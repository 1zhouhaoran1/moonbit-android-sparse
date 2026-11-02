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
assert.deepEqual(report.chunks.map(chunk => chunk.kind), ['RAW', 'FILL', 'DONT_CARE', 'FILL', 'CRC32']);
assert.equal(cli('expand', input, raw).status, 0);
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
const failingHandle = codec.create_expander(false, largerRaw.length, () => { throw new Error('injected output failure'); });
try {
  assert.equal(JSON.parse(codec.feed_inspector(failingHandle, largerImage)).ok, false, 'A host sink exception is reported');
  assert.equal(JSON.parse(codec.feed_inspector(failingHandle, new Uint8Array())).ok, false, 'Failed host sessions cannot resume');
} finally { codec.dispose_inspector(failingHandle); }
console.log('Host integration: independent bytes, bounded sink calls, injected sink failure, CRC cleanup, zero semantics, overwrite protection and limits passed.');
