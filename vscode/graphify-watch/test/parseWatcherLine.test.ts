import * as assert from 'node:assert';
import { GraphStats, parseWatcherLine, WatcherState } from '../src/state';

interface Case {
  name: string;
  input: string;
  state?: WatcherState;
  stats?: GraphStats;
  debounce?: number;
  error?: string;
  flagWritten?: boolean;
  noise?: boolean;
}

const P = '[graphify watch] ';

const cases: Case[] = [
  {
    name: 'watching',
    input: `${P}Watching /Users/x/repo - press Ctrl+C to stop`,
    state: WatcherState.Watching,
  },
  {
    name: 'watching with leading newline',
    input: `\n${P}Watching /a/b - press Ctrl+C to stop`,
    state: WatcherState.Watching,
  },
  {
    name: 'noise code-changes line',
    input: `${P}Code changes rebuild graph automatically. Doc/image changes need LLM.`,
    noise: true,
  },
  { name: 'debounce float', input: `${P}Debounce: 3.0s`, debounce: 3.0 },
  { name: 'debounce int', input: `${P}Debounce: 5s`, debounce: 5 },
  { name: 'files changed', input: `${P}3 file(s) changed`, state: WatcherState.Indexing },
  {
    name: 'files changed with leading newline',
    input: `\n${P}1 file(s) changed`,
    state: WatcherState.Indexing,
  },
  {
    name: 'rebuilt clustered',
    input: `${P}Rebuilt: 1200 nodes, 3400 edges, 42 communities`,
    stats: { nodes: 1200, edges: 3400 },
  },
  {
    name: 'rebuilt no clustering',
    input: `${P}Rebuilt (no clustering): 10 nodes, 20 edges`,
    stats: { nodes: 10, edges: 20 },
  },
  {
    name: 'graph.json updated',
    input: `${P}graph.json updated in /Users/x/repo/graphify-out`,
    state: WatcherState.Watching,
  },
  {
    name: 'multiple products updated',
    input: `${P}graph.json, graph.html and GRAPH_REPORT.md updated in /out`,
    state: WatcherState.Watching,
  },
  {
    name: 'no code-graph changes',
    input: `${P}No code-graph changes detected; graph.json/GRAPH_REPORT.md left untouched.`,
    state: WatcherState.Watching,
  },
  {
    name: 'no topology changes',
    input: `${P}No code-graph topology changes detected; outputs left untouched.`,
    state: WatcherState.Watching,
  },
  {
    name: 'no changes no-cluster',
    input: `${P}No code-graph changes detected (--no-cluster); outputs left untouched.`,
    state: WatcherState.Watching,
  },
  {
    name: 'no code files',
    input: `${P}No code files found - nothing to rebuild.`,
    state: WatcherState.Watching,
  },
  {
    name: 'rebuild already in progress stays indexing',
    input: `${P}Rebuild already in progress for /Users/x/repo - changes queued.`,
    state: WatcherState.Indexing,
  },
  {
    name: 'rebuild failed',
    input: `${P}Rebuild failed: boom went the thing`,
    state: WatcherState.Error,
    error: 'boom went the thing',
  },
  {
    name: 'new or changed files precursor is noise',
    input: `${P}New or changed files detected in /Users/x/repo`,
    noise: true,
  },
  {
    name: 'non-code files changed',
    input: `${P}Non-code files changed - semantic re-extraction requires LLM.`,
    state: WatcherState.UpdateNeeded,
  },
  {
    name: 'flag written confirms update needed',
    input: `${P}Flag written to /Users/x/repo/graphify-out/needs_update`,
    state: WatcherState.UpdateNeeded,
    flagWritten: true,
  },
  { name: 'stopped', input: `${P}Stopped.`, state: WatcherState.Stopped },
  {
    name: 'graphify update preamble is noise',
    input: 'Re-extracting code files in . (no LLM needed)...',
    noise: true,
  },
  {
    name: 'graphify update success tail is noise',
    input: 'Code graph updated. For doc/paper/image changes run /graphify --update in your AI assistant.',
    noise: true,
  },
  { name: 'unprefixed unknown line is noise', input: 'random output', noise: true },
  { name: 'empty line is noise', input: `${P}   `, noise: true },
];

let passed = 0;
const failures: string[] = [];

for (const c of cases) {
  const result = parseWatcherLine(c.input);
  try {
    assert.deepStrictEqual(result.state, c.state, 'state');
    assert.deepStrictEqual(result.stats, c.stats, 'stats');
    assert.deepStrictEqual(result.debounce, c.debounce, 'debounce');
    assert.deepStrictEqual(result.error, c.error, 'error');
    assert.deepStrictEqual(result.flagWritten, c.flagWritten, 'flagWritten');
    assert.deepStrictEqual(result.noise, c.noise, 'noise');
    passed += 1;
  } catch (err) {
    failures.push(`FAIL ${c.name}: ${(err as Error).message}\n  got: ${JSON.stringify(result)}`);
  }
}

console.log(`parseWatcherLine: ${passed}/${cases.length} passed`);
if (failures.length > 0) {
  console.error(failures.join('\n'));
  process.exit(1);
}
