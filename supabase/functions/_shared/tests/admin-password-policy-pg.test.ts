import assert from 'node:assert/strict';
import {fencedTest} from './helpers/fenced-unit.js';
import {openAdminPasswordFixture} from './helpers/admin-password-policy-fixture.js';

const database=Deno.env.get('COLLECT_ADMIN_PASSWORD_POLICY_TEST_DATABASE_URL');
const denied=(message:string)=>(error:any)=>error.code==='42501'&&error.message===message;

fencedTest({name:'Admin password policy FAST: actual full11 guard, independent email proof and exact original session',
 sanitizeResources:false,sanitizeOps:false,fn:async t=>{
 const fixture=await openAdminPasswordFixture(database),{sql}=fixture;
 try{
  const password=await fixture.actor(),oauth=await fixture.actor({method:'oauth'});
  await t.step('HasPassword normal original password and OAuth sessions accept a distinct completed email proof',async()=>{
   for(const a of [password,oauth]){
    await fixture.check(a);
    const retained=(await sql`SELECT o.original_session_id::text,o.verified_session_id::text,o.cleanup_state,
     s.assurance_level,s.mfa_at,s.mfa_factor_id,c.auth_session_id,c.token_hash,
     EXISTS(SELECT 1 FROM auth.sessions managed WHERE managed.id=o.verified_session_id) AS candidate_alive
     FROM private.admin_email_operations o JOIN app.auth_sessions s ON s.id=o.original_session_id::text
     JOIN app.admin_sessions c ON c.auth_session_id=s.id WHERE o.challenge_id=${a.proof!.challenge}`)[0];
    assert.equal(retained.original_session_id,a.sid);assert.notEqual(retained.verified_session_id,a.sid);
    assert.equal(retained.cleanup_state,'confirmed');assert.equal(retained.candidate_alive,false);
    assert.equal(retained.assurance_level,1);assert.equal(retained.mfa_at,null);assert.equal(retained.mfa_factor_id,null);
    assert.equal(retained.auth_session_id,a.sid);assert.equal(retained.token_hash,a.tokenHash);
    assert((await sql`SELECT authentication_method FROM auth.mfa_amr_claims WHERE session_id=${a.sid}`)
     .every((row:any)=>!['otp','magiclink','recovery'].includes(row.authentication_method)));
   }
  });
  await t.step('each signed otp, magiclink and recovery AMR independently refuses despite clean actual original AMR',async()=>{
   for(const method of ['otp','magiclink','recovery']){
    password.rawDb.setClaims({...password.claims,amr:[...password.claims.amr,{method,timestamp:Math.floor(Date.now()/1000)}]});
    try{await assert.rejects(()=>fixture.check(password),denied('password_recovery_required'));}
    finally{password.rawDb.setClaims(password.claims);}
    await fixture.check(password);
   }
  });
  await t.step('each actual managed otp, magiclink and recovery AMR independently refuses despite clean signed claims',async()=>{
   for(const method of ['otp','magiclink','recovery']){
    await sql`INSERT INTO auth.mfa_amr_claims(session_id,authentication_method,updated_at)
     VALUES(${password.sid},${method},now()-interval '20 minutes')`;
    try{await assert.rejects(()=>fixture.check(password),denied('password_recovery_required'));}
    finally{await sql`DELETE FROM auth.mfa_amr_claims WHERE session_id=${password.sid} AND authentication_method=${method}`;}
    await fixture.check(password);
   }
  });
  await t.step('passwordless NULL and empty actual hashes refuse even after genuine email possession proof',async()=>{
   const a=await fixture.actor({method:'oauth',hasPassword:false});
   await assert.rejects(()=>fixture.check(a),denied('password_recovery_required'));
   await sql`UPDATE auth.users SET encrypted_password='' WHERE id=${a.auth}`;
   await assert.rejects(()=>fixture.check(a),denied('password_recovery_required'));
  });
  await t.step('missing proof and a newly refreshed token without proof cannot authorize password change',async()=>{
   const a=await fixture.actor({emailProof:false});
   assert.equal((await fixture.status(a)).email_verified_at,null);
   await assert.rejects(()=>fixture.check(a),denied('recent_email_sign_in_required'));
   a.rawDb.setClaims({...a.claims,iat:Math.floor(Date.now()/1000),exp:Math.floor(Date.now()/1000)+1800});
   try{await assert.rejects(()=>fixture.check(a),denied('recent_email_sign_in_required'));}
   finally{a.rawDb.setClaims(a.claims);}
  });
  await t.step('signed Auth subject and session mismatches cannot inherit the original BFF proof',async()=>{
   for(const claims of [{...password.claims,sub:oauth.auth},{...password.claims,session_id:oauth.sid}]){
    password.rawDb.setClaims(claims);
    try{await assert.rejects(()=>fixture.check(password),denied('admin_email_denied'));}
    finally{password.rawDb.setClaims(password.claims);}
   }
   await fixture.check(password);
  });
  await t.step('actual managed session ownership mismatch is independently rejected',async()=>{
   await sql`UPDATE auth.sessions SET user_id=${oauth.auth} WHERE id=${password.sid}`;
   try{await assert.rejects(()=>fixture.check(password),denied('admin_email_denied'));}
   finally{await sql`UPDATE auth.sessions SET user_id=${password.auth} WHERE id=${password.sid}`;}
   await fixture.check(password);
  });
  await t.step('wrong requested origin and actual original origin drift cannot reuse a prior proof',async()=>{
   const changed='https://changed-password-origin.example';
   await assert.rejects(()=>fixture.check(password,fixture.wrap(password.rawDb,{...password.account,origin:changed})),denied('admin_email_denied'));
   await sql`UPDATE app.admin_sessions SET origin=${changed} WHERE token_hash=${password.tokenHash}`;
   try{
    await assert.rejects(()=>fixture.check(password),denied('admin_email_denied'));
    await assert.rejects(()=>fixture.check(password,fixture.wrap(password.rawDb,{...password.account,origin:changed})),denied('recent_email_sign_in_required'));
   }finally{await sql`UPDATE app.admin_sessions SET origin=${password.origin} WHERE token_hash=${password.tokenHash}`;}
   await fixture.check(password);
  });
  await t.step('removing the actual Admin-principal link revokes original proof authority',async()=>{
   await sql`DELETE FROM app.admin_principal_links WHERE admin_user_id=${oauth.adminId}`;
   await assert.rejects(()=>fixture.check(oauth),denied('admin_email_denied'));
   assert.equal((await sql`SELECT count(*)::int AS n FROM private.admin_sensitive_email_proofs WHERE principal_id=${oauth.principal}`)[0].n,1,
    'Revocation retains provenance instead of deleting proof history');
  });
  await t.step('SQL helper is boolean only, privileged and never exposes the managed hash',async()=>{
   const shape=(await sql`SELECT pg_get_function_result('private.assert_admin_password_change_context()'::regprocedure) AS result,
    (SELECT prosecdef FROM pg_proc WHERE oid='private.assert_admin_password_change_context()'::regprocedure) AS definer`)[0];
   assert.deepEqual({...shape},{result:'boolean',definer:true});
   for(const role of ['anon','authenticated','service_role']){
    assert.equal((await sql`SELECT has_function_privilege(${role},'private.assert_admin_password_change_context()','EXECUTE') AS allowed`)[0].allowed,false);
    await assert.rejects(()=>sql.begin(async(tx:any)=>{await tx.unsafe('SET LOCAL ROLE '+role);await tx`SELECT private.assert_admin_password_change_context()`;}),/permission denied/);
   }
   assert.equal((await sql`SELECT has_table_privilege('collect_runtime','auth.users','SELECT') AS allowed`)[0].allowed,false);
   await fixture.check(password);
  });
 }finally{await fixture.close();}
}});
