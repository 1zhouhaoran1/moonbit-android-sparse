#!/usr/bin/env node
import { openSync, closeSync, readSync, writeSync, readFileSync, statSync, existsSync, linkSync, renameSync, unlinkSync } from 'node:fs';
import { resolve, dirname, join, basename } from 'node:path';
import { randomUUID } from 'node:crypto';
import * as codec from './generated/sparse.js';

const MiB = 1024 * 1024;
const args = process.argv.slice(2).filter((arg, index) => !(index === 0 && arg === '--'));
const command = args.shift();
const help = 'Usage: pnpm cli <inspect|validate|expand|pack> INPUT [OUTPUT] [--json] [--crc|--no-crc] [--force] [--block-size N] [--max-output N]';

function parseOptions(values) {
  const options = { paths: [], json: false, crc: false, noCrc: false, force: false, blockSize: 4096, maxOutput: 64 * 1024 * MiB };
  for (let index = 0; index < values.length; index++) {
    const value = values[index];
    if (value === '--json') options.json = true;
    else if (value === '--crc') options.crc = true;
    else if (value === '--no-crc') options.noCrc = true;
    else if (value === '--force') options.force = true;
    else if (value === '--block-size' || value === '--max-output') {
      const number = Number(values[++index]);
      if (!Number.isSafeInteger(number) || number <= 0) throw new Error(`${value} requires a positive safe integer`);
      options[value === '--block-size' ? 'blockSize' : 'maxOutput'] = number;
    } else if (value.startsWith('--')) throw new Error(`Unknown option: ${value}`);
    else options.paths.push(value);
  }
  if (options.crc && options.noCrc) throw new Error('Choose either --crc or --no-crc');
  return options;
}

function requireOk(text) {
  const result = JSON.parse(text);
  if (!result.ok) {
    const error = new Error(`${result.error.message} (input byte ${result.error.offset})`);
    error.report = result;
    throw error;
  }
  return result;
}

function readIntoSession(input, handle) {
  const file = openSync(input, 'r');
  try {
    const buffer = Buffer.allocUnsafe(MiB);
    for (;;) {
      const length = readSync(file, buffer, 0, buffer.length, null);
      if (length === 0) break;
      requireOk(codec.feed_inspector(handle, buffer.subarray(0, length)));
    }
    return requireOk(codec.finish_inspector(handle));
  } finally {
    closeSync(file);
  }
}

function writeAll(file, data) {
  let offset = 0;
  while (offset < data.length) {
    const written = writeSync(file, data, offset, data.length - offset);
    if (written <= 0) throw new Error('Output stopped accepting data');
    offset += written;
  }
}

function outputTransaction(input, destination, force, operation) {
  const output = resolve(destination);
  if (resolve(input) === output) throw new Error('Input and output paths must differ');
  if (!force && existsSync(output)) throw new Error('Output exists; choose another path or pass --force');
  const temporary = join(dirname(output), `.${basename(output)}.${randomUUID()}.tmp`);
  let file;
  try {
    file = openSync(temporary, 'wx');
    const result = operation(file);
    closeSync(file);
    file = undefined;
    if (force) renameSync(temporary, output);
    else {
      // A hard link publishes atomically without replacing a racing destination.
      linkSync(temporary, output);
      unlinkSync(temporary);
    }
    return result;
  } finally {
    if (file !== undefined) closeSync(file);
    if (existsSync(temporary)) unlinkSync(temporary);
  }
}

let options;
try {
  if (!command || command === '--help' || command === 'help') {
    console.log(help);
  } else {
    if (!['inspect', 'validate', 'expand', 'pack'].includes(command)) throw new Error(help);
    options = parseOptions(args);
    const [input, output] = options.paths;
    const needsOutput = command === 'pack' || command === 'expand';
    if (!input || (needsOutput && !output) || options.paths.length !== (needsOutput ? 2 : 1)) throw new Error(help);
    if (!statSync(input).isFile()) throw new Error('Input must be a regular file');
    const verifyCrc = !options.noCrc && (command !== 'inspect' || options.crc);
    let report;
    if (command === 'pack') {
      if (options.blockSize > 0x7fffffff || options.blockSize % 4 !== 0) throw new Error('Block size must be a positive multiple of four within signed 32-bit range');
      const size = statSync(input).size;
      if (size > 64 * MiB) throw new Error('The convenience pack command accepts at most 64 MiB of raw input');
      if (size === 0 || size % options.blockSize !== 0) throw new Error('Raw input must contain complete blocks; partial final blocks are rejected');
      const packed = codec.pack_bytes(readFileSync(input), options.blockSize);
      if (packed.length > options.maxOutput) throw new Error('Serialized output exceeds --max-output');
      outputTransaction(input, output, options.force, file => writeAll(file, packed));
      report = { ok: true, command, inputBytes: String(size), outputBytes: String(packed.length), output: resolve(output) };
    } else if (command === 'expand') {
      report = outputTransaction(input, output, options.force, file => {
        const handle = codec.create_expander(verifyCrc, options.maxOutput, bytes => writeAll(file, bytes));
        if (handle < 0) throw new Error('Unable to create expansion session');
        try { return readIntoSession(input, handle); }
        finally { codec.dispose_inspector(handle); }
      });
    } else {
      const handle = codec.create_inspector(verifyCrc);
      if (handle < 0) throw new Error('Unable to create inspection session');
      try { report = readIntoSession(input, handle); }
      finally { codec.dispose_inspector(handle); }
    }
    if (options.json) console.log(JSON.stringify(report, null, 2));
    else if (command === 'pack') console.log(`Packed ${report.inputBytes} bytes into ${report.outputBytes} bytes: ${report.output}`);
    else console.log(`${command}: valid; ${report.chunksRead} chunks; ${report.outputBytes} logical bytes; CRC ${report.crcStatus}`);
  }
} catch (error) {
  if (options?.json) console.log(JSON.stringify(error.report ?? { ok: false, error: { offset: '0', message: error.message ?? String(error) } }, null, 2));
  else console.error(error.message ?? String(error));
  process.exitCode = 1;
}
