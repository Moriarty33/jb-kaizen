const vscode = require('vscode');
const path = require('path');

function resolveWorkspaceRoot() {
  const workspaceFile = vscode.workspace.workspaceFile;
  if (workspaceFile && workspaceFile.scheme === 'file') {
    return path.dirname(workspaceFile.fsPath);
  }
  const folders = vscode.workspace.workspaceFolders;
  if (folders && folders.length > 0) {
    return folders[0].uri.fsPath;
  }
  return undefined;
}

function activate(context) {
  context.subscriptions.push(
    vscode.commands.registerCommand('claudeLauncher.run', () => {
      const cwd = resolveWorkspaceRoot();
      if (!cwd) {
        vscode.window.showWarningMessage(
          'Claude Launcher: open a folder or workspace first.'
        );
        return;
      }
      const terminal = vscode.window.createTerminal({
        cwd,
        location: vscode.TerminalLocation.Editor,
      });
      terminal.show();
      terminal.sendText('claude --permission-mode auto');
    })
  );
}

function deactivate() {}

module.exports = { activate, deactivate };
