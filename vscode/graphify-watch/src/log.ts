import * as vscode from 'vscode';

let channel: vscode.OutputChannel | undefined;

export function initLog(): vscode.OutputChannel {
  if (!channel) {
    channel = vscode.window.createOutputChannel('Graphify Watch');
  }
  return channel;
}

function timestamp(): string {
  return new Date().toISOString().slice(11, 23);
}

export function showLog(): void {
  initLog().show(true);
}

export function log(message: string): void {
  initLog().appendLine(`[${timestamp()}] ${message}`);
}

export function logWatcher(line: string): void {
  initLog().appendLine(line.replace(/\s+$/, ''));
}

export function disposeLog(): void {
  channel?.dispose();
  channel = undefined;
}
