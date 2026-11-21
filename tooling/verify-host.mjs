import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, readFileSync, existsSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import * as codec from '../host/generated/sparse.js';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const base = process.env.SPARSE_TEST_ROOT || join(tmpdir(), 'android-sparse-tests');
const { mkdirSync } = await import('node:fs');
mkdirSync(base, { recursive: true });
const directory = mkdtempSync(join(base, 'host-test-'));
const input = join(directory, 'synthetic.img');
const raw = join(directory, 'expanded.raw');
const packed = join(directory, 'packed.img');
const cli = (...args) => spawnSync(process.execPath, [join(root, 'host/cli.mjs'), ...args], { encoding: 'utf8', cwd: root });
const sample = codec.make_sample();
assert.equal(sample.length, 4196);
writeFileSync(input, sample);
const inspected = cli('inspect', input, '--json', '--crc');
assert.equal(inspected.status, 0, inspected.stderr || inspected.stdout);
const report = JSON.parse(inspected.stdout);
assert.equal(report.crcStatus, 'verified');
assert.deepEqual(report.allocation, {
  RAW: { chunks: 1, logicalBytes: '4096' },
  FILL: { chunks: 2, logicalBytes: '16384' },
  DONT_CARE: { chunks: 1, logicalBytes: '12288' },
  CRC32: { chunks: 1, logicalBytes: '0' },
});
assert.equal(report.header.fileHeaderSize, 28);
assert.equal(report.header.chunkHeaderSize, 12);
const extendedSample = Buffer.concat([sample.subarray(0, 28), Buffer.alloc(4), sample.subarray(28)]);
extendedSample.writeUInt16LE(32, 8);
const extendedInput = join(directory, 'extended-header.img');
writeFileSync(extendedInput, extendedSample);
const extendedResult = cli('inspect', extendedInput, '--json', '--crc');
assert.equal(extendedResult.status, 0, extendedResult.stderr || extendedResult.stdout);
assert.equal(JSON.parse(extendedResult.stdout).header.fileHeaderSize, 32);
assert.equal(JSON.parse(extendedResult.stdout).chunks[0].inputOffset, '32');
for (const command of ['inspect', 'validate']) {
  const rejected = cli(command, input, '--json', '--max-output', '32767');
  assert.equal(rejected.status, 1);
  assert.match(JSON.parse(rejected.stdout).error.message, /expanded size exceeds/i);
  assert.equal(cli(command, input, '--max-output', '32768').status, 0);
}
assert.deepEqual(report.chunks.map(chunk => chunk.kind), ['RAW', 'FILL', 'DONT_CARE', 'FILL', 'CRC32']);
const validated = cli('validate', input, '--json');
assert.equal(validated.status, 0, validated.stderr || validated.stdout);
assert.deepEqual(JSON.parse(validated.stdout), { ...report, chunks: [] });
const manyChunks = Buffer.alloc(28 + 10001 * 12);
manyChunks.set(sample.subarray(0, 28));
manyChunks.writeUInt32LE(10001, 16);
manyChunks.writeUInt32LE(10001, 20);
manyChunks.writeUInt32LE(0, 24);
for (let i = 28; i < manyChunks.length; i += 12) {
  manyChunks.writeUInt16LE(0xcac3, i);
  manyChunks.writeUInt32LE(1, i + 4);
  manyChunks.writeUInt32LE(12, i + 8);
}
const manyChunksInput = join(directory, 'many-chunks.img');
writeFileSync(manyChunksInput, manyChunks);
assert.equal(cli('inspect', manyChunksInput).status, 1, 'Detailed inspection caps retained rows');
const largeValidation = cli('validate', manyChunksInput, '--json', '--no-crc');
assert.equal(largeValidation.status, 0, largeValidation.stderr || largeValidation.stdout);
assert.equal(JSON.parse(largeValidation.stdout).chunksRead, 10001);
const smallChunkBudget = cli('validate', manyChunksInput, '--no-crc', '--max-chunks', '10000', '--json');
assert.equal(smallChunkBudget.status, 1);
assert.match(JSON.parse(smallChunkBudget.stdout).error.message, /chunk count/);
assert.match(cli('inspect', manyChunksInput, '--max-chunks', '10001').stderr, /use --summary/);
assert.match(cli('validate', input, '--max-chunks', '4294967296').stderr, /unsigned 32-bit/);
const largeSummary = cli('inspect', manyChunksInput, '--summary', '--json');
assert.equal(largeSummary.status, 0, largeSummary.stderr || largeSummary.stdout);
assert.deepEqual(JSON.parse(largeSummary.stdout), JSON.parse(largeValidation.stdout));
const smallCrcBudget = cli('validate', input, '--json', '--max-crc-bytes', '32767');
assert.equal(smallCrcBudget.status, 1);
assert.match(JSON.parse(smallCrcBudget.stdout).error.message, /checksum work/);
assert.equal(cli('validate', input, '--max-crc-bytes', '32768').status, 0);
assert.match(cli('inspect', input, '--max-crc-bytes', '32768').stderr, /requires CRC verification/);
assert.equal(cli('inspect', input, '--crc', '--max-crc-bytes', '32768').status, 0);
assert.equal(cli('expand', input, raw, '--max-crc-bytes', '32767').status, 1);
assert.equal(existsSync(raw), false);
assert.equal(cli('expand', input, raw, '--max-crc-bytes', '32768').status, 0);
const expected = Buffer.alloc(32768);
for (let i = 0; i < 4096; i++) expected[i] = (i * 37 + Math.floor(i / 17)) % 256;
for (let i = 4096; i < 12288; i += 4) expected.writeUInt32LE(0x12345678, i);
assert.deepEqual(readFileSync(raw), expected, 'Expansion must equal independently constructed raw bytes');
assert.equal(cli('pack', raw, packed).status, 0);
const packedReport = JSON.parse(cli('inspect', packed, '--json', '--crc').stdout);
assert.ok(packedReport.chunks.every(chunk => chunk.kind !== 'DONT_CARE'), 'Packing literal zeros must not create holes');
assert.equal(cli('expand', input, raw).status, 1, 'Existing output is protected');
assert.deepEqual(readFileSync(raw), expected);
const corrupt = Buffer.from(sample);
corrupt[corrupt.length - 1] ^= 1;
const corruptInput = join(directory, 'corrupt.img');
writeFileSync(corruptInput, corrupt);
const failedOutput = join(directory, 'should-not-exist.raw');
assert.equal(cli('expand', corruptInput, failedOutput).status, 1);
assert.equal(existsSync(failedOutput), false, 'A failed checksum must not leave a final artifact');
assert.ok(readdirSync(directory).every(name => !name.endsWith('.tmp')), 'Temporary outputs are removed on failure');
const limitedOutput = join(directory, 'limited.raw');
assert.equal(cli('expand', input, limitedOutput, '--max-output', '4096').status, 1);
assert.equal(existsSync(limitedOutput), false);
const partial = join(directory, 'partial.raw');
writeFileSync(partial, Buffer.from([1, 2, 3]));
assert.equal(cli('pack', partial, join(directory, 'partial.img')).status, 1);
const largerRaw = Buffer.alloc(3 * 65536);
for (let i = 0; i < largerRaw.length; i++) largerRaw[i] = (i * 23 + Math.floor(i / 13)) % 256;
const largerImage = codec.pack_bytes(largerRaw, 4096);
const received = [];
const streamingHandle = codec.create_expander(true, largerRaw.length, bytes => {
  assert.ok(bytes.length <= 65536, 'Host sink callbacks are bounded to 64 KiB');
  received.push(Buffer.from(bytes));
});
try {
  assert.equal(JSON.parse(codec.feed_inspector(streamingHandle, largerImage)).ok, true);
  assert.equal(JSON.parse(codec.finish_inspector(streamingHandle)).ok, true);
  assert.deepEqual(Buffer.concat(received), largerRaw);
} finally { codec.dispose_inspector(streamingHandle); }
const explicitHoles = [];
const expandedData = [];
const holeHandle = codec.create_hole_aware_expander(true, expected.length, expected.length, 5,
  bytes => expandedData.push(Buffer.from(bytes)), size => explicitHoles.push(size));
try {
  assert.equal(JSON.parse(codec.feed_inspector(holeHandle, sample)).ok, true);
  assert.equal(JSON.parse(codec.finish_inspector(holeHandle)).crcStatus, 'verified');
  assert.deepEqual(explicitHoles, [12288]);
  assert.deepEqual(Buffer.concat(expandedData), Buffer.concat([expected.subarray(0, 12288), expected.subarray(24576)]));
} finally { codec.dispose_inspector(holeHandle); }
const rejectedSkip = codec.create_hole_aware_expander(false, expected.length, 0, 5, () => {},
  () => { throw new Error('injected skip failure'); });
try {
  const failure = JSON.parse(codec.feed_inspector(rejectedSkip, sample));
  assert.equal(failure.ok, false);
  assert.match(failure.error.message, /injected skip failure/);
} finally { codec.dispose_inspector(rejectedSkip); }
const failingHandle = codec.create_expander(false, largerRaw.length, () => { throw new Error('injected output failure'); });
try {
  assert.equal(JSON.parse(codec.feed_inspector(failingHandle, largerImage)).ok, false, 'A host sink exception is reported');
  assert.equal(JSON.parse(codec.feed_inspector(failingHandle, new Uint8Array())).ok, false, 'Failed host sessions cannot resume');
} finally { codec.dispose_inspector(failingHandle); }
console.log('Host integration: independent bytes, bounded sink calls, injected sink failure, CRC cleanup, zero semantics, overwrite protection and limits passed.');
