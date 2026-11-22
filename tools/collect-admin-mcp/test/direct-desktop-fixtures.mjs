import { DEFAULT_POLICY, digest, receiptBody, sourceFacts } from '../src/direct-desktop/contract.mjs';

export const CLOCK = Date.parse('2026-10-19T10:00:00.000Z');
export function fixtureInput(reference = 'SYNTHETIC-RECEIPT-1', observedAt = CLOCK) {
  const source = { source_namespace: 'synthetic-browser', tenant_id: 'synthetic-tenant', transaction_reference: reference,
    notification_kind: 'payment_receipt', source_version: 'v1', observed_at: new Date(observedAt).toISOString(),
    payment_state: 'confirmed', amount_label: 'RWF 1,000 confirmed payment', balance_label: 'RWF 5,000 recorded contributions' };
  return { source, recipient: { recipient_key: 'synthetic-recipient', channel: 'messages_native', destination_e164: '+12025550123',
    country_context: 'US', single_recipient: true, recipient_visible: true },
    message: { template_key: 'payment_receipt_v1', purpose: 'payment_receipt', body: receiptBody(source), source_derived: true },
    checks: { source_visible: true, previous_attempt_checked: true, consent_or_authority_visible: true } };
}
export function fixturePolicy() {
  return { ...structuredClone(DEFAULT_POLICY), policy_revision: 'synthetic-test-only-v1', mode: 'assisted', live_dispatch_enabled: true,
    native_adapter: 'mock', channel_accounts: { messages_native: { app_id: 'com.apple.MobileSMS', app_version: 'fixture-only', account_key: 'synthetic-business-account', sending_line_key: 'synthetic-line' } },
    admin_browser: { origin: 'https://platform-admin.collect.ikanisa.com', account_key: 'synthetic-admin-account' },
    test_gate: { enabled: true, owner_designated_recipient_keys: ['synthetic-recipient'], expires_at: new Date(CLOCK + 60_000).toISOString() } };
}
export function witness(ticket, now = CLOCK) {
  return { status: 'verified', evidence_label: 'mock', observed_at: new Date(now).toISOString(), app_id: 'com.apple.MobileSMS', app_version: 'fixture-only',
    account_key: 'synthetic-business-account', sending_line_key: 'synthetic-line', evidence_refs: ['synthetic:preflight-observation'], source: { ...ticket.source, observed_at: new Date(now).toISOString() },
    recipient: structuredClone(ticket.recipient), message_body: ticket.message.body };
}
export function outgoing(ticket, attempt, now = CLOCK) {
  return { status: 'outgoing_observed', app_id: 'com.apple.MobileSMS', app_version: 'fixture-only', account_key: 'synthetic-business-account', sending_line_key: 'synthetic-line',
    recipient_key: ticket.recipient.recipient_key, destination_e164: ticket.recipient.destination_e164, body_hash: digest(ticket.message.body),
    transaction_reference: ticket.source.transaction_reference, observed_at: new Date(now).toISOString(), evidence_label: 'mock', evidence_refs: ['synthetic:outgoing-observation'] };
}
export function mockAdapter(now = () => CLOCK) {
  const calls = { preflight: 0, dispatch: 0, write: 0, inspect: 0 };
  let adminWritten = null;
  const adapter = {
    kind: 'mock', calls,
    async preflightNotification(ticket) { calls.preflight++; return witness(ticket, now()); },
    async dispatchNotification(ticket, attempt, context) {
      context.beforeAction(witness(ticket, now())); calls.dispatch++;
      return outgoing(ticket, attempt, now());
    },
    async inspectAttempt(ticket, attempt) { calls.inspect++; return outgoing(ticket, attempt, now()); },
    async inspectAdminOutcome(ticket, attempt) {
      return { status: adminWritten ? 'matched' : 'absent', attempt_id: attempt.id, ticket_id: ticket.id, operation_key: ticket.operation_key,
        outcome: attempt.state, delivery_state: 'unverified', ...adminWritten, evidence_label: 'mock', evidence_refs: ['synthetic:admin-outcome'],
        browser_origin: 'https://platform-admin.collect.ikanisa.com', account_key: 'synthetic-admin-account', source_facts: sourceFacts(ticket.source),
        observed_at: new Date(now()).toISOString() };
    },
    async writeAdminOutcome(ticket, attempt, context) {
      context.beforeAction(await adapter.inspectAdminOutcome(ticket, attempt)); calls.write++;
      adminWritten = { attempt_id: attempt.id, ticket_id: ticket.id, operation_key: ticket.operation_key, outcome: attempt.state, delivery_state: 'unverified' };
    },
  };
  return adapter;
}
