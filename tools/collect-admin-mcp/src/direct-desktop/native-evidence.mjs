import { randomUUID } from 'node:crypto';
import { canonical, digest, fail, PREPARE_SCHEMA, sourceFacts, validate } from './contract.mjs';
import { timestamp } from './execution-state.mjs';

const APP_IDS = { messages_native: 'com.apple.MobileSMS', whatsapp_native: 'net.whatsapp.WhatsApp' };

export function evidenceLabel(adapterKind) {
  return adapterKind === 'mock' ? 'mock' : 'host_verified';
}

export function validEvidenceRefs(refs) {
  return Array.isArray(refs) && refs.length > 0 && refs.length <= 10 &&
    refs.every(ref => typeof ref === 'string' && ref.length > 0 && ref.length <= 512);
}

function assertFresh(runtime, source, policy) {
  const age = runtime.now() - Date.parse(source.observed_at);
  if (age < -5000 || age > policy.max_source_age_seconds * 1000) fail('source_snapshot_stale');
}

export function assertEligible(runtime, ticket, snapshot, requireLive = false) {
  const { policy, hash } = snapshot;
  if (ticket.policy_hash !== hash) fail('policy_changed');
  if (!policy.approved_channels.includes(ticket.recipient.channel) || !policy.approved_purposes.includes(ticket.message.purpose) ||
      policy.excluded_recipient_keys.includes(ticket.recipient.recipient_key)) fail('policy_scope_denied');
  assertFresh(runtime, ticket.source, policy);
  if (!requireLive) return;
  if (policy.mode === 'dry_run' || !policy.live_dispatch_enabled) fail('live_dispatch_disabled');
  if (runtime.adapter.kind === 'unconfigured' || runtime.adapter.kind !== policy.native_adapter) fail('native_adapter_unavailable');
  if (!runtime.journal.durable) fail('durable_journal_required');
  if (!policy.test_gate.enabled || !policy.test_gate.owner_designated_recipient_keys.includes(ticket.recipient.recipient_key) ||
      Date.parse(policy.test_gate.expires_at) <= runtime.now()) fail('owner_test_gate_required');
  const binding = policy.channel_accounts[ticket.recipient.channel];
  if (!binding || binding.app_id !== APP_IDS[ticket.recipient.channel]) fail('app_account_unverified');
}

export function verifyPreflight(runtime, ticket, value, policy) {
  const binding = policy.channel_accounts[ticket.recipient.channel];
  if (!value || value.status !== 'verified' || value.evidence_label !== evidenceLabel(runtime.adapter.kind) ||
      value.app_id !== binding?.app_id || value.app_version !== binding?.app_version || value.account_key !== binding?.account_key || value.sending_line_key !== binding?.sending_line_key ||
      canonical(value.recipient) !== canonical(ticket.recipient) || value.message_body !== ticket.message.body ||
      canonical(sourceFacts(value.source ?? {})) !== canonical(sourceFacts(ticket.source)) ||
      !validEvidenceRefs(value.evidence_refs)) fail('native_preflight_mismatch');
  validate(PREPARE_SCHEMA.properties.source, value.source, 'native_preflight_mismatch');
  assertFresh(runtime, value.source, policy);
  if (!Number.isFinite(Date.parse(value.observed_at)) || Math.abs(runtime.now() - Date.parse(value.observed_at)) > 5000) fail('native_preflight_stale');
}

export function outgoingObservation(runtime, ticket, attempt, value) {
  const { policy } = runtime.currentPolicy(), binding = policy.channel_accounts[ticket.recipient.channel];
  if (!value || value.status !== 'outgoing_observed' || value.app_id !== binding?.app_id || value.app_version !== binding?.app_version ||
      value.account_key !== binding?.account_key || value.sending_line_key !== binding?.sending_line_key || value.recipient_key !== ticket.recipient.recipient_key || value.destination_e164 !== ticket.recipient.destination_e164 ||
      value.body_hash !== digest(ticket.message.body) || value.transaction_reference !== ticket.source.transaction_reference ||
      value.evidence_label !== evidenceLabel(runtime.adapter.kind) || !validEvidenceRefs(value.evidence_refs) ||
      !Number.isFinite(Date.parse(value.observed_at)) || Date.parse(value.observed_at) < Date.parse(attempt.armed_at) || Date.parse(value.observed_at) > runtime.now() + 5000) fail('native_result_unverified');
  return { id: randomUUID(), attempt_id: attempt.id, status: value.status, app_id: value.app_id, app_version: value.app_version,
    account_key: value.account_key, sending_line_key: value.sending_line_key, recipient_key: value.recipient_key, destination_e164: value.destination_e164, body_hash: value.body_hash,
    transaction_reference: value.transaction_reference, observed_at: value.observed_at, evidence_label: value.evidence_label,
    evidence_refs: structuredClone(value.evidence_refs), delivery_state: 'unverified' };
}

export function noSendObservation(runtime, attempt, result) {
  if (result?.status !== 'failed_no_send' || result.action_not_started !== true ||
      result.evidence_label !== evidenceLabel(runtime.adapter.kind) ||
      typeof result.reason_code !== 'string' || !/^[a-z_]{1,80}$/.test(result.reason_code) ||
      !validEvidenceRefs(result.evidence_refs)) return null;
  return { id: randomUUID(), attempt_id: attempt.id, status: 'failed_no_send', action_not_started: true,
    evidence_label: result.evidence_label, reason_code: result.reason_code,
    evidence_refs: structuredClone(result.evidence_refs), observed_at: timestamp(runtime.now()) };
}
