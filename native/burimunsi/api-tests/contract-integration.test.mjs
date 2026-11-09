import assert from 'node:assert/strict';
import test from 'node:test';
import {createNativeHandler} from '../../../supabase/functions/_shared/domain/burimunsi/http.js';
import {profile, defs} from '../../../supabase/functions/_shared/domain/burimunsi/wire/burimunsi.generated.mjs';
import {decodeResponse} from '../../../supabase/functions/_shared/domain/burimunsi/wire/runtime.mjs';

const origin = 'https://burimunsi.invalid';
const requestId = '00000000-0000-4000-8000-000000000123';
const correlation = '00000000-0000-4000-8000-000000000456';
const binding = {requestId: correlation, installationId: 'phone-1', generation: '1', groupId: 'group-1', actorId: 'operator-1'};
const committed = effect => ({contractVersion: 2, requestId, groupId: 'group-1', actorId: 'operator-1', state: 'committed', operation: 'burimunsi.allocate', financialState: effect});
const unused = async () => { throw new Error('Unexpected fixture port'); };

function handler(status) {
  return createNativeHandler({
    strictContract: true, groupId: 'group-1', origin, networkBucket: async () => 'fixture',
    auth: {login: unused, authenticate: async () => ({id: 'operator-1', groupId: 'group-1'}), logout: unused, changePasscode: unused, manageStaff: unused},
    records: {home: unused, page: unused, detail: unused, exportLedger: unused, commandStatus: async () => structuredClone(status)},
    contributions: {allocate: unused}, members: {enroll: unused, setActive: unused}, gateway: {status: unused, replace: unused},
  });
}
function request(extra = {}) {
  return new Request(`${origin}/v1/burimunsi/operations/${requestId}`, {headers: {
    Authorization: `Bearer ${'a'.repeat(64)}`, 'X-BuriMunsi-Installation': 'phone-1',
    'X-BuriMunsi-Contract': profile.contractVersion, 'X-BuriMunsi-Request': correlation,
    'X-BuriMunsi-Generation': '1', ...extra,
  }});
}
function decode(value) {
  return decodeResponse(profile, defs, 'operation', 200, 'application/json; charset=utf-8',
    JSON.stringify(value), {...binding, recordId: requestId});
}

for (const effect of ['posted', 'reversed', 'corrected']) {
  test(`strict API preserves cumulative A04 v2 ${effect} outcome`, async () => {
    const response = await handler(committed(effect))(request());
    assert.equal(response.status, 200);
    const envelope = await response.json();
    assert.deepEqual({...decode(envelope).data}, committed(effect));
  });
}
test('pending v2 status is explicitly unresolved and has no invented operation', async () => {
  const status = {contractVersion: 2, requestId, groupId: 'group-1', actorId: 'operator-1', state: 'pending', financialState: 'unresolved'};
  const response = await handler(status)(request());
  assert.equal(response.status, 200);
  assert.deepEqual({...decode(await response.json()).data}, status);
});
for (const operation of ['burimunsi.enroll', 'burimunsi.membership', ...['create', 'edit', 'reset', 'disable', 'enable', 'remove'].map(action => `burimunsi.staff.${action}`)]) {
  test(`strict API retains nonfinancial ${operation} status`, async () => {
    const status = {...committed('not_applicable'), operation};
    const response = await handler(status)(request());
    assert.equal(response.status, 200);
    assert.equal(decode(await response.json()).data.operation, operation);
  });
}
for (const [name, mutate] of [
  ['legacy status', () => ({requestId, state: 'committed'})],
  ['wrong owner', value => ({...value, actorId: 'other'})],
  ['wrong group', value => ({...value, groupId: 'other'})],
  ['wrong operation identity', value => ({...value, requestId: correlation})],
  ['invented rejection', value => ({...value, state: 'rejected'})],
  ['unresolved commitment', value => ({...value, financialState: 'unresolved'})],
  ['financial no-effect', value => ({...value, financialState: 'not_applicable'})],
  ['nonfinancial posting', value => ({...value, operation: 'burimunsi.enroll'})],
  ['pending with action', value => ({...value, state: 'pending', financialState: 'unresolved'})],
]) {
  test(`strict handler and decoder reject ${name}`, async () => {
    const status = mutate(committed('posted'));
    const response = await handler(status)(request());
    assert.equal(response.status, 503);
    assert.equal((await response.json()).error.code, 'contract_invalid_response');
    assert.throws(() => decode({contractVersion: profile.contractVersion, ok: true, binding, data: status}));
  });
}
test('request from a different contract is rejected before reading financial status', async () => {
  const response = await handler(committed('posted'))(request({'X-BuriMunsi-Contract': 'mmoney.ledger.v1'}));
  assert.equal(response.status, 400);
  assert.equal((await response.json()).error.code, 'contract_version');
});
test('malformed response media cannot downgrade strict financial decoding', () => {
  for (const media of ['application/json; charset=iso-8859-1', 'application/json; charset=utf-8; charset=utf-8', 'text/html']) {
    assert.throws(() => decodeResponse(profile, defs, 'operation', 200, media,
      JSON.stringify({contractVersion: profile.contractVersion, ok: true, binding, data: committed('posted')}), {...binding, recordId: requestId}));
  }
});
