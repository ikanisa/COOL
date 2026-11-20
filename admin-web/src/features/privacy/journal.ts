import {parsePrivacyJournal, privacyJournalKey, validatePrivacyReceipt, type PrivacyPending} from './contracts';

type Lock = <T>(name: string, work: () => Promise<T>) => Promise<T>;
export interface PrivacyJournalContext {actorId: string; sessionId: string; current: () => boolean; storage?: Storage; lock?: Lock}
function fail(): never {throw new Error('The original review reference could not be retained or verified.');}
function row(intent: PrivacyPending) {
  const p = intent.parameters;
  const parameters = intent.kind === 'claim' ? {p_request_id: p.p_request_id, p_claim_request_id: p.p_claim_request_id,
    p_expected_revision: p.p_expected_revision, p_lease_seconds: p.p_lease_seconds} : {p_outcome_request_id: p.p_outcome_request_id,
    p_claim_id: p.p_claim_id, p_fence: p.p_fence, p_outcome_code: p.p_outcome_code};
  return {kind: intent.kind, operation_id: intent.operationId, actor_id: intent.actorId, session_id: intent.sessionId,
    request_id: intent.requestId, parameters};
}
function fingerprint(intent: PrivacyPending) {return JSON.stringify(row(intent));}
async function browserLock<T>(name: string, work: () => Promise<T>): Promise<T> {
  if (!navigator.locks) return fail();
  return navigator.locks.request(name, {mode: 'exclusive', ifAvailable: true}, async lock => lock ? work() : fail());
}
function store(context: PrivacyJournalContext): Storage {
  try {return context.storage ?? localStorage;} catch {return fail();}
}
function read(context: PrivacyJournalContext) {
  if (!context.current()) return fail();
  const key = privacyJournalKey(context.actorId, context.sessionId), storage = store(context);
  let raw: string | null;
  try {raw = storage.getItem(key);} catch {return fail();}
  const parsed = parsePrivacyJournal(raw, context.actorId, context.sessionId);
  if (!context.current()) return fail();
  return {key, storage, ...parsed};
}
function save(context: PrivacyJournalContext, key: string, storage: Storage, generation: number, pending: PrivacyPending | null) {
  if (!context.current()) return fail();
  const raw = JSON.stringify({version: 1, generation, actor_id: context.actorId, session_id: context.sessionId, pending: pending ? row(pending) : null});
  parsePrivacyJournal(raw, context.actorId, context.sessionId);
  try {storage.setItem(key, raw); if (storage.getItem(key) !== raw) return fail();} catch {return fail();}
  if (!context.current()) return fail();
}

/** Compatible with Flutter's actor/session journal and exclusive lock. */
export async function reservePrivacyIntent(context: PrivacyJournalContext, intent: PrivacyPending, expectedGeneration: number): Promise<number> {
  if (intent.actorId !== context.actorId || intent.sessionId !== context.sessionId || !context.current()) return fail();
  const key = privacyJournalKey(context.actorId, context.sessionId);
  return (context.lock ?? browserLock)(`${key}.exclusive`, async () => {
    const saved = read(context);
    if (saved.generation !== expectedGeneration || expectedGeneration >= 999_999_999 || saved.pending) return fail();
    save(context, saved.key, saved.storage, expectedGeneration + 1, intent);
    return expectedGeneration + 1;
  });
}

/** A journal entry is cleared only after its exact server receipt is verified. */
export async function completePrivacyIntent(context: PrivacyJournalContext, intent: PrivacyPending, expectedGeneration: number, receipt: unknown): Promise<number> {
  if (intent.actorId !== context.actorId || intent.sessionId !== context.sessionId || !context.current()) return fail();
  validatePrivacyReceipt(receipt, intent);
  const key = privacyJournalKey(context.actorId, context.sessionId);
  return (context.lock ?? browserLock)(`${key}.exclusive`, async () => {
    const saved = read(context);
    if (saved.generation !== expectedGeneration || expectedGeneration >= 1_000_000_000 || !saved.pending || fingerprint(saved.pending) !== fingerprint(intent)) return fail();
    save(context, saved.key, saved.storage, expectedGeneration + 1, null);
    return expectedGeneration + 1;
  });
}
