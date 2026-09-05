export interface ShrinkInfo {
  newNodes: number;
  existingNodes: number;
}

const SHRINK_RE = /new graph has (\d+) nodes but existing\s+graph\.json has (\d+)/;
const GENERIC_STDERR_RE = /^Nothing to update or rebuild failed/;

export function parseShrinkLine(line: string): ShrinkInfo | undefined {
  const m = SHRINK_RE.exec(line);
  if (!m) {
    return undefined;
  }
  return { newNodes: Number(m[1]), existingNodes: Number(m[2]) };
}

export function shrinkPercent(shrink: ShrinkInfo): number {
  if (shrink.existingNodes <= 0) {
    return 0;
  }
  return ((shrink.existingNodes - shrink.newNodes) / shrink.existingNodes) * 100;
}

export function isGenericFailureLine(line: string): boolean {
  return GENERIC_STDERR_RE.test(line.trim());
}

export interface RunResult {
  exitCode: number | null;
  spawnError?: string;
  parsedError?: string;
  shrink?: ShrinkInfo;
  lastStderrLine?: string;
  forceAttempted: boolean;
  autoForceShrinkPercent: number;
}

export type RunVerdict =
  | { kind: 'ok' }
  | { kind: 'retryWithForce'; reason: string }
  | { kind: 'fail'; message: string; shrinkRefused: boolean };

export function decideRun(r: RunResult): RunVerdict {
  if (r.spawnError) {
    return { kind: 'fail', message: r.spawnError, shrinkRefused: false };
  }
  if (r.exitCode === 0 || r.exitCode === null) {
    return { kind: 'ok' };
  }

  if (r.shrink) {
    const pct = shrinkPercent(r.shrink);
    if (!r.forceAttempted && r.autoForceShrinkPercent > 0 && pct <= r.autoForceShrinkPercent) {
      return {
        kind: 'retryWithForce',
        reason: `graph shrank ${r.shrink.existingNodes} -> ${r.shrink.newNodes} nodes (${pct.toFixed(2)}%), within auto-force threshold`,
      };
    }
    return {
      kind: 'fail',
      message:
        r.parsedError ??
        `graph shrank ${r.shrink.existingNodes} -> ${r.shrink.newNodes} nodes; shrink guard refused to overwrite graph.json`,
      shrinkRefused: true,
    };
  }

  const stderrDetail =
    r.lastStderrLine && !isGenericFailureLine(r.lastStderrLine) ? r.lastStderrLine : undefined;
  return {
    kind: 'fail',
    message:
      r.parsedError ?? stderrDetail ?? `graphify update exited with code ${r.exitCode}`,
    shrinkRefused: false,
  };
}
