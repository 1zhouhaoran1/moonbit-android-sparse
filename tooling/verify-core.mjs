import { spawnSync } from 'node:child_process';
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
for (const args of [['fmt', '--check'], ['check', '--target', 'wasm-gc', '--deny-warn'], ['check', '--target', 'js', '--deny-warn'], ['build', '--target', 'wasm-gc'], ['build', '--target', 'js'], ['test', '--target', 'wasm-gc'], ['test', '--target', 'js']]) {
  const result = spawnSync('moon', args, { cwd: root, stdio: 'inherit' });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}
