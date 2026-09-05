import { spawnSync } from 'node:child_process';
import { log } from './log';

export interface ExtensionSets {
  code: ReadonlySet<string>;
  watched: ReadonlySet<string>;
}

const FALLBACK_CODE = [
  '.ts',
  '.tsx',
  '.js',
  '.jsx',
  '.mjs',
  '.cjs',
  '.py',
  '.go',
  '.rs',
  '.java',
  '.kt',
  '.rb',
  '.php',
  '.c',
  '.h',
  '.cpp',
  '.hpp',
  '.cs',
  '.swift',
  '.scala',
  '.sql',
];

const FALLBACK_EXTRA_WATCHED = [
  '.md',
  '.mdx',
  '.txt',
  '.pdf',
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.svg',
];

const PROBE = [
  '-c',
  "from graphify.detect import CODE_EXTENSIONS,DOC_EXTENSIONS,PAPER_EXTENSIONS,IMAGE_EXTENSIONS; import json; print(json.dumps({'code':sorted(CODE_EXTENSIONS),'watched':sorted(CODE_EXTENSIONS|DOC_EXTENSIONS|PAPER_EXTENSIONS|IMAGE_EXTENSIONS)}))",
];

interface ProbePayload {
  code: string[];
  watched: string[];
}

function fallbackSets(): ExtensionSets {
  const code = new Set(FALLBACK_CODE);
  const watched = new Set([...FALLBACK_CODE, ...FALLBACK_EXTRA_WATCHED]);
  return { code, watched };
}

function parsePayload(stdout: string): ExtensionSets | undefined {
  const line = stdout.trim().split('\n').pop()?.trim();
  if (!line) {
    return undefined;
  }
  const payload = JSON.parse(line) as ProbePayload;
  if (!Array.isArray(payload.code) || !Array.isArray(payload.watched)) {
    return undefined;
  }
  return {
    code: new Set(payload.code.map((e) => e.toLowerCase())),
    watched: new Set(payload.watched.map((e) => e.toLowerCase())),
  };
}

const cache = new Map<string, ExtensionSets>();

export function resolveExtensionSets(python: string): ExtensionSets {
  const hit = cache.get(python);
  if (hit) {
    return hit;
  }
  try {
    const res = spawnSync(python, PROBE, { timeout: 20000, encoding: 'utf8' });
    if (res.status === 0) {
      const parsed = parsePayload(res.stdout);
      if (parsed && parsed.watched.size > 0) {
        log(`Extension sets resolved from graphify.detect (code=${parsed.code.size}, watched=${parsed.watched.size}).`);
        cache.set(python, parsed);
        return parsed;
      }
    }
  } catch {
    /* fall through to fallback */
  }
  log('Extension sets: graphify.detect probe failed; using hardcoded fallback set.');
  const fallback = fallbackSets();
  cache.set(python, fallback);
  return fallback;
}

export function extensionOf(filePath: string): string {
  const dot = filePath.lastIndexOf('.');
  const slash = Math.max(filePath.lastIndexOf('/'), filePath.lastIndexOf('\\'));
  if (dot <= slash) {
    return '';
  }
  return filePath.slice(dot).toLowerCase();
}
