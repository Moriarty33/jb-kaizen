const IGNORED_SEGMENTS = new Set(['node_modules', 'dist', 'build', '__pycache__']);

export function isIgnoredPath(relativePath: string, outDir: string): boolean {
  const parts = relativePath.split(/[/\\]/).filter(Boolean);
  if (parts.includes(outDir)) {
    return true;
  }
  return parts.some((part) => part.startsWith('.') || IGNORED_SEGMENTS.has(part));
}
