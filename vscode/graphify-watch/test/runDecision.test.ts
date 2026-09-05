import * as assert from 'node:assert';
import { decideRun, parseShrinkLine, shrinkPercent } from '../src/runDecision';

let passed = 0;
const failures: string[] = [];

function check(name: string, fn: () => void): void {
  try {
    fn();
    passed += 1;
  } catch (err) {
    failures.push(`FAIL ${name}: ${(err as Error).message}`);
  }
}

const SHRINK_LINE =
  '[graphify] WARNING: new graph has 26751 nodes but existing graph.json has 26752. Refusing to overwrite — you may be missing chunk files from a previous session. Pass --force to override.';

check('parseShrinkLine extracts node counts from the guard warning', () => {
  const s = parseShrinkLine(SHRINK_LINE);
  assert.ok(s);
  assert.strictEqual(s.newNodes, 26751);
  assert.strictEqual(s.existingNodes, 26752);
});

check('parseShrinkLine ignores unrelated lines', () => {
  assert.strictEqual(parseShrinkLine('Rebuilt: 10 nodes, 20 edges'), undefined);
});

check('shrinkPercent computes relative shrink', () => {
  assert.ok(Math.abs(shrinkPercent({ newNodes: 95, existingNodes: 100 }) - 5) < 1e-9);
});

check('exit 0 with stderr noise is still ok', () => {
  const v = decideRun({
    exitCode: 0,
    lastStderrLine: 'some benign warning',
    forceAttempted: false,
    autoForceShrinkPercent: 5,
  });
  assert.strictEqual(v.kind, 'ok');
});

check('killed run (code null) is not an error', () => {
  const v = decideRun({ exitCode: null, forceAttempted: false, autoForceShrinkPercent: 5 });
  assert.strictEqual(v.kind, 'ok');
});

check('small shrink triggers a single auto-force retry', () => {
  const v = decideRun({
    exitCode: 1,
    shrink: { newNodes: 26751, existingNodes: 26752 },
    lastStderrLine: 'Nothing to update or rebuild failed — check output above.',
    forceAttempted: false,
    autoForceShrinkPercent: 5,
  });
  assert.strictEqual(v.kind, 'retryWithForce');
});

check('shrink after a force attempt fails (no retry loop)', () => {
  const v = decideRun({
    exitCode: 1,
    shrink: { newNodes: 26751, existingNodes: 26752 },
    forceAttempted: true,
    autoForceShrinkPercent: 5,
  });
  assert.strictEqual(v.kind, 'fail');
  assert.ok(v.kind === 'fail' && v.shrinkRefused);
});

check('large shrink is refused with a descriptive message', () => {
  const v = decideRun({
    exitCode: 1,
    shrink: { newNodes: 100, existingNodes: 26752 },
    forceAttempted: false,
    autoForceShrinkPercent: 5,
  });
  assert.strictEqual(v.kind, 'fail');
  assert.ok(v.kind === 'fail' && v.shrinkRefused);
  assert.ok(v.kind === 'fail' && v.message.includes('26752'));
});

check('autoForceShrinkPercent 0 disables auto-force', () => {
  const v = decideRun({
    exitCode: 1,
    shrink: { newNodes: 26751, existingNodes: 26752 },
    forceAttempted: false,
    autoForceShrinkPercent: 0,
  });
  assert.strictEqual(v.kind, 'fail');
});

check('parsed Rebuild failed message wins over generic stderr', () => {
  const v = decideRun({
    exitCode: 1,
    parsedError: 'ValueError: boom',
    lastStderrLine: 'Nothing to update or rebuild failed — check output above.',
    forceAttempted: false,
    autoForceShrinkPercent: 5,
  });
  assert.strictEqual(v.kind, 'fail');
  assert.ok(v.kind === 'fail' && v.message === 'ValueError: boom');
});

check('generic stderr line never becomes the error message', () => {
  const v = decideRun({
    exitCode: 1,
    lastStderrLine: 'Nothing to update or rebuild failed — check output above.',
    forceAttempted: false,
    autoForceShrinkPercent: 5,
  });
  assert.strictEqual(v.kind, 'fail');
  assert.ok(v.kind === 'fail' && v.message.includes('exited with code 1'));
});

check('meaningful stderr line is used as the error message', () => {
  const v = decideRun({
    exitCode: 1,
    lastStderrLine: 'PermissionError: [Errno 13] graph.json',
    forceAttempted: false,
    autoForceShrinkPercent: 5,
  });
  assert.strictEqual(v.kind, 'fail');
  assert.ok(v.kind === 'fail' && v.message.includes('PermissionError'));
});

check('spawn error surfaces as failure regardless of exit code', () => {
  const v = decideRun({
    exitCode: null,
    spawnError: 'spawn python3 ENOENT',
    forceAttempted: false,
    autoForceShrinkPercent: 5,
  });
  assert.strictEqual(v.kind, 'fail');
  assert.ok(v.kind === 'fail' && v.message.includes('ENOENT'));
});

console.log(`runDecision: ${passed} passed`);
if (failures.length > 0) {
  console.error(failures.join('\n'));
  process.exit(1);
}
