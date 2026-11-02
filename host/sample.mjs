import { mkdirSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import * as codec from './generated/sparse.js';

const directory = new URL('../output/', import.meta.url);
mkdirSync(directory, { recursive: true });
const destination = new URL('synthetic.sparse.img', directory);
writeFileSync(destination, codec.make_sample());
console.log(`Synthetic example: ${fileURLToPath(destination)}`);
