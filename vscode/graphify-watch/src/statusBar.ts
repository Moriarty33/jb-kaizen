import * as vscode from 'vscode';
import { GraphStats, WatcherState } from './state';
import * as cmd from './commands';

interface StatePresentation {
  icon: string;
  label: string;
  color?: string;
  tooltipHint: string;
}

const PRESENTATION: Record<WatcherState, StatePresentation> = {
  [WatcherState.Idle]: {
    icon: 'circle-outline',
    label: 'Graphify',
    tooltipHint: 'Watcher is not running.',
  },
  [WatcherState.Watching]: {
    icon: 'eye',
    label: 'Graphify: watching',
    tooltipHint: 'Graph is up to date and watching for changes.',
  },
  [WatcherState.Indexing]: {
    icon: 'sync~spin',
    label: 'Graphify: indexing',
    tooltipHint: 'Running a one-shot graphify update from code changes.',
  },
  [WatcherState.UpdateNeeded]: {
    icon: 'warning',
    label: 'Graphify: update needed',
    color: 'statusBarItem.warningBackground',
    tooltipHint: 'Non-code changes require an LLM re-extraction (run `/graphify --update`).',
  },
  [WatcherState.Error]: {
    icon: 'error',
    label: 'Graphify: error',
    color: 'statusBarItem.errorBackground',
    tooltipHint: 'The watcher reported an error.',
  },
  [WatcherState.Stopped]: {
    icon: 'primitive-square',
    label: 'Graphify: stopped',
    tooltipHint: 'Watcher has stopped.',
  },
  [WatcherState.Attached]: {
    icon: 'link',
    label: 'Graphify: attached',
    tooltipHint: 'Another VS Code window owns the watcher for this folder.',
  },
};

export interface StatusModel {
  state: WatcherState;
  folderName?: string;
  stats?: GraphStats;
  error?: string;
}

export class StatusBar {
  private readonly item: vscode.StatusBarItem;

  constructor() {
    this.item = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 100);
    this.item.command = cmd.SHOW_MENU;
  }

  render(model: StatusModel): void {
    const p = PRESENTATION[model.state];
    this.item.text = `$(${p.icon}) ${p.label}`;
    this.item.color = undefined;
    this.item.backgroundColor = p.color ? new vscode.ThemeColor(p.color) : undefined;
    this.item.tooltip = this.buildTooltip(model, p);
    this.item.show();
  }

  private buildTooltip(model: StatusModel, p: StatePresentation): vscode.MarkdownString {
    const md = new vscode.MarkdownString('', true);
    md.supportThemeIcons = true;
    md.isTrusted = { enabledCommands: cmd.ALL };

    md.appendMarkdown(`**Graphify Watch**\n\n`);
    if (model.folderName) {
      md.appendMarkdown(`Folder: \`${model.folderName}\`\n\n`);
    }
    md.appendMarkdown(`$(${p.icon}) ${p.tooltipHint}\n\n`);
    if (model.stats) {
      md.appendMarkdown(`Graph: ${model.stats.nodes} nodes, ${model.stats.edges} edges\n\n`);
    }
    if (model.error) {
      md.appendMarkdown(`Error: \`${model.error}\`\n\n`);
    }

    md.appendMarkdown('---\n\n');
    md.appendMarkdown(`[$(play) Start](command:${cmd.START}) `);
    md.appendMarkdown(`[$(debug-stop) Stop](command:${cmd.STOP}) `);
    md.appendMarkdown(`[$(refresh) Restart](command:${cmd.RESTART}) `);
    md.appendMarkdown(`[$(sync) Rebuild now](command:${cmd.REBUILD_NOW})\n\n`);
    md.appendMarkdown(`[$(graph) Open graph](command:${cmd.OPEN_GRAPH}) `);
    md.appendMarkdown(`[$(output) Show log](command:${cmd.SHOW_LOG}) `);
    md.appendMarkdown(`[$(gear) Settings](command:${cmd.OPEN_SETTINGS})`);
    return md;
  }

  dispose(): void {
    this.item.dispose();
  }
}
