// Run after tooling/compile-bridge.mjs and reference/aosp/build.sh. No external Node packages.
// Set a cache-directory argument and --wsl=<distribution> when using WSL.
// Add --prepare to exercise the real MoonBit bridge without claiming AOSP execution.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import * as codec from '../../host/generated/sparse.js';

const revision = 'f7b2fc8117d44a26866f87392acbc5ad5c54d7a7';
const args = process.argv.slice(2);
const cache = path.resolve(args.find(arg => !arg.startsWith('--')) ?? process.env.SPARSE_REFERENCE_CACHE ?? path.join(tmpdir(), 'android-sparse-reference'));
const distro = args.find(arg => arg.startsWith('--wsl='))?.slice(6);
const prepareOnly = args.includes('--prepare');
const runDir = path.join(cache, `run-${Date.now()}`);
await mkdir(runDir, { recursive: true });
const file = name => path.join(runDir, name);
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const linuxPath = value => value.replace(/^([A-Za-z]):[\\/]/, (_, drive) => `/mnt/${drive.toLowerCase()}/`).replaceAll('\\', '/');
function oracle(mode, ...paths) {
  const binary = path.join(cache, 'oracle');
  return distro
    ? spawnSync('wsl', ['-d', distro, '--', linuxPath(binary), mode, ...paths.map(linuxPath)], { encoding: 'utf8', timeout: 30000 })
    : spawnSync(binary, [mode, ...paths], { encoding: 'utf8', timeout: 30000 });
}
function requireOracle(result, description) {
  assert.equal(result.error, undefined, `${description}: ${result.error}`);
  assert.equal(result.status, 0, `${description}: ${result.stderr}`);
}
function inspect(bytes) {
  const id = codec.create_inspector(true);
  try {
    for (let at = 0; at < bytes.length; at += 17) {
      const result = JSON.parse(codec.feed_inspector(id, bytes.subarray(at, at + 17)));
      if (!result.ok) return result;
    }
    return JSON.parse(codec.finish_inspector(id));
  } finally { codec.dispose_inspector(id); }
}
function expand(bytes, maximum) {
  const parts = [];
  const id = codec.create_expander(true, maximum, data => parts.push(Buffer.from(data)));
  try {
    for (let at = 0; at < bytes.length; at += 31) {
      assert.equal(JSON.parse(codec.feed_inspector(id, bytes.subarray(at, at + 31))).ok, true);
    }
    assert.equal(JSON.parse(codec.finish_inspector(id)).ok, true);
    return Buffer.concat(parts);
  } finally { codec.dispose_inspector(id); }
}
const expected = Buffer.alloc(8 * 4096);
for (let i = 0; i < 4096; i++) expected[i] = (i * 37 + Math.floor(i / 17)) % 256;
for (let i = 4096; i < 3 * 4096; i += 4) expected.writeUInt32LE(0x12345678, i);
const sample = Buffer.from(codec.make_sample());
const sampleReport = inspect(sample);
assert.equal(sampleReport.ok, true);
assert.equal(sampleReport.crcStatus, 'verified');
assert.deepEqual(sampleReport.chunks.map(chunk => chunk.kind), ['RAW', 'FILL', 'DONT_CARE', 'FILL', 'CRC32']);
assert.deepEqual(expand(sample, expected.length), expected);
const packed = Buffer.from(codec.pack_bytes(expected, 4096));
assert.equal(inspect(packed).crcStatus, 'verified');
assert.deepEqual(expand(packed, expected.length), expected);
await writeFile(file('moon-sample.sparse'), sample, { flag: 'wx' });
await writeFile(file('moon-pack.sparse'), packed, { flag: 'wx' });
await writeFile(file('expected.raw'), expected, { flag: 'wx' });
const summary = {
  revision, checkedAt: new Date().toISOString(), runDir,
  moonBitBridgeExecuted: true, aospExecuted: false,
  moonSampleSha256: hash(sample), moonPackSha256: hash(packed), expandedSha256: hash(expected),
};
if (!prepareOnly) {
  assert.equal((await readFile(path.join(cache, 'revision.txt'), 'utf8')).trim(), revision);
  for (const name of ['moon-sample', 'moon-pack']) {
    requireOracle(oracle('verify', file(`${name}.sparse`)), `AOSP CRC verification of ${name}`);
    requireOracle(oracle('expand', file(`${name}.sparse`), file(`${name}.aosp.raw`)), `AOSP expansion of ${name}`);
    assert.deepEqual(await readFile(file(`${name}.aosp.raw`)), expected);
  }
  const corrupt = Buffer.from(sample);
  corrupt[corrupt.length - 1] ^= 1;
  await writeFile(file('corrupt.sparse'), corrupt, { flag: 'wx' });
  const rejection = oracle('verify', file('corrupt.sparse'));
  assert.equal(rejection.error, undefined);
  assert.equal(rejection.status, 1, 'AOSP must reject the corrupt CRC');
  assert.equal(inspect(corrupt).ok, false);
  requireOracle(oracle('make', file('aosp.sparse'), file('aosp.expected.raw')), 'AOSP fixture generation');
  requireOracle(oracle('verify', file('aosp.sparse')), 'AOSP self-verification');
  const independent = await readFile(file('aosp.sparse'));
  const independentExpected = await readFile(file('aosp.expected.raw'));
  assert.equal(inspect(independent).crcStatus, 'verified');
  assert.deepEqual(expand(independent, independentExpected.length), independentExpected);
  // Preserve the pinned writer's multi-block FILL/hole behavior; never repair its CRC.
  requireOracle(oracle('make-mixed', file('aosp-mixed.sparse'), file('aosp-mixed.expected.raw')), 'AOSP mixed fixture generation');
  const mixedVerification = oracle('verify', file('aosp-mixed.sparse'));
  assert.equal(mixedVerification.error, undefined);
  assert.ok([0, 1].includes(mixedVerification.status));
  const mixedReport = inspect(await readFile(file('aosp-mixed.sparse')));
  assert.equal(mixedReport.ok, mixedVerification.status === 0, 'MoonBit and AOSP disagree on mixed fixture CRC');
  summary.aospExecuted = true;
  summary.moonToAospCrc = 'passed';
  summary.aospToMoonCrc = 'passed';
  summary.corruptCrcRejection = 'passed';
  summary.aospMixedWriterSelfVerification = mixedVerification.status === 0 ? 'accepted' : 'rejected: pinned upstream writer CRC limitation';
  summary.aospFixtureSha256 = hash(independent);
}
await writeFile(file('result.json'), `${JSON.stringify(summary, null, 2)}\n`, { flag: 'wx' });
console.log(JSON.stringify(summary, null, 2));
