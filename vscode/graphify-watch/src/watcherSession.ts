import * as path from 'node:path';
import * as vscode from 'vscode';
import { ChangeBatch, ChangeBatcher } from './changeBatcher';
import { GraphifyConfig } from './config';
import {
  createFlagWatcher,
  createGraphJsonWatcher,
  flagExists,
  readGraphStats,
  writeFlag,
} from './graphFiles';
import { resolveExtensionSets } from './extensionSets';
import { decideBatch, decideFinish } from './flagDecision';
import { resolveInterpreter } from './interpreter';
import { log } from './log';
import { GraphStats, WatcherState } from './state';
import { UpdateOutcome, UpdateRunner } from './updateRunner';
import { WatchLock } from './watchLock';

export interface SessionView {
  state: WatcherState;
  stats?: GraphStats;
  error?: string;
}

export class WatcherSession implements vscode.Disposable {
  state: WatcherState = WatcherState.Idle;
  stats?: GraphStats;
  error?: string;

  private batcher?: ChangeBatcher;
  private runner?: UpdateRunner;
  private flagWatcher?: vscode.FileSystemWatcher;
  private graphWatcher?: vscode.FileSystemWatcher;
  private lock?: WatchLock;
  private disposed = false;
  private pendingNonCode = false;
  private errorNotificationVisible = false;

  constructor(
    private readonly folder: vscode.WorkspaceFolder,
    private cfg: GraphifyConfig,
    private readonly onChange: (session: WatcherSession) => void,
  ) {}

  get folderName(): string {
    return this.folder.name;
  }

  private get folderPath(): string {
    return this.folder.uri.fsPath;
  }

  private get outPath(): string {
    return path.join(this.folderPath, this.cfg.outDir);
  }

  get isOwner(): boolean {
    return this.lock?.isOwner ?? false;
  }

  view(): SessionView {
    return { state: this.state, stats: this.stats, error: this.error };
  }

  updateConfig(cfg: GraphifyConfig): void {
    this.cfg = cfg;
  }

  readInitialStats(): void {
    const stats = readGraphStats(this.outPath);
    if (stats) {
      this.stats = stats;
    }
  }

  start(): void {
    if (this.disposed || this.batcher) {
      return;
    }
    this.error = undefined;

    const lock = new WatchLock(this.outPath, this.cfg.staleLockSeconds);
    if (lock.isForeignAndFresh()) {
      this.startAttachedWatchers();
      this.setState(flagExists(this.outPath) ? WatcherState.UpdateNeeded : WatcherState.Attached);
      return;
    }

    const python = resolveInterpreter(this.folderPath, this.cfg.outDir, this.cfg.pythonPath);
    if (!python) {
      this.error = 'Could not find a Python interpreter with graphify installed.';
      this.setState(WatcherState.Error);
      return;
    }
    if (!lock.acquire()) {
      this.startAttachedWatchers();
      this.setState(flagExists(this.outPath) ? WatcherState.UpdateNeeded : WatcherState.Attached);
      return;
    }
    this.lock = lock;

    const sets = resolveExtensionSets(python);
    this.runner = new UpdateRunner({
      python,
      cwd: this.folderPath,
      outPath: this.outPath,
      autoForceShrinkPercent: () => this.cfg.autoForceShrinkPercent,
      onStart: () => this.setState(WatcherState.Indexing),
      onFinish: (outcome) => this.onUpdateFinished(outcome),
    });
    this.batcher = new ChangeBatcher({
      folder: this.folder,
      outDir: this.cfg.outDir,
      sets,
      debounceSeconds: this.cfg.debounce,
      onMature: (batch) => this.onBatchMature(batch),
    });

    this.startFlagWatcher();
    this.startGraphWatcher();

    this.setState(flagExists(this.outPath) ? WatcherState.UpdateNeeded : WatcherState.Watching);
    log(`Native watcher started for ${this.folderName}.`);
  }

  private onBatchMature(batch: ChangeBatch): void {
    if (this.disposed) {
      return;
    }
    const decision = decideBatch(batch);
    if (decision.setPendingNonCode) {
      this.pendingNonCode = true;
    }
    if (decision.writeFlag) {
      writeFlag(this.outPath);
    }
    if (decision.state) {
      this.setState(decision.state);
    }
    if (decision.requestUpdate) {
      this.runner?.request();
    }
  }

  private onUpdateFinished(outcome: UpdateOutcome): void {
    if (this.disposed) {
      return;
    }
    if (!outcome.ok) {
      this.error = outcome.error;
      this.setState(WatcherState.Error);
      void this.offerRetry(outcome.shrinkRefused ?? false);
      return;
    }
    this.error = undefined;
    if (outcome.stats) {
      this.stats = outcome.stats;
    }
    const decision = decideFinish({
      pendingNonCode: this.pendingNonCode,
      flagExists: flagExists(this.outPath),
    });
    this.pendingNonCode = false;
    if (decision.writeFlag) {
      writeFlag(this.outPath);
    }
    this.setState(decision.state);
  }

  private async offerRetry(shrinkRefused: boolean): Promise<void> {
    if (!this.cfg.showNotifications || this.errorNotificationVisible) {
      return;
    }
    this.errorNotificationVisible = true;
    try {
      const message = `Graphify Watch (${this.folderName}) update failed: ${this.error ?? 'unknown error'}`;
      const actions = shrinkRefused
        ? ['Force rebuild', 'Show output']
        : ['Retry', 'Show output'];
      const choice = await vscode.window.showErrorMessage(message, ...actions);
      if (this.disposed) {
        return;
      }
      if (choice === 'Retry' || choice === 'Force rebuild') {
        if (this.state === WatcherState.Error && !this.runner?.isRunning) {
          if (choice === 'Force rebuild') {
            this.runner?.requestForce();
          } else {
            this.runner?.request();
          }
        }
      } else if (choice === 'Show output') {
        void vscode.commands.executeCommand('graphifyWatch.showLog');
      }
    } finally {
      this.errorNotificationVisible = false;
    }
  }

  rebuildNow(): void {
    if (this.disposed) {
      return;
    }
    if (!this.batcher) {
      this.start();
    }
    this.runner?.request();
  }

  stop(): void {
    if (this.state === WatcherState.Attached) {
      this.teardown();
      this.setState(WatcherState.Idle);
      return;
    }
    const wasActive = this.batcher !== undefined;
    this.teardown();
    this.setState(wasActive ? WatcherState.Stopped : WatcherState.Idle);
  }

  restart(): void {
    this.stop();
    this.start();
    this.rebuildNow();
  }

  recheckAttached(): void {
    if (this.state !== WatcherState.Attached) {
      return;
    }
    const lock = new WatchLock(this.outPath, this.cfg.staleLockSeconds);
    if (lock.isStale()) {
      log('Foreign lock is stale; promoting this window to owner.');
      this.teardown();
      this.start();
    }
  }

  private startAttachedWatchers(): void {
    this.startFlagWatcher();
    this.startGraphWatcher();
  }

  private startFlagWatcher(): void {
    this.flagWatcher = createFlagWatcher(
      this.outPath,
      () => {
        if (this.state === WatcherState.Watching || this.state === WatcherState.Attached) {
          this.setState(WatcherState.UpdateNeeded);
        }
      },
      () => {
        if (this.state === WatcherState.UpdateNeeded) {
          this.setState(this.isOwner ? WatcherState.Watching : WatcherState.Attached);
        }
      },
    );
  }

  private startGraphWatcher(): void {
    this.graphWatcher = createGraphJsonWatcher(this.outPath, () => {
      const stats = readGraphStats(this.outPath);
      if (stats) {
        this.stats = stats;
        this.onChange(this);
      }
    });
  }

  private teardown(): void {
    this.batcher?.dispose();
    this.batcher = undefined;
    this.runner?.dispose();
    this.runner = undefined;
    this.flagWatcher?.dispose();
    this.flagWatcher = undefined;
    this.graphWatcher?.dispose();
    this.graphWatcher = undefined;
    this.lock?.release();
    this.lock = undefined;
  }

  private setState(state: WatcherState): void {
    this.state = state;
    this.onChange(this);
  }

  dispose(): void {
    this.disposed = true;
    this.teardown();
  }
}
