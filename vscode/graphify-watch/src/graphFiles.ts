import { ChildProcess, spawn } from 'node:child_process';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as vscode from 'vscode';
import { log } from './log';
import { GraphStats } from './state';

export interface UpdateHandlers {
  onStdout: (chunk: string) => void;
  onStderr: (chunk: string) => void;
  onError: (err: Error) => void;
  onExit: (code: number | null, signal: NodeJS.Signals | null) => void;
}

export function spawnUpdate(
  python: string,
  cwd: string,
  extraArgs: string[],
  handlers: UpdateHandlers,
): ChildProcess {
  const args = ['-m', 'graphify', 'update', '.', ...extraArgs];
  log(`Running one-shot: ${python} ${args.join(' ')} (cwd=${cwd})`);
  const child = spawn(python, args, {
    cwd,
    env: { ...process.env, PYTHONUNBUFFERED: '1' },
  });
  child.stdout.setEncoding('utf8');
  child.stderr.setEncoding('utf8');
  child.stdout.on('data', handlers.onStdout);
  child.stderr.on('data', handlers.onStderr);
  child.on('error', handlers.onError);
  child.on('exit', handlers.onExit);
  return child;
}

const GRAPH_JSON = 'graph.json';
// Pinned to graphifyy 0.8.36 watch.py: dotless `needs_update` (skill docs show a dotted variant).
const FLAG_FILE = 'needs_update';

interface GraphJson {
  nodes?: unknown[];
  links?: unknown[];
  edges?: unknown[];
}

export function flagExists(outPath: string): boolean {
  try {
    return fs.existsSync(path.join(outPath, FLAG_FILE));
  } catch {
    return false;
  }
}

export function writeFlag(outPath: string): void {
  try {
    fs.mkdirSync(outPath, { recursive: true });
    fs.writeFileSync(path.join(outPath, FLAG_FILE), '1', 'utf8');
  } catch (err) {
    log(`Failed to write needs_update flag: ${String(err)}`);
  }
}

export function createFlagWatcher(
  outPath: string,
  onAppear: () => void,
  onClear: () => void,
): vscode.FileSystemWatcher {
  const pattern = new vscode.RelativePattern(outPath, FLAG_FILE);
  const watcher = vscode.workspace.createFileSystemWatcher(pattern);
  watcher.onDidCreate(onAppear);
  watcher.onDidChange(onAppear);
  watcher.onDidDelete(onClear);
  return watcher;
}

export function createGraphJsonWatcher(
  outPath: string,
  onChange: () => void,
): vscode.FileSystemWatcher {
  const pattern = new vscode.RelativePattern(outPath, GRAPH_JSON);
  const watcher = vscode.workspace.createFileSystemWatcher(pattern);
  watcher.onDidCreate(onChange);
  watcher.onDidChange(onChange);
  return watcher;
}

export function graphExists(outPath: string): boolean {
  try {
    return fs.existsSync(path.join(outPath, GRAPH_JSON));
  } catch {
    return false;
  }
}

export function graphMtime(outPath: string): number | undefined {
  try {
    return fs.statSync(path.join(outPath, GRAPH_JSON)).mtimeMs;
  } catch {
    return undefined;
  }
}

export function readGraphStats(outPath: string): GraphStats | undefined {
  try {
    const file = path.join(outPath, GRAPH_JSON);
    if (!fs.existsSync(file)) {
      return undefined;
    }
    const data = JSON.parse(fs.readFileSync(file, 'utf8')) as GraphJson;
    const nodes = Array.isArray(data.nodes) ? data.nodes.length : 0;
    const edgeArr = data.links ?? data.edges ?? [];
    const edges = Array.isArray(edgeArr) ? edgeArr.length : 0;
    return { nodes, edges };
  } catch (err) {
    log(`Failed to read stats: ${String(err)}`);
    return undefined;
  }
}

export class LineBuffer {
  private buf = '';

  constructor(private readonly onLine: (line: string) => void) {}

  push(chunk: string): void {
    this.buf += chunk;
    let nl: number;
    while ((nl = this.buf.indexOf('\n')) >= 0) {
      const line = this.buf.slice(0, nl);
      this.buf = this.buf.slice(nl + 1);
      this.onLine(line);
    }
  }

  flush(): void {
    if (this.buf.length > 0) {
      const rest = this.buf;
      this.buf = '';
      this.onLine(rest);
    }
  }

  reset(): void {
    this.buf = '';
  }
}
