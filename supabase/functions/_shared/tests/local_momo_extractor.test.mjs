import assert from 'node:assert/strict';
import {test} from 'node:test';

import {extractLocalMomo, LOCAL_MOMO_EXTRACTOR_VERSION, LOCAL_MOMO_TEMPLATE_ID} from '../domain/local_momo_extractor.js';
import {validateMomoExtraction} from '../domain/momo_pipeline.js';

// Invented data only. These tests do not qualify a carrier template, bind a
// receiving account to a device, or exercise the live processing pipeline.
const body = 'You have received 730 RWF from GRACE EXAMPLE (*********621) at 2026-10-15 08:03:52. Balance: 65432 RWF. FT Id: 1357913579.';
const source = {raw_sender: 'SYNTHETIC-MTN', raw_body: body, completeness: 'complete'};
const profile = {
  sender_allowlist: ['SYNTHETIC-MTN'], currency_aliases: ['RWF'],
  incoming_prefixes: ['You have received'], transaction_id_prefixes: ['FT Id:'],
  date_format: 'YMD_HMS', utc_offset_minutes: 120,
  local_momo_extractor: {version: LOCAL_MOMO_EXTRACTOR_VERSION, template: LOCAL_MOMO_TEMPLATE_ID},
};
const account = {
  id: 'synthetic-account', status: 'active', profile_status: 'approved',
  profile_version: 'synthetic-profile.v1', profile_json: JSON.stringify(profile),
  provider: 'mtn_momo', currency: 'RWF', timezone: 'Africa/Kigali',
};
const withProfile = changes => ({...account, profile_json: JSON.stringify({...profile, ...changes})});
const withBody = raw_body => ({...source, raw_body});
function refused(input, receivingAccount = account) {
  const result = extractLocalMomo(input, receivingAccount);
  assert.equal(result.status, 'unsupported');
  assert.equal(result.extraction, null);
  assert.equal(typeof result.code, 'string');
  assert.ok(!Object.hasOwn(result, 'facts'));
  assert.ok(!JSON.stringify(result).includes(body));
  return result;
}

test('extracts the five requested source facts and validates them with v4', () => {
  const result = extractLocalMomo(source, account);
  assert.equal(result.status, 'extracted');
  assert.equal(result.extractor_version, LOCAL_MOMO_EXTRACTOR_VERSION);
  assert.equal(result.template_id, LOCAL_MOMO_TEMPLATE_ID);
  assert.deepEqual(result.source_observation, {
    kind: 'unbound_received_sms_observation', source_binding: 'unverified', balance_scope: 'unverified',
    amount_rwf: 730, sender_name: 'GRACE EXAMPLE', sender_last3: '621',
    observed_balance_rwf: 65432, transaction_id: '1357913579',
  });
  assert.equal(result.extraction.payer_identifier_raw, '*********621');
  assert.equal(result.extraction.fee_amount_raw, null);
  assert.equal(result.extraction.evidence.fee, null);
  assert.equal(result.extraction.evidence.payer, 'GRACE EXAMPLE (*********621)');
  assert.equal(result.extraction.evidence.wallet_balance_after, 'Balance: 65432 RWF');
  for (const value of Object.values(result.extraction.evidence)) {
    if (value !== null) assert.ok(source.raw_body.includes(value));
  }
  const canonical = validateMomoExtraction(result.extraction, source, account);
  assert.equal(canonical.accepted, true);
  assert.equal(canonical.facts.transaction_at, '2026-10-15T06:03:52.000Z');
  assert.equal(canonical.facts.fee_minor, null);
  for (const forbidden of ['facts', 'member_id', 'group_id', 'credit', 'confirmed']) {
    assert.equal(Object.hasOwn(result, forbidden), false);
    assert.equal(Object.hasOwn(result.source_observation, forbidden), false);
  }
});

test('preserves literal grouped and equal amounts, Unicode names and zero balance', () => {
  const samples = [
    ['You have received 9,876 RWF from ÉLODIE EXAMPLE (****007) at 2024-02-29 00:00:00. Balance: 9,876 RWF. FT Id: 7654321.', 9876, 9876, '007'],
    ['You have received 1 RWF from A (******000) at 2026-01-01 23:59:59. Balance: 0 RWF. FT Id: 1000.', 1, 0, '000'],
  ];
  for (const [message, amount, balance, last3] of samples) {
    const result = extractLocalMomo(withBody(message), account);
    assert.equal(result.status, 'extracted');
    assert.equal(result.source_observation.amount_rwf, amount);
    assert.equal(result.source_observation.observed_balance_rwf, balance);
    assert.equal(result.source_observation.sender_last3, last3);
  }
});

test('requires a complete bounded source and a recognized sender', () => {
  for (const input of [null, {}, {...source, completeness: undefined},
    {...source, completeness: 'incomplete'}, {...source, completeness: 'inconsistent'},
    {...source, raw_sender: 'OTHER'}, {...source, raw_sender: ''},
    withBody(body + '\0'), withBody('x'.repeat(16385))]) refused(input);
  assert.equal(extractLocalMomo({...source, raw_sender: 'synthetic-mtn'}, account).status, 'extracted');
});

test('requires an approved matching MTN account and explicit Rwanda time profile', () => {
  const accounts = [null, {}, {...account, status: 'suspended'},
    {...account, profile_status: 'unverified'}, {...account, profile_version: 'unverified'},
    {...account, provider: 'airtel_money'}, {...account, currency: 'USD'},
    {...account, timezone: 'UTC'}, {...account, profile_json: '{'},
    withProfile({date_format: 'DMY_HMS'}), withProfile({utc_offset_minutes: 0}),
    withProfile({incoming_prefixes: ['Payment received']}),
    withProfile({transaction_id_prefixes: ['Transaction ID:']}),
    withProfile({currency_aliases: ['FRW']}), withProfile({sender_allowlist: ['OTHER']}),
    withProfile({local_momo_extractor: undefined}),
    withProfile({local_momo_extractor: {version: LOCAL_MOMO_EXTRACTOR_VERSION, template: 'other'}}),
    withProfile({local_momo_extractor: {version: 'other', template: LOCAL_MOMO_TEMPLATE_ID}}),
    withProfile({local_momo_extractor: {version: LOCAL_MOMO_EXTRACTOR_VERSION, template: LOCAL_MOMO_TEMPLATE_ID, extra: true}}),
    withProfile({outgoing_markers: Array(31).fill('synthetic marker')}),
    {...account, profile_json: JSON.stringify({...profile, extra: 'x'.repeat(65537)})}];
  for (const candidate of accounts) refused(source, candidate);
});

test('an unbound member capture returns an observation, not financial facts directly', () => {
  const memberSource = {...source, source_provenance: 'member_device_unverified', receiving_source_known: false};
  const result = extractLocalMomo(memberSource, account);
  assert.equal(result.status, 'extracted');
  assert.equal(result.source_observation.kind, 'unbound_received_sms_observation');
  assert.equal(result.source_observation.source_binding, 'unverified');
  assert.equal(result.source_observation.balance_scope, 'unverified');
  // Validation alone is not a receiving-source binding or financial authority.
  assert.equal(validateMomoExtraction(result.extraction, memberSource, account).accepted, true);
  for (const forbidden of ['facts', 'receiving_account_id', 'member_id', 'group_id', 'credit', 'confirmed']) {
    assert.equal(Object.hasOwn(result, forbidden), false);
    assert.equal(Object.hasOwn(result.source_observation, forbidden), false);
  }
});

test('refuses additional text, direction ambiguity and competing references', () => {
  const variants = [
    'Forwarded: ' + body, body + '\n', body + ' Another sentence.',
    'Payment reversed. ' + body,
    body.replace('GRACE EXAMPLE', 'GRACE to SOMEONE'),
    body.replace('GRACE EXAMPLE', 'GRACE-via-SOMEONE'),
    body.replace('GRACE EXAMPLE', 'GRACE beneficiary SOMEONE'),
    body.replace('GRACE EXAMPLE', 'GRACE\u202e EXAMPLE'),
    body.replace('FT Id:', 'FT Id: 12345. FT Id:'),
    body + ' FT Id: 12345.', body + ' Balance: 300 RWF.',
    body.replace('You have received', 'You have sent'),
    body.replace('Balance:', 'Pending Balance:'),
  ];
  for (const message of variants) refused(withBody(message));
});

test('refuses malformed amounts, identifiers, masks and timestamps', () => {
  const variants = [
    body.replace('730 RWF', '0 RWF'), body.replace('730 RWF', '-730 RWF'),
    body.replace('730 RWF', '0730 RWF'), body.replace('730 RWF', '7,30 RWF'),
    body.replace('730 RWF', '730.00 RWF'), body.replace('730 RWF', '9007199254740992 RWF'),
    body.replace('65432 RWF', '-65432 RWF'), body.replace('65432 RWF', '9007199254740992 RWF'),
    body.replace('*********621', '*********62'), body.replace('*********621', '*********6213'),
    body.replace('*********621', '+250788000621'), body.replace('1357913579', '123'),
    body.replace('1357913579', 'ABC123'), body.replace('2026-10-15', '2026-02-29'),
    body.replace('08:03:52', '25:03:52'), body.replace('2026-10-15', '15/10/2026'),
    body.replace('730 RWF', 'RWF 730'), body.replace('65432 RWF', 'RWF 65432'),
    body.replace('FT Id:', 'Transaction ID:'),
  ];
  for (const message of variants) refused(withBody(message));
  assert.equal(refused(withBody(body.replace('2026-10-15', '2026-02-29'))).code, 'canonical_validation_failed');
});

test('does not mutate the source or profile and refuses with no source text in the result', () => {
  const input = Object.freeze({...source});
  const receivingAccount = Object.freeze({...account});
  const before = structuredClone({input, receivingAccount});
  assert.equal(extractLocalMomo(input, receivingAccount).status, 'extracted');
  assert.deepEqual({input, receivingAccount}, before);
  const secretLike = 'synthetic non-receipt with unrelated private content';
  assert.ok(!JSON.stringify(refused(withBody(secretLike))).includes(secretLike));
});
