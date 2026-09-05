import { spawnSync } from 'node:child_process';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { log } from './log';

function importsModule(python: string, module: string): boolean {
  try {
    const res = spawnSync(python, ['-c', `import ${module}`], {
      timeout: 15000,
      encoding: 'utf8',
    });
    return res.status === 0;
  } catch {
    return false;
  }
}

function fromOutDir(folder: string, outDir: string): string | undefined {
  const marker = path.join(folder, outDir, '.graphify_python');
  try {
    if (!fs.existsSync(marker)) {
      return undefined;
    }
    const candidate = fs.readFileSync(marker, 'utf8').trim();
    if (candidate && fs.existsSync(candidate)) {
      return candidate;
    }
  } catch {
    /* ignore */
  }
  return undefined;
}

function fromUvToolRun(): string | undefined {
  try {
    const res = spawnSync(
      'uv',
      ['tool', 'run', 'graphifyy', 'python', '-c', 'import sys;print(sys.executable)'],
      { timeout: 30000, encoding: 'utf8' },
    );
    if (res.status === 0) {
      const out = res.stdout.trim().split('\n').pop()?.trim();
      if (out && fs.existsSync(out)) {
        return out;
      }
    }
  } catch {
    /* ignore */
  }
  return undefined;
}

function persistMarker(folder: string, outDir: string, python: string): void {
  const marker = path.join(folder, outDir, '.graphify_python');
  try {
    if (fs.existsSync(marker) && fs.readFileSync(marker, 'utf8').trim() === python) {
      return;
    }
    fs.mkdirSync(path.dirname(marker), { recursive: true });
    fs.writeFileSync(marker, python, 'utf8');
    log(`Persisted interpreter marker: ${marker}`);
  } catch {
    /* best effort */
  }
}

export function resolveInterpreter(
  folder: string,
  outDir: string,
  configuredPython: string,
): string | undefined {
  const candidates: Array<string | undefined> = [
    configuredPython || undefined,
    fromOutDir(folder, outDir),
    fromUvToolRun(),
    'python3',
  ];

  for (const candidate of candidates) {
    if (!candidate) {
      continue;
    }
    if (importsModule(candidate, 'graphify')) {
      log(`Resolved interpreter: ${candidate}`);
      persistMarker(folder, outDir, candidate);
      return candidate;
    }
  }

  log('No interpreter with graphify importable was found.');
  return undefined;
}
