# Graphify Watch

A VS Code extension that keeps a [`graphify`](https://pypi.org/project/graphifyy/) knowledge graph
up to date using **native VS Code file watching** and **on-demand one-shot rebuilds**, surfacing the
live state in the status bar. Pinned and verified against **graphifyy 0.8.36**.

## What it does

- **No long-lived python process.** It does not spawn `graphify.watch`. Instead it uses
  `vscode.workspace.createFileSystemWatcher` (kernel-backed). That watcher honors the user's
  `files.watcherExclude` setting, so `node_modules/`, `.git/`, etc. are excluded for free and idle
  CPU is effectively zero - no more polling `os.walk`/`stat` over the whole tree.
- Change events are filtered in TypeScript (mirroring `graphify/watch.py`'s handler: ignore
  `graphify-out/`, any path segment starting with `.`, and any extension not in graphify's watched
  set) and debounced by `graphifyWatch.debounce` seconds.
- When a debounced batch matures:
  - if it contains any **code** file, it runs a one-shot `<python> -m graphify update .`
    (cwd = folder). This is graphify's AST-only rebuild - no LLM. It prints the same
    `[graphify watch] ...` lines as the old watcher because both call the shared `_rebuild_code`.
  - if it contains any **non-code** watched file (doc/paper/image), it writes the
    `graphify-out/needs_update` flag and reflects the **update needed** state. A code-only rebuild
    unlinks that flag on success, clearing the state automatically.
  - in a **mixed** batch (code + non-code) the code rebuild runs first; because
    `graphify update` unlinks the flag on success, the extension re-asserts the
    `needs_update` flag and the **update needed** state *after* the rebuild finishes, so the
    "doc/image change needs LLM re-extraction" signal survives the code rebuild.
- **Authoritative extension sets:** on first activation it runs the resolved interpreter once to read
  `graphify.detect`'s `CODE_EXTENSIONS`/`DOC_EXTENSIONS`/`PAPER_EXTENSIONS`/`IMAGE_EXTENSIONS` and
  caches them (avoids drift). If that probe fails it logs the fact and falls back to a hardcoded set.
- **Concurrency:** never two `graphify update` runs at once. A batch maturing during an in-flight run
  coalesces into a single pending run (queue depth 1). The in-flight child stays killable
  (SIGINT -> 3s grace -> SIGKILL).
- Watches `graphify-out/needs_update` (flips update-needed <-> watching) and `graphify-out/graph.json`
  (refreshes node/edge stats and last-indexed mtime).
- Coordinates between VS Code windows via an extension-owned `graphify-out/.watch.lock`
  (PID + heartbeat). A second window that finds a fresh lock shows the **attached** state instead
  of running a duplicate watcher; it still reflects stats and the update-needed flag via file watchers.
  Stale locks are taken over after a 10s recheck.

> Note: `.watch.lock` is owned entirely by this extension. graphify's own `.rebuild.lock` flock still
> serializes any accidental concurrent `graphify update` runs as a backstop; this extension never
> touches it.

## Status bar states

The status bar item is **right-aligned** (priority 100).

| State          | Icon                | Background        | Meaning |
| -------------- | ------------------- | ----------------- | ------- |
| idle           | `$(circle-outline)` | -                 | Not running |
| watching       | `$(eye)`            | -                 | Graph up to date, watching |
| indexing       | `$(sync~spin)`      | -                 | Running a one-shot `graphify update` from code changes |
| update needed  | `$(warning)`        | warningBackground | Non-code changes need an LLM re-extraction (`/graphify --update`) |
| error          | `$(error)`          | errorBackground   | The last `graphify update` failed |
| stopped        | `$(primitive-square)` | -               | Watcher stopped |
| attached       | `$(link)`           | -                 | Another window owns the watcher for this folder |

Click the item (or run **Graphify Watch: Show Menu**) for Start / Stop / Restart / Rebuild now /
Open graph / Show log / Settings. **Rebuild now** triggers a single `graphify update` without tearing
down the watcher; **Restart** tears down and re-creates the watcher, then triggers one rebuild. The
hover tooltip exposes the same actions as trusted command links.

## Commands

`graphifyWatch.start`, `.stop`, `.restart`, `.rebuildNow`, `.openGraph`, `.showLog`,
`.openSettings`, `.showMenu`.

## Settings

| Key | Default | Description |
| --- | ------- | ----------- |
| `graphifyWatch.autoStart` | `true` | Start the watcher for each folder on activation |
| `graphifyWatch.autoForceShrinkPercent` | `5` | Auto-retry a shrink-guard-refused rebuild once with `--force` when the node-count shrink is at most this percent (0 disables) |
| `graphifyWatch.debounce` | `3` | Seconds to wait after the last change before running `graphify update` |
| `graphifyWatch.pythonPath` | `""` | Explicit interpreter; empty = auto-resolve |
| `graphifyWatch.outDir` | `graphify-out` | Output dir relative to the folder |
| `graphifyWatch.showNotifications` | `true` | Notify on error / update-needed |
| `graphifyWatch.staleLockSeconds` | `30` | Age after which another window's lock is stale |

## Interpreter resolution

In order: `graphifyWatch.pythonPath` -> `graphify-out/.graphify_python` -> `uv tool run graphifyy
python -c "import sys;print(sys.executable)"` -> `python3`. Each candidate is verified with
`spawnSync(py, ["-c", "import graphify"])` (exit 0). `watchdog` is **no longer required at runtime**
- this extension no longer spawns `graphify.watch`, and `graphify update` does not need watchdog.

## Development

```bash
npm install
npm run build      # esbuild bundle -> dist/extension.js
npm run lint       # tsc --noEmit (strict)
npm test           # runs the parseWatcherLine table test offline (tsx)
```

Press **F5** in VS Code to launch an Extension Development Host with the watcher loaded.
`npm run watch` keeps esbuild rebuilding on save.

## Build, package, install

```bash
npm run package                 # lint + production esbuild bundle
npx vsce package                # produces graphify-watch-<version>.vsix
code --install-extension graphify-watch-0.1.0.vsix
```

## stdout contract (`graphify update` -> extension state)

We now parse the stdout of the one-shot `graphify update .`. Because `graphify update` and the old
`graphify.watch` both call the shared `_rebuild_code`, the rebuild lines are identical and the same
pure `parseWatcherLine` function still applies. Rebuild lines are prefixed with `[graphify watch] `
(occasionally with a leading newline); the prefix is stripped, then matched with contains-anchored
regexes. The `Re-extracting code files in ... (no LLM needed)...` preamble and the
`Code graph updated. ...` tail printed by the `update` subcommand are unprefixed and treated as noise.
The authoritative mapping:

| Line (after prefix) | State |
| --- | --- |
| `Watching <abspath> - press Ctrl+C to stop` | watching (watch-loop only; not emitted by `update`) |
| `Code changes rebuild graph automatically...` | noise (ignored) |
| `Debounce: <n>s` | sets debounce (watch-loop only; not emitted by `update`) |
| `<n> file(s) changed` | indexing |
| `Rebuilt: <N> nodes, <M> edges, <K> communities` | stats `{nodes, edges}` |
| `Rebuilt (no clustering): <N> nodes, <M> edges` | stats `{nodes, edges}` |
| `graph.json updated in <dir>` | watching |
| `<products> updated in <dir>` | watching |
| `No code-graph changes detected; ... left untouched.` | watching |
| `No code-graph topology changes detected; outputs left untouched.` | watching |
| `No code-graph changes detected (--no-cluster); outputs left untouched.` | watching |
| `No code files found - nothing to rebuild.` | watching |
| `Rebuild already in progress for <path> - changes queued.` | stays indexing |
| `Rebuild failed: <msg>` | error (`error=msg`) |
| `New or changed files detected in <path>` | noise (precursor) |
| `Non-code files changed - semantic re-extraction requires LLM.` | update needed |
| `Flag written to <path>` | confirms update needed |
| `Stopped.` | stopped |

The `graph.json` shape used for the initial stats read has the edge array under `links` (with
`edges` as a fallback): `nodes.length` and `(links ?? edges ?? []).length`.
