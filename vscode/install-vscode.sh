#!/usr/bin/env bash
# install-vscode.sh - install the bundled VS Code companions through the `code` CLI.
#
#   vscode/install-vscode.sh [claude-launcher] [graphify-watch]     (default: both)
#
# Each companion ships as source plus a prebuilt <name>-<version>.vsix. The .vsix that
# matches package.json's version is installed as is; when it is missing (you edited the
# source and bumped the version) it is rebuilt first with vsce, which needs node + npm.
# Reload the VS Code window afterwards: Cmd/Ctrl+Shift+P -> Developer: Reload Window.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ $# -gt 0 ] || set -- claude-launcher graphify-watch

command -v code >/dev/null 2>&1 || {
  echo "code CLI not found - in VS Code run 'Shell Command: Install code command in PATH' and retry" >&2
  exit 1
}

for name in "$@"; do
  d="$DIR/$name"
  [ -f "$d/package.json" ] || { echo "unknown companion: $name (expected $d/package.json)" >&2; exit 2; }
  version="$(jq -r .version "$d/package.json")"
  vsix="$d/$name-$version.vsix"
  if [ ! -f "$vsix" ]; then
    command -v npm >/dev/null 2>&1 || { echo "$vsix is missing and npm is not available to rebuild it" >&2; exit 1; }
    echo "building $name $version"
    (
      cd "$d"
      # graphify-watch bundles with esbuild from devDependencies; claude-launcher is plain JS.
      [ ! -f package-lock.json ] || [ -d node_modules ] || npm ci --silent
      npx --yes @vscode/vsce package --out "$vsix" >/dev/null
    )
  fi
  echo "installing $name $version"
  code --install-extension "$vsix" --force
done
echo "reload the VS Code window to activate: Developer: Reload Window"
