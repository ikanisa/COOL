import assert from 'node:assert/strict';
import {digest} from '../../domain/core.js';
import {loadAdminEmailAccount} from '../../domain/admin_email_auth.js';
import {bindAdminEmailActor} from '../../domain/admin_email_policy.js';

// Local managed-Auth service model only. Never call this against a hosted DB.
async function local(sql){
 const row=(await sql`SELECT current_database() AS db,host(inet_server_addr()) AS host`)[0];
 assert(['127.0.0.1','::1'].includes(row.host));
 assert(['collect_admin_invitation_test','collect_invitation_notice_test','collect_sms_content_test',
  'collect_private_retention_test','collect_receipt_facts_test','collect_admin_email_test','collect_notification_delivery_test'].includes(row.db));
}
export async function fixtureAdminAccount(sql,db,args){
 await local(sql);
 const [id,hash,origin,publicId]=args;
 // Confirmed email is a managed fixture fact, not a sufficient proof by itself.
 await sql.unsafe('ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS email_confirmed_at timestamptz');
 await sql`UPDATE auth.users SET email_confirmed_at=coalesce(email_confirmed_at,now()) WHERE id=${db.claims.sub}`;
 const row=(await sql`SELECT a.*,c.token_hash,c.public_id,c.origin,c.auth_session_id,c.issued_assurance_level,
  c.issued_mfa_at,c.issued_mfa_factor_id,l.user_id AS principal_id,b.auth_user_id::text AS auth_user_id
  FROM app.admin_users a JOIN app.admin_principal_links l ON l.admin_user_id=a.id
  JOIN app.admin_sessions c ON c.user_id=a.id JOIN private.bff_sessions b ON b.token_hash=c.token_hash
  WHERE a.id=${id} AND c.token_hash=${hash} AND c.public_id=${publicId} AND c.origin=${origin}`)[0];
 assert(row);assert.equal(row.auth_user_id,db.claims.sub);assert.equal(row.auth_session_id,db.claims.session_id);
 const permissions=await sql`SELECT g.permission FROM app.admin_grants g JOIN app.admin_account_role_capabilities c
  ON c.permission=g.permission AND c.role=${row.role} WHERE g.user_id=${row.principal_id}`;
 return {...row,permissions:permissions.map(v=>v.permission)};
}
const tuple=a=>[a.id,a.token_hash,a.origin,a.public_id];
const uuidArgs={admin_email_send_claim:[5],admin_email_send_finish:[5],admin_email_verify_claim:[5],
 admin_email_verify_finish:[5],admin_email_record:[5],admin_email_cleanup_claim:[5,6],admin_email_cleanup_finish:[5,6]};
const call=(db,name,args)=>db.prepare(`SELECT private.${name}(${args.map((_,i)=>(uuidArgs[name]??[]).includes(i)?'?::uuid':'?').join(',')}) AS result`).bind(...args).first('result');
export async function establishInitialAdminEmail(sql,db,account){
 await local(sql);const at=Number((await sql`SELECT auth_at FROM app.auth_sessions WHERE id=${account.auth_session_id}`)[0].auth_at);
 assert(db.claims.amr?.some(v=>v.method==='otp'&&v.timestamp===at),'Initial proof needs the original managed email OTP event');
 const id=crypto.randomUUID(),identity=account.email.toLowerCase(),hash=await digest('email:'+identity);
 await sql`INSERT INTO auth.mfa_amr_claims(session_id,authentication_method,updated_at)
  VALUES(${account.auth_session_id},'otp',to_timestamp(${at})) ON CONFLICT(session_id,authentication_method)
  DO UPDATE SET updated_at=excluded.updated_at`;
 await sql`INSERT INTO private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,
  registration_allowed,created_at,expires_at,attempts,consumed_at,delivery_status)
  VALUES(${id},${hash},'email',${identity},'admin',0,${at-1},${at+299},1,${at},'accepted')`;
 await call(db,'admin_email_record_initial',[...tuple(account),id]);
 const status=await call(db,'admin_email_status',tuple(account));assert(status.proof_id);assert.equal(status.email_verified_at,at);
 await loadAdminEmailAccount({DB:db},account);return {account,status,challenge:id};
}
export async function establishRecentAdminEmail(sql,db,account){
 await local(sql);const original=structuredClone(db.claims),id=crypto.randomUUID(),send=crypto.randomUUID(),verify=crypto.randomUUID(),cleanup=crypto.randomUUID();
 const before=JSON.stringify(await sql`SELECT to_jsonb(s) AS app,to_jsonb(c) AS cookie,to_jsonb(b) AS bff
  FROM app.auth_sessions s JOIN app.admin_sessions c ON c.auth_session_id=s.id
  JOIN private.bff_sessions b ON b.token_hash=c.token_hash WHERE c.token_hash=${account.token_hash}`);
 const prepared=await call(db,'admin_email_prepare',[...tuple(account),id]);assert.equal(prepared.created,true);
 assert.equal((await call(db,'admin_email_send_claim',[...tuple(account),id,send])).claimed,true);
 await call(db,'admin_email_send_finish',[...tuple(account),id,send,'accepted']);
 assert.equal((await call(db,'admin_email_verify_claim',[...tuple(account),id,verify])).claimed,true);
 const candidate=crypto.randomUUID(),at=Number((await sql`SELECT app.unixepoch() AS at`)[0].at);
 await sql`INSERT INTO auth.sessions(id,user_id,aal)VALUES(${candidate},${original.sub},'aal1')`;
 await sql`INSERT INTO auth.mfa_amr_claims(session_id,authentication_method,updated_at)VALUES(${candidate},'otp',to_timestamp(${at}))`;
 const candidateClaims={...original,session_id:candidate,aal:'aal1',amr:[{method:'otp',timestamp:at}]};
 // These exercise the real kernel against genuine local managed OTP evidence.
 // Fresh password/OAuth/refresh iat, a forged AAL2, wrong subject, original SID
 // and zero/missing SID must never substitute for this exact independent event.
 for(const claims of [
  {...candidateClaims,aal:'aal2',iat:at,amr:[{method:'password',timestamp:at}]},
  {...candidateClaims,iat:at,amr:[{method:'oauth',timestamp:at}]},
  {...candidateClaims,iat:at,amr:[{method:'token_refresh',timestamp:at}]},
  {...candidateClaims,amr:[{method:'otp',timestamp:at-10}]},
  {...candidateClaims,sub:crypto.randomUUID()},
  {...candidateClaims,session_id:original.session_id},
  {...candidateClaims,session_id:'00000000-0000-0000-0000-000000000000'},
  {...candidateClaims,session_id:undefined}
 ]){
  db.setClaims(claims);
  try{await assert.rejects(()=>call(db,'admin_email_record',[...tuple(account),id,verify]),error=>error.message==='admin_email_candidate_denied');}
  finally{db.setClaims(original);}
 }
 for(const args of [[account.id,'f'.repeat(64),account.origin,account.public_id],
  [account.id,account.token_hash,'https://foreign-admin.example',account.public_id],
  [account.id,account.token_hash,account.origin,crypto.randomUUID()]])
  await assert.rejects(()=>call(db,'admin_email_status',args),error=>error.message==='admin_email_denied');
 const unchanged=(await sql`SELECT verification_state,consumed_at FROM private.admin_email_operations o
  JOIN private.supabase_otp_challenges c ON c.id=o.challenge_id WHERE o.challenge_id=${id}`)[0];
 assert.equal(unchanged.verification_state,'verifying');assert.equal(unchanged.consumed_at,null);
 db.setClaims(candidateClaims);
 try{await call(db,'admin_email_record',[...tuple(account),id,verify]);}finally{db.setClaims(original);}
 const pending=await call(db,'admin_email_status',tuple(account));assert.equal(pending.email_verified_at,null,'Unconfirmed cleanup grants no freshness');
 await assert.rejects(()=>call(db,'admin_email_cleanup_finish',[...tuple(account),id,verify,cleanup,'confirmed']),error=>error.message==='admin_email_denied');
 assert.equal((await call(db,'admin_email_cleanup_claim',[...tuple(account),id,verify,cleanup])).claimed,true);
 await assert.rejects(()=>call(db,'admin_email_cleanup_finish',[...tuple(account),id,verify,cleanup,'confirmed']),error=>error.message==='admin_email_cleanup_unconfirmed');
 // Exact-session synthetic GoTrue model. This is local fixture owner DML, not
 // a production cleanup implementation or provider-version equivalence proof.
 await sql`DELETE FROM auth.mfa_amr_claims WHERE session_id=${candidate}`;
 await sql`DELETE FROM auth.sessions WHERE id=${candidate}`;
 await call(db,'admin_email_cleanup_finish',[...tuple(account),id,verify,cleanup,'confirmed']);
 assert.equal(JSON.stringify(await sql`SELECT to_jsonb(s) AS app,to_jsonb(c) AS cookie,to_jsonb(b) AS bff
  FROM app.auth_sessions s JOIN app.admin_sessions c ON c.auth_session_id=s.id
  JOIN private.bff_sessions b ON b.token_hash=c.token_hash WHERE c.token_hash=${account.token_hash}`),before,
  'Email verification preserves the original app/BFF session tuple byte-for-byte');
 const status=await call(db,'admin_email_status',tuple(account));assert(status.proof_id);assert.equal(status.email_verified_at,at);
 await loadAdminEmailAccount({DB:db},account);return {account,status,challenge:id};
}

export function adminEmailFixtureDatabase(db,account){
 const args=tuple(account);const wrapped={
  get sql(){return db.sql;},get claims(){return db.claims;},get applicationWork(){return db.applicationWork;},
  setClaims(claims){db.setClaims(claims);},setApplicationWork(work){db.setApplicationWork(work);},withSession(){return wrapped;},
  async context(tx){await db.context(tx);await tx.unsafe('SELECT private.set_admin_email_context($1,$2,$3,$4)',args);},
  async readContext(tx){await db.readContext(tx);await tx.unsafe('SELECT private.set_admin_email_context($1,$2,$3,$4)',args);},
  prepare(sql){return statement(sql,[]);},transaction(fn){return db.transaction(fn);},
  async execute(value){return (await wrapped.batch([value]))[0];},query(sql,values=[]){return statement(sql,values).all();},
  async batch(statements){const result=await db.batch([db.prepare('SELECT private.set_admin_email_context(?,?,?,?)').bind(...args),...statements]);return result.slice(1);}
 };
 function statement(sql,values){return {sql,values,bind(...next){return statement(sql,next);},
  async all(){return (await wrapped.batch([this]))[0];},async run(){return this.all();},
  async first(column){const row=(await this.all()).results[0]??null;return column&&row?row[column]:row;},
  async raw(){return (await this.all()).results.map(Object.values);}};}
 return wrapped;
}
export function bindFixtureAdminActor(actor,account){bindAdminEmailActor(actor,account);return actor;}
