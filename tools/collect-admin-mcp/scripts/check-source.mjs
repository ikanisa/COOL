import { spawnSync } from 'node:child_process';
import { readdirSync } from 'node:fs';
import { extname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const sourceRoot = fileURLToPath(new URL('../src/', import.meta.url));
const supported = new Set(['.mjs', '.js', '.cjs']);
const modules = readdirSync(sourceRoot, { recursive: true, withFileTypes: true })
  .filter(entry => entry.isFile() && supported.has(extname(entry.name)))
  .map(entry => join(entry.parentPath, entry.name))
  .sort();

if (modules.length === 0) throw new Error('No Admin MCP source modules were found.');
for (const path of modules) {
  const result = spawnSync(process.execPath, ['--check', path], { stdio: 'inherit' });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}
console.log(`Syntax checked ${modules.length} Admin MCP source modules.`);
