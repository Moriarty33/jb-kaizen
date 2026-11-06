#!/usr/bin/env node
'use strict';

const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const packaged = path.join(__dirname, '..', 'dist', 'install-entry.sh');
// A repo checkout has no dist/: it runs the extension tree that holds npm/.
const entry = fs.existsSync(packaged) ? packaged : path.join(__dirname, '..', '..', 'install-entry.sh');

const result = spawnSync('bash', [entry, ...process.argv.slice(2)], { stdio: 'inherit' });
if (result.error) {
  console.error(`jb-kaizen: could not start bash (${result.error.message}) - macOS and Linux only`);
  process.exit(1);
}
process.exit(result.status === null ? 1 : result.status);
