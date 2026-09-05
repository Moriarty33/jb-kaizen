import { ChildProcess } from 'node:child_process';
import { LineBuffer, readGraphStats, spawnUpdate } from './graphFiles';
import { log, logWatcher } from './log';
import { decideRun, parseShrinkLine, ShrinkInfo } from './runDecision';
import { GraphStats, parseWatcherLine } from './state';

const KILL_GRACE_MS = 3000;

export interface UpdateOutcome {
  ok: boolean;
  stats?: GraphStats;
  error?: string;
  shrinkRefused?: boolean;
}

interface RunnerDeps {
  python: string;
  cwd: string;
  outPath: string;
  autoForceShrinkPercent: () => number;
  onStart: () => void;
  onFinish: (outcome: UpdateOutcome) => void;
}

export class UpdateRunner {
  private child?: ChildProcess;
  private killTimer?: NodeJS.Timeout;
  private queued = false;
  private disposed = false;

  private readonly stdout = new LineBuffer((line) => this.handleStdoutLine(line));
  private readonly stderr = new LineBuffer((line) => this.handleStderrLine(line));
  private stats?: GraphStats;
  private parsedError?: string;
  private spawnError?: string;
  private shrink?: ShrinkInfo;
  private lastStderrLine?: string;
  private forceAttempted = false;

  constructor(private readonly deps: RunnerDeps) {}

  get isRunning(): boolean {
    return this.child !== undefined;
  }

  request(): void {
    if (this.disposed) {
      return;
    }
    if (this.child) {
      this.queued = true;
      return;
    }
    this.launch(false);
  }

  requestForce(): void {
    if (this.disposed) {
      return;
    }
    if (this.child) {
      this.queued = true;
      return;
    }
    this.launch(true);
  }

  private launch(force: boolean): void {
    this.resetRunState();
    this.forceAttempted = force;
    this.deps.onStart();
    this.child = spawnUpdate(this.deps.python, this.deps.cwd, force ? ['--force'] : [], {
      onStdout: (chunk) => this.stdout.push(chunk),
      onStderr: (chunk) => this.stderr.push(chunk),
      onError: (err) => {
        this.spawnError = err.message;
        this.finish(null);
      },
      onExit: (code) => this.finish(code),
    });
  }

  private resetRunState(): void {
    this.stdout.reset();
    this.stderr.reset();
    this.stats = undefined;
    this.parsedError = undefined;
    this.spawnError = undefined;
    this.shrink = undefined;
    this.lastStderrLine = undefined;
  }

  private handleStdoutLine(raw: string): void {
    if (!raw.trim()) {
      return;
    }
    logWatcher(raw);
    const parsed = parseWatcherLine(raw);
    if (parsed.stats) {
      this.stats = parsed.stats;
    }
    if (parsed.error) {
      this.parsedError = parsed.error;
    }
    this.shrink = parseShrinkLine(raw) ?? this.shrink;
  }

  private handleStderrLine(raw: string): void {
    const line = raw.trim();
    if (!line) {
      return;
    }
    logWatcher(raw);
    this.lastStderrLine = line;
    this.shrink = parseShrinkLine(line) ?? this.shrink;
  }

  private finish(code: number | null): void {
    this.stdout.flush();
    this.stderr.flush();
    this.clearKillTimer();
    this.child = undefined;
    if (this.disposed) {
      return;
    }

    const verdict = decideRun({
      exitCode: code,
      spawnError: this.spawnError,
      parsedError: this.parsedError,
      shrink: this.shrink,
      lastStderrLine: this.lastStderrLine,
      forceAttempted: this.forceAttempted,
      autoForceShrinkPercent: this.deps.autoForceShrinkPercent(),
    });
    log(`graphify update finished (code=${code}, verdict=${verdict.kind}).`);

    if (verdict.kind === 'retryWithForce') {
      log(`Auto-retrying with --force: ${verdict.reason}`);
      this.queued = false;
      this.launch(true);
      return;
    }

    const outcome: UpdateOutcome =
      verdict.kind === 'ok'
        ? { ok: true, stats: this.stats ?? readGraphStats(this.deps.outPath) }
        : { ok: false, error: verdict.message, shrinkRefused: verdict.shrinkRefused };
    this.deps.onFinish(outcome);

    if (this.queued) {
      this.queued = false;
      this.launch(false);
    }
  }

  private clearKillTimer(): void {
    if (this.killTimer) {
      clearTimeout(this.killTimer);
      this.killTimer = undefined;
    }
  }

  kill(): void {
    this.queued = false;
    const child = this.child;
    if (!child) {
      return;
    }
    child.kill('SIGINT');
    this.clearKillTimer();
    this.killTimer = setTimeout(() => {
      this.killTimer = undefined;
      if (!child.killed) {
        child.kill('SIGKILL');
      }
    }, KILL_GRACE_MS);
  }

  dispose(): void {
    this.disposed = true;
    this.kill();
  }
}
