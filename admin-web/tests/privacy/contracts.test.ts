import {describe, expect, it} from 'vitest';
import {parsePrivacyCheckpoint, parsePrivacyDetail, parsePrivacyOperation, parsePrivacyPage, parseRetentionContext, parseRetentionInspection, privacyIntentApplies} from '../../src/features/privacy/contracts';

const now = Date.parse('2026-11-16T12:00:00.000Z');
const id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const flags = {policy_acceptance_granted: false, destructive_execution_available: false, erasure_completed: false,
  account_access_restricted: false, auth_removed: false, processor_operation_started: false};
const envelope = {contract_version: 1, scope: 'account_privacy_review_only', checked_at: '2026-11-16T11:59:59.999999Z',
  completion: 'blocked', blocking_reason: 'policy_authority_unavailable', ...flags};
const item = {request_id: id, accepted_at: '2026-11-16T11:00:00.123456Z', revision: 0, review_state: 'awaiting_review',
  claim_expires_at: null, outcome_code: null, outcome_recorded_at: null};
const page = { ...envelope, items: [item], limit: 1, next_cursor: {request_id: id, accepted_at: item.accepted_at} };

describe('privacy review evidence', () => {
  it('retains microseconds in cursor ordering and the original server value', () => {
    const parsed = parsePrivacyPage(page, 1, null, now);
    expect(parsed.next?.acceptedAtWire).toBe('2026-11-16T11:00:00.123456Z');
    expect(() => parsePrivacyPage(page, 1, {requestId: 'ffffffff-ffff-4fff-8fff-ffffffffffff',
      acceptedAt: Date.parse(item.accepted_at), acceptedAtWire: '2026-11-16T11:00:00.123455Z'}, now)).toThrow();
  });
  it('rejects false completion claims, future or expired evidence, and contradictory details', () => {
    expect(() => parsePrivacyPage({...page, erasure_completed: true}, 1, null, now)).toThrow();
    expect(() => parsePrivacyPage({...page, checked_at: '2026-11-16T12:00:00.000001Z'}, 1, null, now)).toThrow();
    expect(() => parsePrivacyPage({...page, checked_at: '2026-11-16T11:49:59.999Z'}, 1, null, now)).toThrow();
    const detail = {...envelope, item, own_claim_receipt: null, own_outcome_receipt: null, own_claim_authority_current: false};
    expect(parsePrivacyDetail(detail, id, now).item?.requestId).toBe(id);
    expect(() => parsePrivacyDetail({...detail, own_claim_authority_current: true}, id, now)).toThrow();
  });
  it('requires a bounded, current retention context and no approval or erasure', () => {
    const context = {contract_version: 1, scope: 'account_retention_inspection_context', source_id: 'a'.repeat(64),
      checked_at: '2026-11-16T11:59:00.000Z', valid_until: '2026-11-16T12:04:00.000Z', approval_granted: false, erasure_completed: false};
    expect(parseRetentionContext(context, now).sourceId).toBe('a'.repeat(64));
    expect(() => parseRetentionContext({...context, approval_granted: true}, now)).toThrow();
    expect(() => parseRetentionContext({...context, valid_until: '2026-11-16T12:04:00.001Z'}, now)).toThrow();
  });
  it('binds retention inventory to the request and source, rejects self-review and false erasure', () => {
    const source = 'a'.repeat(64), actor = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
    const inspection = {contract_version: 1, request_id: id, subject_id: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', source_id: source,
      schema_sha256: 'b'.repeat(64), snapshot_sha256: 'c'.repeat(64), table_counts: {payments: 2}, object_count: 0,
      active_hold_count: 1, in_flight_unresolved: true, approval_granted: false, erasure_completed: false};
    expect(parseRetentionInspection(inspection, id, source, actor).activeHoldCount).toBe(1);
    expect(() => parseRetentionInspection({...inspection, subject_id: actor}, id, source, actor)).toThrow();
    expect(() => parseRetentionInspection({...inspection, erasure_completed: true}, id, source, actor)).toThrow();
    expect(() => parseRetentionInspection({...inspection, table_counts: {payments: -1}}, id, source, actor)).toThrow();
  });
  it('reads only an authority-bound Flutter checkpoint and validates its original lookup', () => {
    const actor = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', session = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
    const operation = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
    const checkpoint = JSON.stringify({version: 1, generation: 1, actor_id: actor, session_id: session, pending: {kind: 'claim',
      operation_id: operation, actor_id: actor, session_id: session, request_id: id, parameters: {p_request_id: id,
        p_claim_request_id: operation, p_expected_revision: 0, p_lease_seconds: 60}}});
    const pending = parsePrivacyCheckpoint(checkpoint, actor, session)!;
    const lookup = {...envelope, operation_kind: 'claim', operation_id: operation, observed: false, receipt: null, claim_authority_current: false};
    expect(parsePrivacyOperation(lookup, pending, now)).toBe(false);
    expect(() => parsePrivacyCheckpoint(checkpoint, actor, 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee')).toThrow();
    expect(() => parsePrivacyOperation({...lookup, operation_id: id}, pending, now)).toThrow();
    expect(() => parsePrivacyOperation({...lookup, observed: true}, pending, now)).toThrow();
    const detail = parsePrivacyDetail({...envelope, item, own_claim_receipt: null, own_outcome_receipt: null, own_claim_authority_current: false}, id, now);
    expect(privacyIntentApplies(pending, detail, now)).toBe(true);
    expect(privacyIntentApplies({...pending, parameters: {...pending.parameters, p_expected_revision: 1}}, detail, now)).toBe(false);
    expect(privacyIntentApplies(pending, detail, now + 600_000)).toBe(false);
  });
});
