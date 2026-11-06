#!/usr/bin/env node
'use strict';

// A package cannot ship files above its own folder, so prepack copies the installer tree into dist/.
const fs = require('node:fs');
const path = require('node:path');

const here = __dirname;
const root = path.resolve(here, '..');
const dist = path.join(here, 'dist');
const tree = ['install-entry.sh', 'install.sh', 'uninstall.sh', 'VERSION', 'LICENSE', '.claude-plugin', 'hooks', 'lib', 'skills', 'templates'];
const pageFiles = ['README.md', 'LICENSE'];
const rawBase = 'https://raw.githubusercontent.com/Moriarty33/jb-kaizen/main/';

const skipped = (name) => name.includes('.bak-') || name === '__pycache__' || name === '.DS_Store';

function copy(from, to) {
  const stat = fs.statSync(from);
  if (stat.isDirectory()) {
    fs.mkdirSync(to, { recursive: true });
    for (const name of fs.readdirSync(from)) {
      if (!skipped(name)) copy(path.join(from, name), path.join(to, name));
    }
    return;
  }
  fs.copyFileSync(from, to);
  fs.chmodSync(to, stat.mode);
}

fs.rmSync(dist, { recursive: true, force: true });
for (const name of pageFiles) fs.rmSync(path.join(here, name), { force: true });
if (process.argv.includes('--clean')) process.exit(0);

fs.mkdirSync(dist, { recursive: true });
for (const entry of tree) copy(path.join(root, entry), path.join(dist, entry));
const readme = fs.readFileSync(path.join(root, 'README.md'), 'utf8').replace(/(src|srcset)="docs\//g, `$1="${rawBase}docs/`);
fs.writeFileSync(path.join(here, 'README.md'), readme);
fs.copyFileSync(path.join(root, 'LICENSE'), path.join(here, 'LICENSE'));
