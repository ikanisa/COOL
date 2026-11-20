import assert from 'node:assert/strict';
import {test} from 'node:test';

import {parsePartialInboxEvidence, parseUnresolvedEvidence} from '../../domain/burimunsi/unresolved-evidence.js';

// Synthetic values only. These fixtures do not qualify a carrier grammar or
// bind a phone, receiving account, member, group, transaction or ledger.
const rule = {role: 'recipient', kind: 'public_code', prefix: 'Receiver code: ', suffix: '.', digit_count: 5, format: 'digits'};
const profile = {
  sender_allowlist: ['SYNTHETIC-MOMO'], currency_aliases: ['RWF'],
  incoming_prefixes: ['You have received'], transaction_id_prefixes: ['TxId:'],
  date_format: 'YMD_HMS', utc_offset_minutes: 120, recipient_rules: [rule],
};
const tuple = changes => ({provider: 'synthetic_provider', status: 'active', profile_status: 'approved',
  profile_version: 'synthetic.v1', profile_json: JSON.stringify({...profile, ...changes}),
  currency: 'RWF', timezone: 'Africa/Kigali'});
const body = 'You have received RWF 1,500 from +250788111222 at 2026-11-10 08:10:20. Fee: 0 RWF. Balance: 9,000 RWF. TxId: TX-556677. Receiver code: 48271.';
const source = changes => ({raw_sender: 'SYNTHETIC-MOMO', raw_body: body, completeness: 'complete', ...changes});
const parse = (sms = source(), providerProfile = tuple(), modelOutput) => parseUnresolvedEvidence({source: sms, providerProfile, modelOutput});
const slice = (sms, span) => sms.raw_body.slice(span.start, span.end);

function extraction(overrides = {}) {
  return {
    schema_version: 'momo-extraction.v1', event_kind: 'incoming_receipt', payment_outcome: 'successful',
    transaction_id_raw: 'TX-556677', original_transaction_id_raw: null,
    transaction_datetime_raw: '2026-11-10 08:10:20', principal_amount_raw: '1,500', currency_raw: 'RWF',
    payer_name_raw: null, payer_identifier_raw: '+250788111222', payment_reference_raw: null,
    fee_amount_raw: '0', wallet_balance_after_raw: '9,000',
    evidence: {incoming_success: 'You have received RWF 1,500', principal: 'RWF 1,500',
      transaction_id: 'TxId: TX-556677', transaction_datetime: 'at 2026-11-10 08:10:20',
      payer: 'from +250788111222', fee: 'Fee: 0 RWF', wallet_balance_after: 'Balance: 9,000 RWF'},
    issues: [], ...overrides,
  };
}

test('extracts only unbound provisional observations with exact role spans', () => {
  const sms = source();
  const result = parse(sms);
  assert.equal(result.kind, 'provisional_sms_evidence');
  assert.equal(result.facts_state, 'supported');
  assert.equal(result.facts.principal.amount_minor, 1500);
  assert.equal(result.facts.principal.currency, 'RWF');
  assert.equal(result.facts.transaction_id.raw, 'TX-556677');
  assert.equal(slice(sms, result.facts.principal.role_evidence), 'You have received RWF 1,500');
  assert.equal(slice(sms, result.facts.transaction_id.evidence), 'TxId: TX-556677');
  assert.deepEqual(result.recipient, {state: 'candidate', kind: 'public_code', raw: '48271',
    identifier: {start: body.indexOf('48271'), end: body.indexOf('48271') + 5},
    role: {start: body.indexOf('Receiver code: '), end: body.length}});
  assert.equal(slice(sms, result.recipient.role), 'Receiver code: 48271.');
  for (const forbidden of ['receiving_account_id', 'group_id', 'member_id', 'source_body_sha256',
    'provider_confirmation', 'settlement_status', 'ledger', 'transaction_id']) {
    assert.equal(Object.hasOwn(result, forbidden), false);
  }
});

test('an approved profile without recipient grammar never guesses from amounts, payer numbers or references', () => {
  const raw = 'You have received RWF 48271 from +250788482710. TxId: 48271.';
  const result = parse(source({raw_body: raw}), tuple({recipient_rules: undefined}));
  assert.deepEqual(result.recipient, {state: 'unresolved', reason: 'recipient_grammar_missing'});
  assert.equal(result.facts_state, 'supported');
  assert.equal(result.facts.principal.amount_minor, 48271);
});

test('uses a model only after canonical source and role validation', () => {
  const sms = source();
  const result = parse(sms, tuple(), extraction());
  assert.equal(result.facts_state, 'supported');
  assert.equal(result.facts.transaction_time.value, '2026-11-10T06:10:20.000Z');
  assert.equal(slice(sms, result.facts.transaction_time.evidence), 'at 2026-11-10 08:10:20');
  assert.equal(result.facts.fee.value, 0);
  assert.equal(result.facts.wallet_balance_after.value, 9000);
  assert.equal(Object.hasOwn(result.facts, 'payer_name'), false);
  assert.equal(Object.hasOwn(result.facts, 'payer_identifier'), false);
  const invented = parse(sms, tuple(), extraction({transaction_id_raw: '48271'}));
  assert.equal(invented.facts_state, 'unsupported');
  assert.equal(invented.facts, null);
  assert.equal(invented.recipient.raw, '48271');
});

test('model recipient inventions cannot create a receiving identifier', () => {
  const sms = source({raw_body: body.replace(' Receiver code: 48271.', '')});
  const output = {...extraction(), recipient_identifier_raw: '48271'};
  const result = parse(sms, tuple({recipient_rules: undefined}), output);
  assert.equal(result.facts_state, 'unsupported');
  assert.equal(result.recipient.state, 'unresolved');
  assert.equal(Object.hasOwn(result.recipient, 'raw'), false);
});

test('a malformed model does not silently fall back to a deterministic extraction', () => {
  for (const model of [{}, extraction({principal_amount_raw: '9,000'}), extraction({payment_outcome: 'failed'}),
    extraction({evidence: {...extraction().evidence, incoming_success: 'not in the message'}})]) {
    const result = parse(source(), tuple(), model);
    assert.equal(result.facts, null);
    assert.equal(result.facts_state, 'unsupported');
  }
});

for (const [name, replacement] of [
  ['masked', 'Receiver code: ****1.'], ['partly masked', 'Receiver code: 4827*.'],
  ['short', 'Receiver code: 4827.'], ['long', 'Receiver code: 482711.'],
  ['missing suffix', 'Receiver code: 48271'], ['ellipsis', 'Receiver code: 48271...'],
  ['decimal continuation', 'Receiver code: 48271.99'], ['masked continuation', 'Receiver code: 48271.xxxx'],
]) test('recipient evidence remains unresolved when ' + name, () => {
  const sms = source({raw_body: body.replace('Receiver code: 48271.', replacement)});
  const result = parse(sms);
  assert.equal(result.recipient.state, 'unresolved');
  assert.equal(Object.hasOwn(result.recipient, 'raw'), false);
});

test('multiple or conflicting recipient mentions remain ambiguous', () => {
  for (const extra of [' Receiver code: 55119.', ' Receiver code: 48271.']) {
    const result = parse(source({raw_body: body + extra}));
    assert.deepEqual(result.recipient, {state: 'unresolved', reason: 'recipient_evidence_ambiguous'});
  }
  const phoneRule = {role: 'recipient', kind: 'phone_number', prefix: 'Recipient phone: ', suffix: '.', digit_count: 12, format: 'plus_digits'};
  const result = parse(source({raw_body: body + ' Recipient phone: +250788123456.'}), tuple({recipient_rules: [rule, phoneRule]}));
  assert.equal(result.recipient.state, 'unresolved');
});

test('honors an explicitly approved phone grammar without rewriting the number', () => {
  const phoneRule = {role: 'recipient', kind: 'phone_number', prefix: 'Recipient phone: ', suffix: '.', digit_count: 12, format: 'plus_digits'};
  const sms = source({raw_body: body.replace('Receiver code: 48271.', 'Recipient phone: +250788123456.')});
  const result = parse(sms, tuple({recipient_rules: [phoneRule]}));
  assert.equal(result.recipient.state, 'candidate');
  assert.equal(result.recipient.raw, '+250788123456');
  assert.equal(slice(sms, result.recipient.identifier), '+250788123456');
  assert.equal(slice(sms, result.recipient.role), 'Recipient phone: +250788123456.');
});

test('rejects missing, ambiguous or wrongly scoped recipient grammar', () => {
  for (const badRule of [
    {...rule, role: 'payer'}, {...rule, prefix: ''}, {...rule, suffix: ''},
    {...rule, digit_count: 0}, {...rule, digit_count: 33}, {...rule, format: 'regex'},
    {...rule, prefix: 'TxId: ', digit_count: 6}, {...rule, extra: true},
    // Do not let a fixed part of the grammar hide identifier digits or masks.
    {...rule, prefix: 'Receiver code: 4', digit_count: 4},
    {...rule, prefix: 'Receiver code: x', digit_count: 4},
    {...rule, suffix: '1.', digit_count: 4}, {...rule, suffix: '*. '},
    {...rule, suffix: '...'}, {...rule, suffix: '.x'},
  ]) assert.equal(parse(source(), tuple({recipient_rules: [badRule]})).recipient.state, 'unresolved');
  assert.equal(parse(source(), tuple({recipient_rules: [rule, {...rule}]})).recipient.state, 'unresolved');
  assert.equal(parse(source(), tuple({recipient_rules: [rule, {...rule, prefix: 'receiver code: '}]})).recipient.state, 'unresolved');
  assert.equal(parse(source(), tuple({recipient_rules: [rule, {...rule, prefix: 'code: '}]})).recipient.state, 'unresolved');
  const sms = source({raw_body: body.replace('Receiver code: 48271.', 'NotReceiver code: 48271.')});
  assert.equal(parse(sms).recipient.state, 'unresolved');
});

test('evidence offsets stay within the exact UTF-16 source, including astral characters', () => {
  const sms = source({raw_body: '💸 ' + body});
  const result = parse(sms);
  assert.equal(result.recipient.state, 'candidate');
  for (const span of [result.recipient.identifier, result.recipient.role,
    result.facts.event_kind.evidence, result.facts.principal.evidence,
    result.facts.principal.role_evidence, result.facts.transaction_id.evidence]) {
    assert.ok(Number.isInteger(span.start) && Number.isInteger(span.end));
    assert.ok(span.start >= 0 && span.start < span.end && span.end <= sms.raw_body.length);
    assert.ok(slice(sms, span).length > 0);
  }
  assert.equal(slice(sms, result.recipient.identifier), '48271');
  assert.equal(slice(sms, result.recipient.role), 'Receiver code: 48271.');
});

test('malformed Unicode and accessor-backed model arrays fail closed', () => {
  const malformed = parse(source({raw_body: body + '\ud800'}));
  assert.equal(malformed.recipient.state, 'unresolved');
  assert.equal(malformed.facts, null);
  const issues = [];
  Object.defineProperty(issues, '0', {enumerable: true, get() { throw new Error('must not read'); }});
  const result = parse(source(), tuple(), extraction({issues}));
  assert.equal(result.facts, null);
  assert.equal(result.facts_state, 'unsupported');
});

test('unapproved profiles, sender mismatches and incomplete messages expose no facts', () => {
  for (const providerProfile of [{...tuple(), status: 'inactive'}, {...tuple(), profile_status: 'draft'},
    {...tuple(), profile_version: 'unverified'}, {...tuple(), id: 'account-must-not-be-supplied'}]) {
    const result = parse(source(), providerProfile);
    assert.equal(result.facts, null);
    assert.equal(result.recipient.state, 'unresolved');
  }
  for (const sms of [source({raw_sender: 'WRONG'}), source({completeness: 'partial'}),
    source({completeness: undefined}), source({raw_body: body + '\0'})]) {
    const result = parse(sms);
    assert.equal(result.facts, null);
    assert.equal(result.recipient.state, 'unresolved');
    assert.equal(JSON.stringify(result).includes(sms.raw_body), false);
  }
});

test('duplicate profile keys and accessor-backed input fail closed', () => {
  const provider = tuple();
  const duplicate = provider.profile_json.slice(0, -1) + ',"recipient_rules":' + JSON.stringify([rule]) + '}';
  const result = parse(source(), {...provider, profile_json: duplicate});
  assert.equal(result.recipient.state, 'unresolved');
  assert.equal(result.facts, null);
  const input = {providerProfile: provider};
  Object.defineProperty(input, 'source', {enumerable: true, get() { throw new Error('must not read'); }});
  assert.equal(parseUnresolvedEvidence(input).recipient.state, 'unresolved');
});

test('does not mutate input, assign an account, or claim settlement', () => {
  const sms = Object.freeze(source()), provider = Object.freeze(tuple()), model = extraction();
  Object.freeze(model.evidence); Object.freeze(model.issues); Object.freeze(model);
  const before = structuredClone({sms, provider, model});
  const result = parse(sms, provider, model);
  assert.deepEqual({sms, provider, model}, before);
  assert.equal(result.recipient.state, 'candidate');
  assert.equal(Object.hasOwn(result, 'receiving_account_id'), false);
  assert.equal(Object.hasOwn(result, 'settlement_status'), false);
  assert.equal(Object.hasOwn(result, 'source_body_sha256'), false);
});

const partialSource = changes => ({raw_sender: 'SYNTHETIC-MOMO', raw_body: body,
  source_mode: 'catch_up', complete: false, ...changes});
const partial = (sms = partialSource(), providerProfile = tuple()) => parsePartialInboxEvidence({source: sms, providerProfile});
const quote = (result, kind) => result.hints.find(item => item.kind === kind);

test('incomplete inbox text yields only a distinct display result with exact quotes', () => {
  const sms = Object.freeze(partialSource()), providerProfile = Object.freeze(tuple());
  const before = structuredClone({sms, providerProfile});
  const result = partial(sms, providerProfile);
  assert.equal(result.kind, 'partial_inbox_display_only');
  assert.equal(result.state, 'partial');
  assert.equal(result.source_complete, false);
  assert.deepEqual(result.recipient, {state: 'unresolved', reason: 'incomplete_source'});
  assert.equal(quote(result, 'quoted_incoming_amount').text, 'You have received RWF 1,500');
  assert.equal(quote(result, 'quoted_reference').text, 'TxId: TX-556677');
  for (const hint of result.hints) {
    assert.equal(slice(sms, hint.evidence), hint.text);
    assert.ok(hint.evidence.start >= 0 && hint.evidence.end <= sms.raw_body.length);
  }
  for (const forbidden of ['facts', 'event_kind', 'amount_minor', 'transaction_id', 'receiving_account_id',
    'group_id', 'member_id', 'settlement_status', 'provider_confirmation', 'source_body_sha256']) {
    assert.equal(Object.hasOwn(result, forbidden), false);
  }
  assert.deepEqual({sms, providerProfile}, before);
  assert.equal(parseUnresolvedEvidence({source: sms, providerProfile}).facts, null);
});

test('partial parser accepts only an explicitly incomplete inbox source and no model input', () => {
  for (const sms of [partialSource({complete: true}), partialSource({source_mode: 'live'}),
    partialSource({completeness: 'complete'}), partialSource({complete: undefined})]) {
    const result = partial(sms);
    assert.equal(result.state, 'unavailable');
    assert.deepEqual(result.hints, []);
    assert.equal(result.recipient.state, 'unresolved');
  }
  const injected = parsePartialInboxEvidence({source: partialSource(), providerProfile: tuple(),
    modelOutput: extraction()});
  assert.equal(injected.state, 'unavailable');
  assert.deepEqual(injected.hints, []);
});

test('amount and reference at the end of an incomplete body are not treated as complete tokens', () => {
  for (const text of ['You have received RWF 1,500', 'You have received RWF 1,500.']) {
    assert.equal(quote(partial(partialSource({raw_body: text})), 'quoted_incoming_amount'), undefined);
  }
  for (const text of ['TxId: TX-556677', 'TxId: TX-556677.']) {
    assert.equal(quote(partial(partialSource({raw_body: text})), 'quoted_reference'), undefined);
  }
});

test('partial amounts reject malformed, negative, decimal and masked continuations', () => {
  for (const text of ['You have received RWF -1,500 from payer', 'You have received RWF 1,50 from payer',
    'You have received RWF 1,500.00 from payer', 'You have received RWF 1,500... truncated',
    'You have received RWF 1,500 xxxx']) {
    assert.equal(quote(partial(partialSource({raw_body: text})), 'quoted_incoming_amount'), undefined);
  }
});

test('partial references reject masking, truncation and duplicate visible labels', () => {
  for (const text of ['TxId: ****123. More text', 'TxId: XX123. More text',
    'TxId: TX-556677... truncated', 'TxId: TX-556677. More text TxId:']) {
    assert.equal(quote(partial(partialSource({raw_body: text})), 'quoted_reference'), undefined);
  }
});

test('conflicting visible incoming labels do not produce an amount quote', () => {
  const sms = partialSource({raw_body: body + ' You have received RWF 2,000 from someone.'});
  const result = partial(sms);
  assert.deepEqual(result.hints, []);
  assert.equal(result.recipient.state, 'unresolved');
});

test('a trailing sentence permits only exact provisional amount and reference quotes', () => {
  const provider=tuple({transaction_id_prefixes:['FT Id:']});
  const text='You have received RWF 1,500 from a synthetic payer. FT Id: TX-556677. Thank you.';
  const sms=partialSource({raw_body:text}),result=partial(sms,provider);
  assert.deepEqual(result.hints.map(x=>x.kind).sort(),['quoted_incoming_amount','quoted_reference']);
  for(const hint of result.hints)assert.equal(slice(sms,hint.evidence),hint.text);
  assert.equal(result.recipient.state,'unresolved');
  for(const bad of [text+' FT Id: OTHER. More text.',text+' You have received RWF 2,000. More text.',
    'Transaction reversal. '+text,'Payment failed. '+text])
    assert.deepEqual(partial(partialSource({raw_body:bad}),provider).hints,[]);
});

test('visible failure, reversal, outgoing and secret markers suppress all partial hints', () => {
  for (const marker of ['Payment failed. ', 'Transaction reversal. ', 'Pending. ',
    'You have sent. ', 'Verification code. ']) {
    const result = partial(partialSource({raw_body: marker + body}));
    assert.deepEqual(result.hints, []);
    assert.equal(result.recipient.state, 'unresolved');
  }
});

test('partial quotes require an approved profile and matching sender', () => {
  for (const providerProfile of [{...tuple(), profile_status: 'draft'}, {...tuple(), profile_version: 'unverified'}]) {
    assert.deepEqual(partial(partialSource(), providerProfile).hints, []);
  }
  assert.deepEqual(partial(partialSource({raw_sender: 'WRONG'})).hints, []);
  assert.deepEqual(partial(partialSource({raw_body: body + '\ud800'})).hints, []);
});

test('partial evidence offsets remain exact after an astral character', () => {
  const sms = partialSource({raw_body: '💸 ' + body});
  const result = partial(sms);
  assert.equal(result.hints.length, 2);
  for (const hint of result.hints) assert.equal(slice(sms, hint.evidence), hint.text);
  assert.equal(result.recipient.state, 'unresolved');
});
