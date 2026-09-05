import * as vscode from 'vscode';
import { extensionOf, ExtensionSets } from './extensionSets';
import { isIgnoredPath } from './pathFilter';

export interface ChangeBatch {
  hasCode: boolean;
  hasNonCode: boolean;
}

interface BatcherDeps {
  folder: vscode.WorkspaceFolder;
  outDir: string;
  sets: ExtensionSets;
  debounceSeconds: number;
  onMature: (batch: ChangeBatch) => void;
}

export class ChangeBatcher implements vscode.Disposable {
  private readonly watcher: vscode.FileSystemWatcher;
  private readonly pending = new Set<string>();
  private timer?: NodeJS.Timeout;
  private disposed = false;

  constructor(private readonly deps: BatcherDeps) {
    const pattern = new vscode.RelativePattern(deps.folder, '**');
    this.watcher = vscode.workspace.createFileSystemWatcher(pattern);
    this.watcher.onDidCreate((uri) => this.consider(uri));
    this.watcher.onDidChange((uri) => this.consider(uri));
    this.watcher.onDidDelete((uri) => this.consider(uri));
  }

  private consider(uri: vscode.Uri): void {
    if (this.disposed) {
      return;
    }
    const fsPath = uri.fsPath;
    const relative = vscode.workspace.asRelativePath(uri, false);
    if (isIgnoredPath(relative, this.deps.outDir)) {
      return;
    }
    const ext = extensionOf(fsPath);
    if (!this.deps.sets.watched.has(ext)) {
      return;
    }
    this.pending.add(fsPath);
    this.arm();
  }

  private arm(): void {
    if (this.timer) {
      clearTimeout(this.timer);
    }
    this.timer = setTimeout(() => this.mature(), this.deps.debounceSeconds * 1000);
  }

  private mature(): void {
    this.timer = undefined;
    if (this.disposed || this.pending.size === 0) {
      return;
    }
    const batch = [...this.pending];
    this.pending.clear();
    let hasCode = false;
    let hasNonCode = false;
    for (const file of batch) {
      const ext = extensionOf(file);
      if (this.deps.sets.code.has(ext)) {
        hasCode = true;
      } else {
        hasNonCode = true;
      }
    }
    this.deps.onMature({ hasCode, hasNonCode });
  }

  dispose(): void {
    this.disposed = true;
    if (this.timer) {
      clearTimeout(this.timer);
      this.timer = undefined;
    }
    this.pending.clear();
    this.watcher.dispose();
  }
}
