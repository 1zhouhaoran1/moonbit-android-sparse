import { spawnSync } from 'node:child_process';
import { copyFileSync, mkdirSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const result = spawnSync('moon', ['build', '--target', 'js', '--release', 'kernel/javascript'], { cwd: root, stdio: 'inherit' });
if (result.error) throw result.error;
if (result.status !== 0) process.exit(result.status ?? 1);
const source = join(root, '_build/js/release/build/javascript/javascript.js');
if (!existsSync(source)) throw new Error(`Missing MoonBit artifact: ${source}`);
for (const destination of ['inspector/src/generated/sparse.js', 'host/generated/sparse.js']) {
  const output = join(root, destination);
  mkdirSync(dirname(output), { recursive: true });
  copyFileSync(source, output);
}
console.log('MoonBit JavaScript bridge generated for the CLI and browser.');
