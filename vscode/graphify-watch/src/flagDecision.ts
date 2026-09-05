import { WatcherState } from './state';

export interface BatchInput {
  hasCode: boolean;
  hasNonCode: boolean;
}

export interface BatchDecision {
  requestUpdate: boolean;
  writeFlag: boolean;
  state?: WatcherState;
  setPendingNonCode: boolean;
}

export function decideBatch(batch: BatchInput): BatchDecision {
  if (batch.hasCode) {
    return { requestUpdate: true, writeFlag: false, setPendingNonCode: batch.hasNonCode };
  }
  if (batch.hasNonCode) {
    return {
      requestUpdate: false,
      writeFlag: true,
      state: WatcherState.UpdateNeeded,
      setPendingNonCode: false,
    };
  }
  return { requestUpdate: false, writeFlag: false, setPendingNonCode: false };
}

export interface FinishInput {
  pendingNonCode: boolean;
  flagExists: boolean;
}

export interface FinishDecision {
  writeFlag: boolean;
  state: WatcherState;
}

export function decideFinish(input: FinishInput): FinishDecision {
  if (input.pendingNonCode) {
    return { writeFlag: true, state: WatcherState.UpdateNeeded };
  }
  return {
    writeFlag: false,
    state: input.flagExists ? WatcherState.UpdateNeeded : WatcherState.Watching,
  };
}
