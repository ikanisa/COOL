import test from 'node:test';import assert from 'node:assert/strict';
import {principalFixture,I} from './native-principal-fixture.mjs';

test('actual session SELECT resolves the exact active canonical principal',async t=>{
 const f=principalFixture();t.after(f.close);const actor=await f.session();
 assert.equal(actor.principalUserId,I.principal);assert.equal(actor.id,I.account);assert.equal(actor.sessionId,I.session);
 assert.equal(actor.groupId,I.group);assert.deepEqual(actor.capabilities,['records.read','payments.allocate']);
 for(const secret of ['pinHash','pin_hash','token_hash'])assert.equal(actor[secret],undefined);
});
const changes={
 'disabled canonical user':"UPDATE app.users SET access_status='disabled'",
 'missing canonical user':'DELETE FROM app.users',
 'inactive native account':'UPDATE private.burimunsi_accounts SET active=false',
 'removed native account':'UPDATE private.burimunsi_accounts SET removed=true',
 'disabled group':'UPDATE private.burimunsi_scopes SET enabled=false',
 'disabled device':'UPDATE private.burimunsi_device_grants SET active=false',
 'rotated grant':'UPDATE private.burimunsi_device_grants SET version=2',
 'rotated PIN':'UPDATE private.burimunsi_accounts SET credential_version=2',
 'revoked session':'UPDATE private.burimunsi_sessions SET revoked=true',
 'expired session':`UPDATE private.burimunsi_sessions SET expires_at=${I.now}`,
 'future session':`UPDATE private.burimunsi_sessions SET created_at=${I.now+1}`,
 'removed device assignment':'DELETE FROM private.burimunsi_device_accounts',
 'wrong group assignment':"UPDATE private.burimunsi_device_accounts SET collection_id='other-group'",
 'changed installation':"UPDATE private.burimunsi_device_grants SET installation_id='10000000-0000-4000-8000-000000000099'",
 'missing historical principal snapshot':'UPDATE private.burimunsi_sessions SET principal_user_id=NULL',
 'changed principal snapshot':"UPDATE private.burimunsi_sessions SET principal_user_id='another-user'"
};
for(const [name,q]of Object.entries(changes))test('session denies '+name,async t=>{const f=principalFixture();t.after(f.close);f.execute(q);assert.equal(await f.session(),null);});
test('account reassignment never retargets an already issued session',async t=>{
 const f=principalFixture();t.after(f.close);f.execute("INSERT INTO app.users VALUES('another-user','active')");
 f.execute("UPDATE private.burimunsi_accounts SET principal_user_id='another-user'");assert.equal(await f.session(),null);
});
test('session creation stores the verified principal snapshot and audits in one transaction',async t=>{
 const f=principalFixture();t.after(f.close);assert.equal(await f.store.createSessionIfCurrent(f.issuance),true);
 const row=f.sqlite.prepare('SELECT * FROM private.burimunsi_sessions WHERE id=?').get(I.issued);
 assert.equal(row.principal_user_id,I.principal);assert.equal(row.token_hash,'c'.repeat(64));
 assert.equal(f.sqlite.prepare('SELECT count(*) AS n FROM private.burimunsi_audit').get().n,1);
});
for(const [name,q]of Object.entries(changes).filter(([k])=>!['revoked session','expired session','future session','missing historical principal snapshot','changed principal snapshot'].includes(k)))
 test('conditional issuance denies '+name,async t=>{
 const f=principalFixture();t.after(f.close);f.execute(q);assert.equal(await f.store.createSessionIfCurrent(f.issuance),false);
 assert.equal(f.sqlite.prepare('SELECT count(*) AS n FROM private.burimunsi_sessions WHERE id=?').get(I.issued).n,0);
 assert.equal(f.sqlite.prepare('SELECT count(*) AS n FROM private.burimunsi_audit').get().n,0);
 });
test('reassignment between PIN verification and issuance cannot switch principals',async t=>{
 const f=principalFixture();t.after(f.close);f.execute("INSERT INTO app.users VALUES('another-user','active')");
 f.execute("UPDATE private.burimunsi_accounts SET principal_user_id='another-user'");
 assert.equal(await f.store.createSessionIfCurrent(f.issuance),false);
});
for(const field of ['principalUserId','deviceTokenHash','tokenHash','credentialVersion','deviceGrantVersion','expiresAt'])
 test('issuance refuses missing '+field,async t=>{const f=principalFixture();t.after(f.close);delete f.issuance[field];await assert.rejects(f.store.createSessionIfCurrent(f.issuance));assert.equal(f.state.transactions,0);});
test('issuance refuses excessively long session lifetime before SQL',async t=>{const f=principalFixture();t.after(f.close);f.issuance.expiresAt=I.now+8*3600000+1;await assert.rejects(f.store.createSessionIfCurrent(f.issuance));assert.equal(f.state.transactions,0);});
test('audit failure rolls back session creation',async t=>{const f=principalFixture();t.after(f.close);f.state.afterQuery=async q=>{if(q.startsWith('INSERT INTO private.burimunsi_audit'))throw Error('audit unavailable');};await assert.rejects(f.store.createSessionIfCurrent(f.issuance));assert.equal(f.sqlite.prepare('SELECT count(*) AS n FROM private.burimunsi_sessions WHERE id=?').get(I.issued).n,0);});
test('revoked admission rolls back both issued session and audit',async t=>{const f=principalFixture();t.after(f.close);f.state.afterQuery=async q=>{if(q.startsWith('INSERT INTO private.burimunsi_audit'))f.state.workRevoked=true;};await assert.rejects(f.store.createSessionIfCurrent(f.issuance));assert.equal(f.sqlite.prepare('SELECT count(*) AS n FROM private.burimunsi_sessions WHERE id=?').get(I.issued).n,0);});
test('ambiguous duplicate assignment fails instead of choosing an operator row',async t=>{const f=principalFixture();t.after(f.close);f.execute('INSERT INTO private.burimunsi_device_accounts VALUES(?,?,?)',I.grant,I.account,I.group);await assert.rejects(f.session(),/session_unavailable/);});
test('no selector cannot select an arbitrary native session',async t=>{const f=principalFixture();t.after(f.close);await assert.rejects(f.store.session(f.sql,{}));assert.equal(f.state.queries.length,0);});
