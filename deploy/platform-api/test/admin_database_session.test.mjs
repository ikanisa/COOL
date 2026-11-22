import {test} from 'node:test';
import assert from 'node:assert/strict';
import {accountDatabase} from '../src/admin_accounts.js';
import {fixture} from './support/notification_operator_integration_fixture.mjs';

test('account wrapper preserves the actual database session capabilities', () => {
 const statement={};
 const session={prepare(){assert.equal(this,session);return statement;},batch(){}};
 const wrapped=accountDatabase({DB:session},{},null).DB;
 assert.equal(wrapped.withSession,undefined);
 assert.equal(wrapped.prepare('SELECT 1'),statement);
 const database={withSession(constraint){assert.equal(this,database);assert.equal(constraint,'first-primary');return session;}};
 const selected=accountDatabase({DB:database},{},null).DB.withSession('first-primary');
 assert.equal(selected.withSession,undefined);
 assert.equal(selected.prepare('SELECT 1'),statement);
});

test('Owner SMS access works through a real non-recursive D1 session and keeps authority checks', async t => {
 const f=await fixture(t,{TEST_REAL_D1_SESSIONS:true},{migrationsThrough:13});
 const account=await f.seedAccount();
 const login=await f.login(account);
 const aal1=await f.call('/api/admin/notification-operator/access',{method:'GET',cookie:login.cookie});
 assert.equal(aal1.status,403);
 const owner=await f.stepUp(login);
 const result=await f.call('/api/admin/notification-operator/access',{method:'GET',cookie:owner.cookie});
 assert.equal(result.status,200,JSON.stringify(result.body));
 const access=result.body.result??result.body;
 assert.equal(access.scope,'owner_receipt_sms_access');
 assert.equal(access.read_granted,false);
 assert.equal(access.manage_granted,false);
 assert.equal(access.can_operate,false);
 assert.equal(access.provider_approved,false);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM request_receipts').first()).n,0);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM assisted_sms_jobs').first()).n,0);
 await f.db.prepare("DELETE FROM admin_grants WHERE user_id=? AND permission='admin_users.manage'").bind(account.userId).run();
 const revoked=await f.call('/api/admin/notification-operator/access',{method:'GET',cookie:owner.cookie});
 assert.equal(revoked.status,403);
});
