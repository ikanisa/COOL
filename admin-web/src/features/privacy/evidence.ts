import type {AdminRequest} from '../../api/client';
import {
  parsePrivacyDetail, parsePrivacyOperation, parsePrivacyPage, parseRetentionContext, parseRetentionInspection,
  type PrivacyCursor, type PrivacyPending, type RetentionContext,
} from './contracts';

const pageSize = 25;
const evidenceLifetime = 600_000;

export function privacyEvidenceIsCurrent(checkedAt: number, now = Date.now()): boolean {
  return checkedAt <= now && now - checkedAt < evidenceLifetime;
}

// Permit a subsecond server clock lead to elapse without admitting future evidence.
async function waitForEvidenceClock(value: Record<string, unknown>, signal: AbortSignal) {
  const time = typeof value.checked_at === 'string' ? value.checked_at : '';
  const fraction = time.match(/\.(\d+)Z$/)?.[1] ?? '';
  const delay = Date.parse(time) - Date.now() + (/[1-9]/.test(fraction.slice(3)) ? 1 : 0);
  if (!Number.isFinite(delay) || delay <= 0 || delay >= 1000) return;
  await new Promise<void>((resolve, reject) => {
    const abort = () => { clearTimeout(timer); reject(new Error('Request cancelled.')); };
    const timer = setTimeout(() => {
      signal.removeEventListener('abort', abort);
      resolve();
    }, Math.ceil(delay) + 1);
    if (signal.aborted) abort();
    else signal.addEventListener('abort', abort, {once: true});
  });
}

interface EvidenceAccess {
  request: AdminRequest;
  signal: AbortSignal;
  current: () => boolean;
}

export function assertEvidenceAccess({current, signal}: EvidenceAccess) {
  if (signal.aborted || !current()) throw new Error('Review access expired.');
}

async function readEvidence(access: EvidenceAccess, operation: string, body: Record<string, unknown>, timed = true) {
  assertEvidenceAccess(access);
  const raw = await access.request(`privacy/${operation}`, {body, signal: access.signal});
  if (timed) await waitForEvidenceClock(raw, access.signal);
  assertEvidenceAccess(access);
  return raw;
}

export async function readRetentionContext(access: EvidenceAccess) {
  return parseRetentionContext(await readEvidence(access, 'admin_get_account_retention_context_v1', {}));
}

export async function readPrivacyPage(access: EvidenceAccess, before: PrivacyCursor | null) {
  const raw = await readEvidence(access, 'admin_list_account_deletion_reviews_v1', {
    p_limit: pageSize,
    p_before_accepted_at: before?.acceptedAtWire ?? null,
    p_before_request_id: before?.requestId ?? null,
  });
  return parsePrivacyPage(raw, pageSize, before);
}

export async function readPrivacyDetail(access: EvidenceAccess, requestId: string) {
  const raw = await readEvidence(access, 'admin_get_account_deletion_review_v1', {p_request_id: requestId});
  return parsePrivacyDetail(raw, requestId);
}

export async function readRetentionInspection(access: EvidenceAccess, bound: RetentionContext, actorId: string,
  requestId: string, revision: number) {
  const raw = await readEvidence(access, 'admin_inspect_account_retention_scope_v1', {
    p_request_id: requestId,
    p_expected_review_revision: revision,
    p_expected_source_id: bound.sourceId,
  }, false);
  return parseRetentionInspection(raw, requestId, bound.sourceId, actorId);
}

export async function readPrivacyOperation(access: EvidenceAccess, pending: PrivacyPending) {
  const raw = await readEvidence(access, 'admin_get_account_deletion_review_operation_v1', {
    p_operation_kind: pending.kind,
    p_operation_id: pending.operationId,
  });
  return {observed: parsePrivacyOperation(raw, pending), receipt: raw.receipt};
}
