import test from 'node:test';
import assert from 'node:assert/strict';
import {createDecipheriv, hkdfSync} from 'node:crypto';
import {GRAPH, compileTransfer, sourceSnapshotHmac, verifyActorLineage} from './compile.mjs';

const operationId = '1c8642f5-7f7d-472b-b69c-3403a571f0da';
const key = Buffer.alloc(32, 9), old = 'source-owner', primary = 'cloud-owner';
const hash = c => c.repeat(64);
const uuid = 'bc06849a-b445-4235-b2a1-a31bd8fe52fc';
function fixture() {
  const tables = Object.fromEntries(GRAPH.map(name => [name, []]));
  tables['app.users'] = [
    {id: old, phone: '+250700000001', email: 'owner@example.test', full_name: 'Original actor', public_id: '111111', access_status: 'active'},
    {id: 'member', phone: '+250700000002', email: null, full_name: 'Member', public_id: '222222', access_status: 'active'},
  ];
  tables['app.collections'] = [{id: 'group', creator_user_id: old}];
  tables['app.memberships'] = [{id: 'membership', collection_id: 'group', user_id: 'member'}];
  tables['private.burimunsi_scopes'] = [{collection_id: 'group', enabled: false, active_binding_id: null}];
  tables['private.burimunsi_accounts'] = [{id: 'account', principal_user_id: old, active: true, pin_hash: {digest:'secret'},removed:false}];
  tables['private.burimunsi_device_grants'] = [{id: 'grant', active: true, token_hash: hash('a')}];
  tables['private.burimunsi_sessions'] = [{id: 'session', revoked: false, token_hash: hash('b')}];
  const sms = {id:'sms-id', owner_user_id:old, client_envelope_id:uuid, body_sha256:hash('c'), object_sha256:hash('d'), object_key:'sms/sms-id', originating_session_id:null, receiver_hash:null, evidence_level:'client_received'};
  const ev = {id:'evidence-id', collection_id:'group', owner_user_id:old, object_sha256:hash('e'), object_key:'evidence/evidence-id'};
  tables['app.sms_receipts'] = [sms]; tables['app.payment_evidence'] = [ev];
  tables['private.burimunsi_native_receipt_origins'] = [{source_id:sms.id, principal_user_id:old, request_id:uuid, body_sha256:sms.body_sha256, object_sha256:sms.object_sha256, collection_id:'group', fingerprint:hash('f')}];
  tables['private.burimunsi_auto_sms_jobs'] = [{source_id:sms.id, collection_id:'group', source_fingerprint:hash('f'), transaction_id:'transaction', state:'completed', phase:'finished', lease_token:null, lease_until:null, retry_lease:null, next_attempt_at:null}];
  for (const [row,purpose,prefix] of [[sms,'sms_receipt','sms'],[ev,'payment_evidence','evidence']]) {
    const scope = {ownerId:old,purpose,entityId:row.id}, operation_id = 'put-' + row.id;
    tables['private.storage_objects'].push({object_key:row.object_key,operation_id,scope,sha256:hash('1'),size:'20',etag:'old-etag'});
    tables['private.storage_payload_reservations'].push({object_key:row.object_key,scope,plaintext_sha256:row.object_sha256,aad:`${prefix}:${row.id}:${row.object_sha256}`,sealed_body:null});
    tables['private.storage_put_intents'].push({operation_id,object_key:row.object_key,scope,sha256:hash('1'),size:'20',state:'committed',upload_unresolved:false,delete_tombstone:false,active_attempt:null});
  }
  tables['app.payments'] = [{id:'payment',collection_id:'group',member_id:'member',evidence_id:ev.id,amount_minor:'1000',currency:'RWF'}];
  tables['app.ledger_entries'] = [{id:'entry',payment_id:'payment',collection_id:'group',member_id:'member',evidence_id:ev.id,amount_minor:'1000',currency:'RWF',kind:'contribution',actor_user_id:old}];
  tables['app.momo_financial_links'] = [{transaction_id:'transaction',payment_id:'payment',beneficiary_member_id:'member',linked_by:old}];
  tables['app.contribution_posting_snapshots'] = [{ledger_entry_id:'entry',payment_id:'payment'}];
  const catalog = Object.fromEntries(GRAPH.map(name => [name,{columns:(tables[name][0] ? Object.keys(tables[name][0]) : ['id']).map(name => ({name,type:'text',generated:false})),foreignKeys:[]}]));
  catalog['app.collections'].foreignKeys = [{target:'app.users',deferrable:false,columns:['creator_user_id'],targetColumns:['id']}];
  catalog['app.ledger_entries'].foreignKeys = [{target:'app.payments',deferrable:false,columns:['payment_id'],targetColumns:['id']}];
  const targetUsers = [{id:primary,phone:'+250700000001',email:'owner@example.test',public_id:'111111'}];
  return {snapshot:{tables},sourceCatalog:catalog,targetCatalog:structuredClone(catalog),targetUsers,sourceOwnerId:old,cloudPrimaryId:primary,aliasPublicId:'333333',operationId,custodyKey:key};
}
function build(f = fixture()) { return compileTransfer({...f,expectedSourceHmac:sourceSnapshotHmac(f.snapshot,key,operationId)}); }

test('compiles preserved original ownership, inert credentials and authenticated lineage', () => {
  const f = fixture(), plan = build(f);
  assert.equal(plan.summary.executionAuthorized,false); assert.equal(plan.summary.sms,1); assert.equal(plan.summary.missingObjectProofCount,2);
  const user = plan.commands.find(c => c.table === 'app.users' && c.params[0] === old);
  assert.deepEqual(user.params, [old,null,null,'Original actor','333333','suspended']);
  const grant = plan.commands.find(c => c.table === 'private.burimunsi_device_grants');
  assert.equal(grant.params[1],false); assert.notEqual(grant.params[2],hash('a'));
  const session = plan.commands.find(c => c.table === 'private.burimunsi_sessions');
  assert.equal(session.params[1],true); assert.notEqual(session.params[2],hash('b'));
  const account = plan.commands.find(c => c.table === 'private.burimunsi_accounts');
  assert.equal(account.params[1],primary); assert.equal(account.params[2],false); assert.deepEqual(account.params[3],{});
  const sms = plan.commands.find(c => c.table === 'app.sms_receipts'); assert.equal(sms.params[1],old);
  const marker = plan.commands.find(c => c.table === 'private.collect_imported_native_history');
  assert.deepEqual(marker.params,['sms-id','group',uuid,'transaction',hash('c'),hash('d'),hash('f'),operationId]);
  const actor = plan.commands.find(c => c.table === 'private.collect_migration_actor_lineage');
  const envelope = actor.params[4], aes = Buffer.from(hkdfSync('sha256',key,Buffer.from(operationId),Buffer.from('collect.actor.lineage.encryption.v1'),32));
  const decipher = createDecipheriv('aes-256-gcm',aes,Buffer.from(envelope.nonce,'base64'));
  decipher.setAAD(Buffer.from(JSON.stringify(['collect.actor.lineage.v1',operationId,old,primary]))); decipher.setAuthTag(Buffer.from(envelope.tag,'base64'));
  const original = JSON.parse(Buffer.concat([decipher.update(Buffer.from(envelope.ciphertext,'base64')),decipher.final()]).toString());
  assert.equal(original.user.email,'owner@example.test'); assert.equal(original.user.public_id,'111111');
  assert.equal(original.native_accounts[0].principal_user_id,old); assert.equal(original.native_accounts[0].pin_hash.digest,'secret');
  const verify={envelope,operationId,sourceOwnerId:old,cloudPrimaryId:primary,custodyKey:key,originalUser:f.snapshot.tables['app.users'][0],originalAccounts:f.snapshot.tables['private.burimunsi_accounts']};
  assert.equal(verifyActorLineage(verify),true); assert.equal(verifyActorLineage({...verify,cloudPrimaryId:'wrong'}),false);
  assert(plan.commands.findIndex(c => c.table === 'app.users') < plan.commands.findIndex(c => c.table === 'app.collections'));
  assert(plan.commands.findIndex(c => c.table === 'app.payments') < plan.commands.findIndex(c => c.table === 'app.ledger_entries'));
  assert(!JSON.stringify(plan.summary).includes('owner@example.test'));
});

test('refuses snapshot drift, principal collision and altered source relationships', () => {
  const f = fixture(), expected = sourceSnapshotHmac(f.snapshot,key,operationId); f.snapshot.tables['app.payments'][0].amount_minor = '2000';
  assert.throws(() => compileTransfer({...f,expectedSourceHmac:expected}),/source_snapshot_changed/);
  assert.throws(() => build(f),/financial_graph_mismatch/);
  const collision = fixture(); collision.aliasPublicId = '111111'; assert.throws(() => build(collision),/user_key_collision/);
  const scope = fixture(); scope.snapshot.tables['private.storage_objects'][0].scope.ownerId = primary;
  assert.throws(() => build(scope),/protected_object_graph_mismatch/);
  const pending = fixture(); pending.snapshot.tables['private.burimunsi_auto_sms_jobs'][0].state = 'processing';
  assert.throws(() => build(pending),/native_sms_graph_mismatch/);
});

test('requires actual target object proof and detects catalogue or nondeferrable cycles', () => {
  const f = fixture(); f.verifiedTargetObjects = Object.fromEntries(f.snapshot.tables['private.storage_objects'].map(o => [o.object_key,{sha256:o.sha256,size:o.size,etag:'verified-target'}]));
  const plan = build(f); assert.equal(plan.summary.missingObjectProofCount,0);
  assert(plan.commands.filter(c => c.table === 'private.storage_objects').every(c => c.params.includes('verified-target')));
  assert.equal(plan.summary.executionAuthorized,false);
  f.targetCatalog['app.users'].columns[0].type = 'uuid'; assert.throws(() => build(f),/target_column_catalogue_mismatch/);
  const cycle = fixture(); cycle.sourceCatalog['app.users'].foreignKeys.push({target:'app.collections',deferrable:false,columns:['id'],targetColumns:['creator_user_id']});
  assert.throws(() => build(cycle),/source_foreign_key_missing|nondeferrable_dependency_cycle/);
});
