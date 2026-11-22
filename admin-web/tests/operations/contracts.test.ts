import { describe, expect, it } from 'vitest';
import { parseEmailPage, parseGatewayPage, parseGrantDetail, parseGrantPage, parseMemberDetail, parseMemberPage, parseSmsDetail, parseSmsPage } from '../../src/features/operations/contracts';

const id = '11111111-1111-1111-1111-111111111111';
const user = '22222222-2222-2222-2222-222222222222';
const second = '33333333-3333-3333-3333-333333333333';
const hash = 'a'.repeat(64);
const time = '2026-11-16T08:00:00.000Z';
const epoch = Date.parse(time) / 1000;

function smsCapture() {
  return {
    source_kind: 'capture', id, user_id: user, payee_id: null, source_sha256: hash,
    status: 'received', version: 1, received_at: epoch, created_at: epoch,
    public_id: '123456', display_name: null, transaction_id: null, evidence_level: 'client_received',
    source_fact_id: null, parser_version: null, extraction_status: 'not_extracted',
    source_body_sha256: null, source_payload_sha256: null, parsed_at: null,
    payer_name: null, payer_phone: null, payer_masked_phone: null, payer_last3: null,
    payee_momo_number: null, payee_momo_code: null, momo_transaction_reference: null,
    momo_timestamp_local: null, momo_timezone_offset: null, amount_rwf: null, wallet_balance_rwf: null,
    network: null, direction: null, is_payment: null, transaction_reference: null,
    duplicate_reference_count: 0, conflicting_reference_count: 0, provider_confirmation: false,
    settlement_status: 'not_asserted', timezone_known: false, payer_last3_known: false,
    source_content_reveal_required: true, received_at_device: '2026-11-16T10:00:00+02:00',
  };
}
function smsReceiver() {
  const {received_at_device: _deviceTime, ...common} = smsCapture();
  return {...common, source_kind: 'receiver', user_id: null, payee_id: second, public_id: null,
    evidence_level: 'receiver_ingress_unverified', status: 'parsed', source_fact_id: user,
    parser_version: 'collect-admin-source-facts-v1', source_body_sha256: 'b'.repeat(64), source_payload_sha256: hash,
    parsed_at: epoch, extraction_status: 'parsed', momo_transaction_reference: 'MOMO-RECORDED-001',
    amount_rwf: 1000, network: 'mtn_momo', direction: 'incoming', is_payment: 1,
    duplicate_reference_count: 2, conflicting_reference_count: 1};
}
function gateway() {
  return {id, label: 'Device A', app_id: 'app.collect.gateway', installation_id: second, key_sha256: hash,
    signing_certificate_sha256: hash, state: 'active', version: 1, created_at: time, activated_at: time,
    revoked_at: null, last_heartbeat_at: null, carrier_proof: false, send_authority: false};
}
function grant() {
  return {id, device_id: second, device_label: 'Device A', installation_id: user, key_sha256: hash,
    payee_id: second, payee_label: 'Payee A', payee_network: 'mtn_momo', payee_momo_number_or_code: '0780000100',
    status: 'active', version: 1, created_by_admin_id: user, created_at: time, revoked_by_admin_id: null,
    revoked_at: null, capture_authority: true, send_authority: false, financial_authority: false};
}
function member() {
  return {id, user_id: user, body_sha256: hash, status: 'received', version: 1, received_at: time,
    created_at: time, public_id: '123456', display_name: null, transaction_id: null, reviewed_at: null,
    source_kind: 'capture', received_at_device: '2026-11-16T10:00:00+02:00', evidence_level: 'client_received',
    provider_confirmation: false, settlement_status: 'not_asserted', source_content_reveal_required: true};
}

describe('Operational response contracts', () => {
  it('accepts a zoned SMS capture but rejects unproved settlement or conflicting time', () => {
    const capture = smsCapture();
    const page = {rows: [capture], total: 1, limit: 25, offset: 0, next_offset: null};
    expect(parseSmsPage(page, 0).rows[0].received_at).toBe(epoch);
    expect(() => parseSmsPage({...page, rows: [{...capture, provider_confirmation: true}]}, 0)).toThrow();
    expect(() => parseSmsPage({...page, rows: [{...capture, received_at: epoch + 1}]}, 0)).toThrow();
    expect(() => parseSmsPage({...page, total: 2}, 0)).toThrow();
  });

  it('validates source, extraction, duplicate and model filters against returned SMS records', () => {
    const capture = smsCapture(), receiver = smsReceiver();
    const page = (row: unknown) => ({rows: [row], total: 1, limit: 25, offset: 0, next_offset: null});
    expect(parseSmsPage(page(capture), 0, 25, 'received', {sourceKind: 'capture', extractionStatus: 'not_extracted', canonical: true}).rows).toHaveLength(1);
    expect(parseSmsPage(page(receiver), 0, 25, 'parsed', {sourceKind: 'receiver', extractionStatus: 'parsed', duplicates: 'all', canonical: false}).rows).toHaveLength(1);
    expect(parseSmsPage(page(receiver), 0, 25, 'parsed', {duplicates: 'conflicting', canonical: false}).rows).toHaveLength(1);
    expect(() => parseSmsPage(page(capture), 0, 25, '', {sourceKind: 'receiver'})).toThrow();
    expect(() => parseSmsPage(page(capture), 0, 25, '', {extractionStatus: 'parsed'})).toThrow();
    expect(() => parseSmsPage(page(capture), 0, 25, '', {duplicates: 'all'})).toThrow();
    expect(() => parseSmsPage(page({...receiver, conflicting_reference_count: 0}), 0, 25, '', {duplicates: 'conflicting'})).toThrow();
    expect(() => parseSmsPage(page(receiver), 0, 25, '', {canonical: true})).toThrow();
    expect(() => parseSmsPage(page(capture), 0, 25, '', {canonical: false})).toThrow();
    expect(() => parseSmsPage({rows: [], total: 0, limit: 25, offset: 0, next_offset: null}, 0, 25, '', {duplicates: 'invalid'})).toThrow();
  });

  it('accepts a payer contact masked to three digits and rejects a longer visible suffix', () => {
    const receiver = {...smsReceiver(), payer_last3: '123', payer_last3_known: true};
    const page = (phone: string) => ({rows: [{...receiver, payer_masked_phone: phone}], total: 1, limit: 25, offset: 0, next_offset: null});
    expect(parseSmsPage(page('****123'), 0).rows[0].payer_masked_phone).toBe('****123');
    expect(() => parseSmsPage(page('****0123'), 0)).toThrow();
    expect(() => parseSmsPage(page('0788000123'), 0)).toThrow();
  });

  it('checks SMS detail actor and protects duplicate-reference consistency', () => {
    const duplicatePage = {rows: [], total: 0, limit: 25, offset: 0, next_offset: null};
    const detail = {resource_type: 'sms_receipts', resource: smsCapture(), current_actor_id: user, can_extract: false, related: {duplicate_references: duplicatePage}};
    expect(parseSmsDetail(detail, 'capture', id, user, false).resource.id).toBe(id);
    expect(() => parseSmsDetail({...detail, current_actor_id: second}, 'capture', id, user, false)).toThrow();
    expect(() => parseSmsDetail({...detail, can_extract: true}, 'capture', id, user, false)).toThrow();
  });

  it('rejects invented device sending authority and mismatched status filters', () => {
    const row = gateway();
    expect(parseGatewayPage({rows: [row], total: 1}, 0, 'active').rows[0].label).toBe('Device A');
    expect(() => parseGatewayPage({rows: [{...row, send_authority: true}], total: 1}, 0)).toThrow();
    expect(() => parseGatewayPage({rows: [row], total: 1}, 0, 'revoked')).toThrow();
  });

  it('validates capture grant authority and related page identity', () => {
    const row = grant();
    expect(parseGrantPage({rows: [row], total: 1, limit: 25, offset: 0}, 0).rows[0].capture_authority).toBe(true);
    expect(() => parseGrantPage({rows: [{...row, financial_authority: true}], total: 1, limit: 25, offset: 0}, 0)).toThrow();
    const detail = {resource_type: 'receiver_capture_grants', resource: row, current_actor_id: user, can_manage: false, related: {captures: []}, related_total: 0, related_limit: 25, related_offset: 0};
    expect(parseGrantDetail(detail, id, user, false).captures.total).toBe(0);
    expect(() => parseGrantDetail({...detail, can_manage: true}, id, user, false)).toThrow();
  });

  it('keeps canonical member captures distinct from reviewed legacy receipts', () => {
    const row = member();
    expect(parseMemberPage({rows: [row], total: 1}, 0, true).rows[0].source_kind).toBe('capture');
    expect(() => parseMemberPage({rows: [row], total: 1}, 0, false)).toThrow();
    const detail = {resource_type: 'member_receipts', resource: row, current_actor_id: user, can_manage: false, related_truncated: false, related: {reviews: []}};
    expect(parseMemberDetail(detail, id, user, false, true).reviews).toEqual([]);
    expect(() => parseMemberDetail({...detail, can_manage: true}, id, user, false, true)).toThrow();
  });

  it('does not treat accepted email as delivered and rejects inconsistent delivery timestamps', () => {
    const row = {id, recipient_masked: 'a•••@example.com', notification_type: 'notice', status: 'accepted', attempt_count: 1, created_at: epoch, updated_at: epoch, accepted_at: epoch, delivered_at: null};
    expect(parseEmailPage({rows: [row], total: 1, limit: 25, offset: 0}, 0).rows[0].status).toBe('accepted');
    expect(() => parseEmailPage({rows: [{...row, status: 'delivered'}], total: 1, limit: 25, offset: 0}, 0)).toThrow();
    expect(() => parseEmailPage({rows: [{...row, recipient_masked: 'person@example.com'}], total: 1, limit: 25, offset: 0}, 0)).toThrow();
  });
});
