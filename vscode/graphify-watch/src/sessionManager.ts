import * as vscode from 'vscode';
import { readConfig } from './config';
import { log } from './log';
import { StatusBar, StatusModel } from './statusBar';
import { WatcherState } from './state';
import { WatcherSession } from './watcherSession';

const STATE_PRIORITY: WatcherState[] = [
  WatcherState.Error,
  WatcherState.UpdateNeeded,
  WatcherState.Indexing,
  WatcherState.Watching,
  WatcherState.Attached,
  WatcherState.Stopped,
  WatcherState.Idle,
];

export class SessionManager implements vscode.Disposable {
  private readonly sessions = new Map<string, WatcherSession>();
  private readonly statusBar = new StatusBar();
  private recheckTimer?: NodeJS.Timeout;

  constructor() {
    this.recheckTimer = setInterval(() => {
      for (const session of this.sessions.values()) {
        session.recheckAttached();
      }
    }, 10000);
  }

  private getOrCreate(folder: vscode.WorkspaceFolder): WatcherSession {
    const key = folder.uri.toString();
    let session = this.sessions.get(key);
    if (!session) {
      session = new WatcherSession(folder, readConfig(folder), () => this.refresh());
      session.readInitialStats();
      this.sessions.set(key, session);
    } else {
      session.updateConfig(readConfig(folder));
    }
    return session;
  }

  private activeFolder(): vscode.WorkspaceFolder | undefined {
    const folders = vscode.workspace.workspaceFolders;
    if (!folders || folders.length === 0) {
      return undefined;
    }
    const active = vscode.window.activeTextEditor?.document.uri;
    if (active) {
      const match = vscode.workspace.getWorkspaceFolder(active);
      if (match) {
        return match;
      }
    }
    return folders[0];
  }

  startActive(): void {
    const folder = this.activeFolder();
    if (!folder) {
      vscode.window.showWarningMessage('Graphify Watch: open a workspace folder first.');
      return;
    }
    this.getOrCreate(folder).start();
    this.refresh();
  }

  stopActive(): void {
    this.withActiveSession((s) => s.stop());
  }

  restartActive(): void {
    const folder = this.activeFolder();
    if (folder) {
      this.getOrCreate(folder).restart();
      this.refresh();
    }
  }

  rebuildNowActive(): void {
    const folder = this.activeFolder();
    if (folder) {
      this.getOrCreate(folder).rebuildNow();
      this.refresh();
    }
  }

  private withActiveSession(fn: (session: WatcherSession) => void): void {
    const folder = this.activeFolder();
    if (!folder) {
      return;
    }
    const session = this.sessions.get(folder.uri.toString());
    if (session) {
      fn(session);
      this.refresh();
    }
  }

  autoStartAll(): void {
    const folders = vscode.workspace.workspaceFolders ?? [];
    this.pruneRemovedFolders(folders);
    for (const folder of folders) {
      if (readConfig(folder).autoStart) {
        this.getOrCreate(folder).start();
      }
    }
    this.refresh();
  }

  private pruneRemovedFolders(folders: readonly vscode.WorkspaceFolder[]): void {
    const live = new Set(folders.map((f) => f.uri.toString()));
    for (const [key, session] of this.sessions) {
      if (!live.has(key)) {
        session.dispose();
        this.sessions.delete(key);
      }
    }
  }

  activeOutDir(): { folder: vscode.WorkspaceFolder; outDir: string } | undefined {
    const folder = this.activeFolder();
    if (!folder) {
      return undefined;
    }
    return { folder, outDir: readConfig(folder).outDir };
  }

  private aggregate(): StatusModel {
    const folder = this.activeFolder();
    const session = folder ? this.sessions.get(folder.uri.toString()) : undefined;
    if (session) {
      const v = session.view();
      return {
        state: v.state,
        folderName: session.folderName,
        stats: v.stats,
        error: v.error,
      };
    }

    let best: StatusModel = { state: WatcherState.Idle, folderName: folder?.name };
    for (const s of this.sessions.values()) {
      const v = s.view();
      if (STATE_PRIORITY.indexOf(v.state) < STATE_PRIORITY.indexOf(best.state)) {
        best = { state: v.state, folderName: s.folderName, stats: v.stats, error: v.error };
      }
    }
    return best;
  }

  refresh(): void {
    this.statusBar.render(this.aggregate());
  }

  dispose(): void {
    if (this.recheckTimer) {
      clearInterval(this.recheckTimer);
    }
    for (const session of this.sessions.values()) {
      session.dispose();
    }
    this.sessions.clear();
    this.statusBar.dispose();
    log('SessionManager disposed.');
  }
}
