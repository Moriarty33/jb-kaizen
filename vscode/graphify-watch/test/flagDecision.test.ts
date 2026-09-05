import * as assert from 'node:assert';
import { decideBatch, decideFinish } from '../src/flagDecision';
import { WatcherState } from '../src/state';

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

check('code-only batch requests update, no flag, no pending', () => {
  const d = decideBatch({ hasCode: true, hasNonCode: false });
  assert.strictEqual(d.requestUpdate, true);
  assert.strictEqual(d.writeFlag, false);
  assert.strictEqual(d.setPendingNonCode, false);
  assert.strictEqual(d.state, undefined);
});

check('non-code-only batch writes flag and goes UpdateNeeded, no update', () => {
  const d = decideBatch({ hasCode: false, hasNonCode: true });
  assert.strictEqual(d.requestUpdate, false);
  assert.strictEqual(d.writeFlag, true);
  assert.strictEqual(d.state, WatcherState.UpdateNeeded);
  assert.strictEqual(d.setPendingNonCode, false);
});

check('mixed batch runs update first, defers the flag (no early write)', () => {
  const d = decideBatch({ hasCode: true, hasNonCode: true });
  assert.strictEqual(d.requestUpdate, true);
  assert.strictEqual(d.writeFlag, false, 'must not write flag before the code rebuild');
  assert.strictEqual(d.setPendingNonCode, true);
});

check('code-only finish with no pending and no flag -> Watching', () => {
  const d = decideFinish({ pendingNonCode: false, flagExists: false });
  assert.strictEqual(d.writeFlag, false);
  assert.strictEqual(d.state, WatcherState.Watching);
});

check('finish re-asserts flag + UpdateNeeded when non-code signal pending', () => {
  const d = decideFinish({ pendingNonCode: true, flagExists: false });
  assert.strictEqual(d.writeFlag, true, 'pending signal must survive the code rebuild');
  assert.strictEqual(d.state, WatcherState.UpdateNeeded);
});

check('finish honors an externally present flag even without pending', () => {
  const d = decideFinish({ pendingNonCode: false, flagExists: true });
  assert.strictEqual(d.writeFlag, false);
  assert.strictEqual(d.state, WatcherState.UpdateNeeded);
});

console.log(`flagDecision: ${passed} passed`);
if (failures.length > 0) {
  console.error(failures.join('\n'));
  process.exit(1);
}
