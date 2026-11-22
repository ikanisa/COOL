import { randomUUID } from 'node:crypto';
import { canonical, fail } from './contract.mjs';
import { control, immutable } from './execution-state.mjs';
import { evidenceLabel, validEvidenceRefs } from './native-evidence.mjs';

export function acquireLease(runtime, tx, executorId, purpose, seconds, operation_key, allowStopped = false) {
  const state = control(tx);
  if (!allowStopped && (state.stopped || runtime.localStopReason !== null)) fail('operator_stopped');
  if (state.lease) fail(state.lease.expires_at <= runtime.now() ? 'lease_recovery_required' : 'executor_busy');
  if (!Number.isSafeInteger(state.fence) || state.fence >= Number.MAX_SAFE_INTEGER) fail('journal_corrupt');
  const lease = immutable({ token: randomUUID(), owner: executorId, purpose, operation_key, fence: state.fence + 1, expires_at: runtime.now() + seconds * 1000 });
  tx.put('control', 'state', { ...state, fence: lease.fence, lease });
  runtime.event(tx, 'lease_acquired', lease);
  return lease;
}

export function assertLease(runtime, tx, lease, allowStopped = false) {
  const state = control(tx);
  if (!allowStopped && (state.stopped || runtime.localStopReason !== null)) fail('operator_stopped');
  if (canonical(state.lease) !== canonical(lease) || lease.expires_at <= runtime.now()) fail('lease_fence_invalid');
}

export function releaseLease(runtime, tx, lease) {
  const state = control(tx);
  if (canonical(state.lease) !== canonical(lease)) fail('lease_fence_invalid');
  tx.put('control', 'state', { ...state, lease: null });
  runtime.event(tx, 'lease_released', { token: lease.token, fence: lease.fence });
}

export async function recoverLease(runtime, args, ticket) {
  const old = runtime.transaction(tx => {
    const state = control(tx), lease = state.lease;
    if (!state.stopped) fail('recovery_requires_stop');
    if (!lease || lease.token !== args.lease_token || lease.fence !== args.lease_fence || lease.operation_key !== ticket.operation_key) fail('lease_fence_invalid');
    if (lease.expires_at > runtime.now() || runtime.active.has(lease.token)) fail('executor_busy');
    return immutable(lease);
  });
  if (!runtime.quiescenceVerifier) fail('executor_quiescence_unverified');
  const evidence = await runtime.quiescenceVerifier(old);
  if (evidence?.status !== 'quiescent' || evidence.lease_token !== old.token || evidence.lease_fence !== old.fence ||
      evidence.executor_id !== old.owner || evidence.evidence_label !== evidenceLabel(runtime.adapter.kind) ||
      !validEvidenceRefs(evidence.evidence_refs)) fail('executor_quiescence_unverified');
  runtime.transaction(tx => {
    const state = control(tx);
    if (!state.stopped || canonical(state.lease) !== canonical(old) || runtime.active.has(old.token) || state.fence >= Number.MAX_SAFE_INTEGER) fail('lease_fence_invalid');
    tx.put('control', 'state', { ...state, lease: null, fence: state.fence + 1 });
    runtime.event(tx, 'lease_recovered', { lease_token: old.token, old_fence: old.fence, new_fence: state.fence + 1,
      owner_review_ref: args.owner_review_ref, evidence_label: evidence.evidence_label, evidence_refs: evidence.evidence_refs });
  });
}
