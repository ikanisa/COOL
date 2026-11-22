import assert from 'node:assert/strict';
import {createHmac, randomBytes, randomUUID} from 'node:crypto';
import {composeNativeRequest} from '../../../../supabase/functions/_shared/domain/burimunsi/compose.js';
import {PinHasher} from '../../../../supabase/functions/_shared/domain/burimunsi/pin.js';
import {PostgresNativeAuthStore} from '../../../../supabase/functions/_shared/domain/burimunsi/postgres-auth-store.js';
import {sha256} from '../../../../supabase/functions/_shared/domain/burimunsi/values.js';

// Separate from the running service: this is the canonical byte order and keyed
// domain used by the code-44 server for an original create without a PIN field.
function predecessorFingerprint(command, pin, pepper) {
  const {action, capabilities, name, phone, requestId} = command;
  return createHmac('sha256', pepper).update('burimunsi-credential-command-v1\0')
    .update(JSON.stringify({action, capabilities, name, phone, pin, requestId})).digest('hex');
}

export async function verifyStaffCreatePredecessor({owner, db, clock, group, otherGroup, staffActorId, staffSessionId}) {
  const pepper = randomBytes(32), cursorKey = randomBytes(32), legacyPin = '7'.repeat(4);
  const origin = 'https://example.test', unexpected = () => assert.fail('Unexpected unrelated service call');
  const token = () => randomBytes(32).toString('hex');
  await owner.query("INSERT INTO app.users VALUES('fixture-create-result-1','active'),('fixture-create-result-2','active')");
  async function admin(collection) {
    const id = randomUUID(), grant = randomUUID(), installation = randomUUID(), session = randomUUID(), bearer = token();
    await owner.query(`INSERT INTO private.burimunsi_accounts
      (id,collection_id,principal_user_id,phone,name,role,capabilities,pin_hash,created_at,updated_at)
      VALUES($1,$2,'principal','+250780000007','Synthetic admin','admin',ARRAY['records.read','staff.manage'],'{}',1,1)`, [id, collection]);
    await owner.query(`INSERT INTO private.burimunsi_device_grants(id,collection_id,installation_id,token_hash,profile,created_at)
      VALUES($1,$2,$3,$4,'internal_receiver',1)`, [grant, collection, installation, token()]);
    await owner.query('INSERT INTO private.burimunsi_device_accounts VALUES($1,$2,$3)', [grant, id, collection]);
    await owner.query(`INSERT INTO private.burimunsi_sessions(id,collection_id,account_id,grant_id,installation_id,
      credential_version,grant_version,token_hash,created_at,expires_at,principal_user_id)
      VALUES($1,$2,$3,$4,$5,1,1,$6,1,2000000,'principal')`, [session, collection, id, grant, installation, await sha256(bearer)]);
    return {collection, id, installation, session, bearer};
  }
  const original = await admin(group), outside = await admin(otherGroup);
  let principalCalls = 0;
  function route(actor, legacyStaffCreatePin) {
    const auth = new PostgresNativeAuthStore({db, groupId: actor.collection, clock,
      createOperatorPrincipal: async () => ({id: 'fixture-create-result-' + ++principalCalls})});
    return composeNativeRequest({admission: {verified: true, groupId: actor.collection},
      config: {enabled: true, groupId: actor.collection, origin}, clock,
      secrets: {pinPepper: pepper, pinPepperId: 'fixture', cursorKey, legacyStaffCreatePin},
      networkBucket: unexpected, ports: {auth, canonical: {inCanonicalTransaction: unexpected, inMemberTransaction: unexpected},
        records: {withReadSnapshot: unexpected}, gateway: {withAuthorityTransaction: unexpected, withReadSnapshot: unexpected}}});
  }
  const handler = route(original, legacyPin);
  async function post(command, actor = original, service = handler) {
    const reply = await service(new Request(origin + '/v1/burimunsi/staff', {method: 'POST', headers: {
      'content-type': 'application/json', authorization: 'Bearer ' + actor.bearer,
      'x-burimunsi-installation': actor.installation, 'x-burimunsi-contract': 'burimunsi.native.v1',
      'x-burimunsi-request': randomUUID(), 'x-burimunsi-generation': '1'}, body: JSON.stringify(command)}));
    const body = await reply.json();
    return {status: reply.status, result: body.ok ? body.data : body.error.code};
  }
  const history = {action: 'create', name: 'Synthetic retained staff', phone: '+250780000008',
    capabilities: ['records.read'], requestId: randomUUID()};
  const result = {applied: true, id: randomUUID(), version: 1};
  async function retain(command, {actor = original, session = actor.session, operation = 'burimunsi.staff.create',
    response = result} = {}) {
    await owner.query(`INSERT INTO private.burimunsi_command_receipts
      (collection_id,actor_id,request_id,session_id,operation,fingerprint,response,created_at) VALUES($1,$2,$3,$4,$5,$6,$7,1)`,
      [actor.collection, actor.id, command.requestId, session, operation, predecessorFingerprint(command, legacyPin, pepper), response]);
    return command;
  }
  const otherRequest = () => ({...history, requestId: randomUUID()});
  await retain(history);
  const wrongActor = await retain(otherRequest(), {actor: {collection: group, id: staffActorId, session: staffSessionId}});
  const wrongSession = await retain(otherRequest(), {session: randomUUID()});
  const wrongOperation = await retain(otherRequest(), {operation: 'burimunsi.staff.edit'});
  const cancelled = await retain(otherRequest(), {operation: 'burimunsi.staff.cancelled.create'});
  const uncertain = await retain(otherRequest(), {response: {...result, applied: false}});
  async function originalReceipt() {
    return (await owner.query(`SELECT collection_id,actor_id,request_id,session_id,operation,fingerprint,response,created_at
      FROM private.burimunsi_command_receipts WHERE collection_id=$1 AND actor_id=$2 AND request_id=$3`,
      [group, original.id, history.requestId])).rows;
  }
  async function sideEffects() {
    const {rows} = await owner.query(`SELECT
      (SELECT count(*)::int FROM private.burimunsi_accounts) AS accounts,
      (SELECT count(*)::int FROM private.burimunsi_audit) AS audit,
      (SELECT count(*)::int FROM private.burimunsi_command_receipts) AS receipts,
      (SELECT count(*)::int FROM private.burimunsi_sessions) AS sessions`);
    return {...rows[0], principalCalls};
  }
  const before = await sideEffects(), beforeReceipt = await originalReceipt();
  for (let attempt = 0; attempt < 2; attempt++)
    assert.deepEqual(await post(history), {status: 200, result});
  for (const command of [otherRequest(), wrongActor])
    assert.deepEqual(await post(command), {status: 400, result: 'staff_passcode_required'});
  assert.deepEqual(await post(history, outside, route(outside, legacyPin)), {status: 400, result: 'staff_passcode_required'});
  for (const command of [wrongSession, wrongOperation, {...history, name: 'Different name'},
    {...history, phone: '+250780000009'}, {...history, capabilities: ['records.read', 'members.enroll']}])
    assert.deepEqual(await post(command), {status: 409, result: 'idempotency_conflict'});
  assert.deepEqual(await post(cancelled), {status: 409, result: 'staff_command_cancelled'});
  assert.deepEqual(await post(uncertain), {status: 503, result: 'invalid_recovery_proof'});
  for (const binding of [undefined, 'retired'])
    assert.deepEqual(await post(history, original, route(original, binding)), {status: 400, result: 'staff_passcode_required'});
  assert.deepEqual(await post(history, original, route(original, '6'.repeat(4))), {status: 409, result: 'idempotency_conflict'});
  assert.deepEqual(await sideEffects(), before);
  assert.deepEqual(await originalReceipt(), beforeReceipt);

  const explicit = {...otherRequest(), pin: '4'.repeat(4)};
  const created = await post(explicit);
  assert.equal(created.status, 200);
  assert.deepEqual(created.result, {applied: true, id: created.result.id, version: 1});
  assert.deepEqual(await post(explicit), created);
  assert.deepEqual(await sideEffects(), {...before, accounts: before.accounts + 1, audit: before.audit + 1,
    receipts: before.receipts + 1, principalCalls: 1});
  const {rows: [staff]} = await owner.query('SELECT phone,pin_hash FROM private.burimunsi_accounts WHERE id=$1', [created.result.id]);
  const verifier = new PinHasher({pepper, pepperId: 'fixture'});
  assert.equal(await verifier.verify(staff.phone, explicit.pin, staff.pin_hash), true);
  assert.equal(await verifier.verify(staff.phone, legacyPin, staff.pin_hash), false);
  // Before this discriminator, a current explicit request with coincidentally
  // identical digits and a historical omitted field had identical keyed bytes.
  const equalDigits = {...otherRequest(), phone: '+250780000009', pin: legacyPin};
  const equalResult = await post(equalDigits);
  assert.equal(equalResult.status, 200);
  const {rows: [recorded]} = await owner.query(`SELECT fingerprint,response FROM private.burimunsi_command_receipts
    WHERE collection_id=$1 AND actor_id=$2 AND request_id=$3`, [group, original.id, equalDigits.requestId]);
  assert.equal(recorded.fingerprint, predecessorFingerprint(equalDigits, equalDigits.pin, pepper));
  assert.deepEqual(recorded.response, {...equalResult.result, staffCreateInput: 'explicit_pin'});
  assert.deepEqual(await post(equalDigits), equalResult);
  const {pin: _pin, ...omitted} = equalDigits;
  assert.deepEqual(await post(omitted), {status: 409, result: 'idempotency_conflict'});
  assert.deepEqual(await sideEffects(), {...before, accounts: before.accounts + 2, audit: before.audit + 2,
    receipts: before.receipts + 2, principalCalls: 2});
  await owner.query('UPDATE private.burimunsi_sessions SET revoked=true WHERE id=$1', [original.session]);
  assert.deepEqual(await post(history), {status: 401, result: 'session_unavailable'});
  assert.deepEqual(await originalReceipt(), beforeReceipt);
}
