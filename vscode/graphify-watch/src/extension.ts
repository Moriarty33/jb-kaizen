import * as fs from 'node:fs';
import * as path from 'node:path';
import * as vscode from 'vscode';
import * as cmd from './commands';
import { disposeLog, initLog, log, showLog } from './log';
import { SessionManager } from './sessionManager';

let manager: SessionManager | undefined;

export function activate(context: vscode.ExtensionContext): void {
  initLog();
  log('Graphify Watch activated.');
  manager = new SessionManager();
  const mgr = manager;

  const register = (id: string, handler: () => void): void => {
    context.subscriptions.push(vscode.commands.registerCommand(id, handler));
  };

  register(cmd.START, () => mgr.startActive());
  register(cmd.STOP, () => mgr.stopActive());
  register(cmd.RESTART, () => mgr.restartActive());
  register(cmd.REBUILD_NOW, () => mgr.rebuildNowActive());
  register(cmd.OPEN_GRAPH, () => openGraph(mgr));
  register(cmd.SHOW_LOG, () => showLog());
  register(cmd.OPEN_SETTINGS, () =>
    vscode.commands.executeCommand('workbench.action.openSettings', 'graphifyWatch'),
  );
  register(cmd.SHOW_MENU, () => showMenu(mgr));

  context.subscriptions.push(
    vscode.window.onDidChangeActiveTextEditor(() => mgr.refresh()),
    vscode.workspace.onDidChangeWorkspaceFolders(() => mgr.autoStartAll()),
    new vscode.Disposable(() => mgr.dispose()),
  );

  mgr.refresh();
  mgr.autoStartAll();
}

function openGraph(mgr: SessionManager): void {
  const ctx = mgr.activeOutDir();
  if (!ctx) {
    return;
  }
  const html = path.join(ctx.folder.uri.fsPath, ctx.outDir, 'graph.html');
  if (!fs.existsSync(html)) {
    vscode.window.showWarningMessage(`Graphify Watch: ${html} does not exist yet.`);
    return;
  }
  vscode.env.openExternal(vscode.Uri.file(html));
}

async function showMenu(mgr: SessionManager): Promise<void> {
  const picks: Array<vscode.QuickPickItem & { run: () => void }> = [
    { label: '$(play) Start', run: () => mgr.startActive() },
    { label: '$(debug-stop) Stop', run: () => mgr.stopActive() },
    { label: '$(refresh) Restart', run: () => mgr.restartActive() },
    { label: '$(sync) Rebuild now', run: () => mgr.rebuildNowActive() },
    { label: '$(graph) Open graph', run: () => openGraph(mgr) },
    { label: '$(output) Show log', run: () => showLog() },
    {
      label: '$(gear) Settings',
      run: () =>
        vscode.commands.executeCommand('workbench.action.openSettings', 'graphifyWatch'),
    },
  ];
  const choice = await vscode.window.showQuickPick(picks, {
    placeHolder: 'Graphify Watch',
  });
  choice?.run();
}

export function deactivate(): void {
  manager?.dispose();
  manager = undefined;
  disposeLog();
}
