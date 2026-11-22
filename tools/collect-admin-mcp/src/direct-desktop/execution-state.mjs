import { DesktopError, digest, fail } from './contract.mjs';

export const unavailable = () => ({ status: 'unavailable', reason_code: 'native_adapter_unavailable' });
export const control = tx => tx.get('control', 'state') ?? { stopped: false, reason: null, fence: 0, lease: null };
export const timestamp = time => new Date(time).toISOString();
export const blocked = reason_code => ({ status: 'blocked', reason_code, external_action: 'not_started' });
export const cleanFailure = error => error instanceof DesktopError ? error.code : 'native_operation_unverified';
const observedState = attempt => attempt.state === 'DISPATCH_ARMED' ? 'OUTCOME_UNKNOWN' : attempt.state;
export const outcomeRevision = attempt => digest([attempt.id, observedState(attempt), attempt.observation_id ?? null]);

export function immutable(value) {
  if (value && typeof value === 'object') {
    for (const item of Object.values(value)) immutable(item);
    Object.freeze(value);
  }
  return value;
}

export function attemptView(attempt) {
  return {
    ...attempt,
    state: observedState(attempt),
    ...(attempt.state === 'DISPATCH_ARMED'
      ? { durable_state: 'DISPATCH_ARMED', reason_code: 'armed_attempt_requires_reconciliation' }
      : {}),
    delivery_state: 'unverified',
  };
}

export function unresolvedAttempt(attempt) {
  return attempt.state === 'DISPATCH_ARMED' || attempt.state === 'OUTCOME_UNKNOWN';
}

/** Authorize one action only while the native invocation that owns it is open. */
export function actionPermit(authorize) {
  let used = false;
  let open = true;
  return {
    get used() { return used; },
    consume(witness) {
      if (!open) fail('action_permit_expired');
      if (used) fail('action_permit_consumed');
      const receipt = authorize(witness);
      used = true;
      return receipt;
    },
    close() { open = false; },
  };
}
