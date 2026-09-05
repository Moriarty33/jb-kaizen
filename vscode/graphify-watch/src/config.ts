import * as vscode from 'vscode';

const SECTION = 'graphifyWatch';

export interface GraphifyConfig {
  autoStart: boolean;
  debounce: number;
  pythonPath: string;
  outDir: string;
  showNotifications: boolean;
  staleLockSeconds: number;
  autoForceShrinkPercent: number;
}

export function readConfig(scope?: vscode.WorkspaceFolder): GraphifyConfig {
  const cfg = vscode.workspace.getConfiguration(SECTION, scope?.uri);
  return {
    autoStart: cfg.get<boolean>('autoStart', true),
    debounce: cfg.get<number>('debounce', 3),
    pythonPath: cfg.get<string>('pythonPath', '').trim(),
    outDir: cfg.get<string>('outDir', 'graphify-out').trim() || 'graphify-out',
    showNotifications: cfg.get<boolean>('showNotifications', true),
    staleLockSeconds: cfg.get<number>('staleLockSeconds', 30),
    autoForceShrinkPercent: cfg.get<number>('autoForceShrinkPercent', 5),
  };
}
