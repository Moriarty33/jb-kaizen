import * as assert from 'node:assert';
import { isIgnoredPath } from '../src/pathFilter';

interface Case {
  name: string;
  path: string;
  ignored: boolean;
}

const OUT = 'graphify-out';

const cases: Case[] = [
  { name: 'plain source file', path: 'src/index.ts', ignored: false },
  { name: 'nested source file', path: 'apps/web/src/main.tsx', ignored: false },
  { name: 'outDir flag', path: 'graphify-out/needs_update', ignored: true },
  { name: 'dotted segment', path: '.git/config', ignored: true },
  { name: 'nested dotted segment', path: 'src/.cache/x.js', ignored: true },
  { name: 'node_modules at root', path: 'node_modules/pkg/index.js', ignored: true },
  { name: 'nested node_modules', path: 'apps/web/node_modules/dep/lib.js', ignored: true },
  { name: 'dist output', path: 'dist/bundle.js', ignored: true },
  { name: 'build output', path: 'packages/x/build/out.js', ignored: true },
  { name: 'pycache', path: 'pkg/__pycache__/mod.pyc', ignored: true },
  { name: 'windows-style node_modules', path: 'apps\\web\\node_modules\\dep\\lib.js', ignored: true },
];

let passed = 0;
const failures: string[] = [];

for (const c of cases) {
  try {
    assert.strictEqual(isIgnoredPath(c.path, OUT), c.ignored);
    passed += 1;
  } catch {
    failures.push(`FAIL ${c.name}: ${c.path} expected ignored=${c.ignored}`);
  }
}

console.log(`pathFilter: ${passed}/${cases.length} passed`);
if (failures.length > 0) {
  console.error(failures.join('\n'));
  process.exit(1);
}
