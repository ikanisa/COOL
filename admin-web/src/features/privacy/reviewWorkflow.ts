import type {AdminRequest} from '../../api/client';
import {privacyIntentApplies, type PrivacyDetail, type PrivacyPending} from './contracts';
import {assertEvidenceAccess, readPrivacyDetail, readPrivacyOperation} from './evidence';
import {
  assertPrivacyCheckpoint, completePrivacyIntent, readReservedPrivacyCheckpoint, reservePrivacyIntent,
  type PrivacyCheckpoint,
} from './journal';

interface ReviewAccess {
  request: AdminRequest;
  signal: AbortSignal;
  current: () => boolean;
}

export async function checkOriginalReview(access: ReviewAccess, checkpoint: PrivacyCheckpoint) {
  const {actorId, sessionId} = checkpoint.pending;
  const journal = {actorId, sessionId, current: access.current};
  assertPrivacyCheckpoint(journal, checkpoint);
  const result = await readPrivacyOperation(access, checkpoint.pending);
  assertPrivacyCheckpoint(journal, checkpoint);
  return result;
}

export async function readOriginalReview(access: ReviewAccess, checkpoint: PrivacyCheckpoint) {
  const {actorId, requestId, sessionId} = checkpoint.pending;
  const journal = {actorId, sessionId, current: access.current};
  assertPrivacyCheckpoint(journal, checkpoint);
  const detail = await readPrivacyDetail(access, requestId);
  assertPrivacyCheckpoint(journal, checkpoint);
  return detail;
}

export async function confirmPrivacyReview(access: ReviewAccess, detail: PrivacyDetail, intent: PrivacyPending, generation: number,
  checkpoint: PrivacyCheckpoint | null, onDispatch: (saved: PrivacyCheckpoint) => void) {
  assertEvidenceAccess(access);
  if (!privacyIntentApplies(intent, detail, Date.now())) throw new Error('Review evidence expired.');
  const journal = {actorId: intent.actorId, sessionId: intent.sessionId, current: access.current};

  let retained: PrivacyCheckpoint;
  if (checkpoint) {
    const lookup = await checkOriginalReview(access, checkpoint);
    if (lookup.observed) {
      const generation = await completePrivacyIntent(journal, intent, checkpoint.generation, lookup.receipt);
      return {generation, previouslyRecorded: true};
    }
    const latest = await readOriginalReview(access, checkpoint);
    if (!privacyIntentApplies(intent, latest, Date.now())) throw new Error('Current evidence does not allow a retry.');
    retained = checkpoint;
  } else {
    const reserved = await reservePrivacyIntent(journal, intent, generation);
    retained = readReservedPrivacyCheckpoint(journal, intent, reserved);
  }

  assertPrivacyCheckpoint(journal, retained);
  assertEvidenceAccess(access);
  onDispatch(retained);
  const operation = intent.kind === 'claim' ? 'admin_claim_account_deletion_review_v1' : 'admin_record_account_deletion_review_v1';
  const receipt = await access.request(`privacy/${operation}`, {body: intent.parameters, signal: access.signal});
  assertEvidenceAccess(access);
  const completed = await completePrivacyIntent(journal, intent, retained.generation, receipt);
  return {generation: completed, previouslyRecorded: false};
}
