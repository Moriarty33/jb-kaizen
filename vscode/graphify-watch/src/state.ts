export enum WatcherState {
  Idle = 'idle',
  Watching = 'watching',
  Indexing = 'indexing',
  UpdateNeeded = 'updateNeeded',
  Error = 'error',
  Stopped = 'stopped',
  Attached = 'attached',
}

export interface GraphStats {
  nodes: number;
  edges: number;
}

export interface ParsedLine {
  state?: WatcherState;
  stats?: GraphStats;
  debounce?: number;
  error?: string;
  flagWritten?: boolean;
  noise?: boolean;
}

const WATCH_PREFIX = '[graphify watch] ';

export function stripPrefix(raw: string): string {
  const trimmed = raw.replace(/^\s+/, '');
  return trimmed.startsWith(WATCH_PREFIX)
    ? trimmed.slice(WATCH_PREFIX.length).trim()
    : trimmed.trim();
}

const WATCHING_RE = /^Watching .* press Ctrl\+C/;
const DEBOUNCE_RE = /^Debounce: ([\d.]+)s/;
const CHANGED_RE = /^\d+ file\(s\) changed/;
const REBUILT_RE = /^Rebuilt(?: \(no clustering\))?: (\d+) nodes, (\d+) edges/;
const PRODUCTS_RE = /(?:graph\.json|GRAPH_REPORT\.md) updated in/;
const NOOP_RE = /^No code.*(left untouched|nothing to rebuild)/;
const IN_PROGRESS_RE = /^Rebuild already in progress/;
const FAILED_RE = /^Rebuild failed: (.*)/;
const NONCODE_RE = /^Non-code files changed/;
const FLAG_RE = /^Flag written to (.*)/;
const STOPPED_RE = /^Stopped\./;
const NOISE_RE = /^Code changes rebuild graph automatically/;
const PRECURSOR_RE = /^New or changed files detected/;

export function parseWatcherLine(raw: string): ParsedLine {
  const line = stripPrefix(raw);
  if (!line) {
    return { noise: true };
  }

  const debounce = DEBOUNCE_RE.exec(line);
  if (debounce) {
    return { debounce: parseFloat(debounce[1]) };
  }

  const rebuilt = REBUILT_RE.exec(line);
  if (rebuilt) {
    return {
      stats: { nodes: Number(rebuilt[1]), edges: Number(rebuilt[2]) },
    };
  }

  const failed = FAILED_RE.exec(line);
  if (failed) {
    return { state: WatcherState.Error, error: failed[1].trim() };
  }

  if (FLAG_RE.test(line)) {
    return { state: WatcherState.UpdateNeeded, flagWritten: true };
  }

  if (NONCODE_RE.test(line)) {
    return { state: WatcherState.UpdateNeeded };
  }

  if (WATCHING_RE.test(line)) {
    return { state: WatcherState.Watching };
  }

  if (CHANGED_RE.test(line)) {
    return { state: WatcherState.Indexing };
  }

  if (IN_PROGRESS_RE.test(line)) {
    return { state: WatcherState.Indexing };
  }

  if (PRODUCTS_RE.test(line) || NOOP_RE.test(line)) {
    return { state: WatcherState.Watching };
  }

  if (STOPPED_RE.test(line)) {
    return { state: WatcherState.Stopped };
  }

  if (NOISE_RE.test(line) || PRECURSOR_RE.test(line)) {
    return { noise: true };
  }

  return { noise: true };
}
