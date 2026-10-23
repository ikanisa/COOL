import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {fixture} from './admin_support/fixture.mjs';

const enroll = (f, cookie) => f.call('/api/admin/auth/mfa/enroll', {cookie});
const cancel = (f, cookie, id, headers = {}) => f.call('/api/admin/auth/mfa/cancel-enrollment', {cookie, data: {factor_id: id}, headers});

test('an actual replacement sign-in recovers a lost pending setup with original-session audit and no AAL2', async t => {
  const f = await fixture(t), owner = await f.seedAccount(), first = await f.login(owner);
  const setup = await enroll(f, first.cookie); assert.equal(setup.status, 200);
  const replacement = await f.login(owner);
  const read = await f.call('/api/admin/auth/user', {method: 'GET', cookie: replacement.cookie});
  assert.equal(read.status, 200); assert.equal(read.body.factors.length, 1);
  assert.equal(read.body.factors[0].enrollment_current_session, false);
  assert.equal(read.body.factors[0].enrollment_expired, false);
  assert.ok(!JSON.stringify(read.body).includes(setup.body.totp.secret));
  assert.ok(!JSON.stringify(read.body).includes('otpauth:'));
  const result = await cancel(f, replacement.cookie, setup.body.id);
  assert.equal(result.status, 200, JSON.stringify(result));
  assert.deepEqual(result.body, {id: setup.body.id, factor_type: 'totp', status: 'revoked'});
  const audit = await f.db.prepare("SELECT * FROM audit_log WHERE action='auth.mfa.enrollment.cancelled'").first();
  const details = JSON.parse(audit.details_json);
  assert.notEqual(details.enrollment_session_id, details.recovery_session_id);
  assert.equal(audit.actor_session_id, details.recovery_session_id);
  assert.equal((await f.db.prepare('SELECT assurance_level FROM auth_sessions WHERE id=?').bind(audit.actor_session_id).first()).assurance_level, 1);
  const next = await enroll(f, replacement.cookie); assert.equal(next.status, 200);
  assert.notEqual(next.body.id, setup.body.id); assert.notEqual(next.body.totp.secret, setup.body.totp.secret);
});

test('expired pending enrollment can be recovered, while a foreign or verified factor cannot be cancelled', async t => {
  const f = await fixture(t), owner = await f.seedAccount(), login = await f.login(owner);
  const initial = await enroll(f, login.cookie); assert.equal(initial.status, 200);
  const row = await f.db.prepare('SELECT * FROM auth_mfa_factors WHERE id=?').bind(initial.body.id).first();
  assert.equal((await cancel(f, login.cookie, row.id)).status, 200);
  const expired = randomUUID();
  await f.db.prepare("INSERT INTO auth_mfa_factors(id,user_id,friendly_name,secret_ciphertext,status,created_at,enrollment_session_id) VALUES(?,?,?,?,'pending',?,?)")
    .bind(expired, row.user_id, row.friendly_name, row.secret_ciphertext, Math.floor(Date.now()/1000)-700, row.enrollment_session_id).run();
  const read = await f.call('/api/admin/auth/user', {method: 'GET', cookie: login.cookie});
  assert.equal(read.body.factors[0].enrollment_expired, true);
  assert.equal((await cancel(f, login.cookie, expired)).status, 200);
  const verified = await f.stepUp(login);
  const denied = await cancel(f, verified.cookie, verified.factor.id); assert.equal(denied.status, 409);
  const other = await f.seedAccount({email: 'other@example.com', role: 'admin'}), otherLogin = await f.login(other);
  const pending = await enroll(f, otherLogin.cookie); assert.equal(pending.status, 200);
  assert.equal((await cancel(f, verified.cookie, pending.body.id)).status, 409);
  assert.equal((await f.db.prepare('SELECT status FROM auth_mfa_factors WHERE id=?').bind(verified.factor.id).first()).status, 'verified');
  assert.equal((await f.db.prepare('SELECT status FROM auth_mfa_factors WHERE id=?').bind(pending.body.id).first()).status, 'pending');
});

for (const change of ['grant', 'session', 'account', 'verified']) {
  test(`cancellation rechecks ${change} state inside the actual atomic D1 operation`, async t => {
    const f = await fixture(t), owner = await f.seedAccount(), login = await f.login(owner);
    const pending = await enroll(f, login.cookie); assert.equal(pending.status, 200);
    f.setGate(async () => {
      if (change === 'grant') await f.db.prepare("DELETE FROM admin_grants WHERE user_id=? AND permission='auth.mfa.enroll'").bind(owner.userId).run();
      if (change === 'session') await f.db.prepare("UPDATE auth_sessions SET revoked_at=?,revocation_reason='controlled_recovery_race' WHERE user_id=?").bind(Math.floor(Date.now()/1000),owner.userId).run();
      if (change === 'account') await f.db.prepare("UPDATE admin_users SET status='revoked',auth_version=auth_version+1 WHERE id=?").bind(owner.adminId).run();
      if (change === 'verified') await f.db.prepare("UPDATE auth_mfa_factors SET status='verified',verified_at=?,last_totp_counter=1 WHERE id=?").bind(Math.floor(Date.now()/1000),pending.body.id).run();
    });
    const response = await cancel(f, login.cookie, pending.body.id, {'X-Test-Pause':'before_commit'});
    assert.ok([401,403,409].includes(response.status),JSON.stringify(response));
    const factor = await f.db.prepare('SELECT status FROM auth_mfa_factors WHERE id=?').bind(pending.body.id).first();
    assert.equal(factor.status, change === 'verified' ? 'verified' : 'pending');
    assert.equal((await f.db.prepare("SELECT count(*) AS n FROM audit_log WHERE action='auth.mfa.enrollment.cancelled'").first()).n,0);
  });
}
