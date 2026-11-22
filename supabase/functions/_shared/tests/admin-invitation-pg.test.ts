import {loadReviewedPlatformFixture} from '../../../../scripts/supabase/testing/curated-platform-fixture.mjs';
import {initializeSqlFixture,finishSqlFixtureWork} from './helpers/fenced-postgres.js';
import {fencedTest} from './helpers/fenced-unit.js';
import assert from 'node:assert/strict';
import {connection,PostgresDatabase} from './helpers/fenced-postgres.js';
import {digest} from '../domain/core.js';
import {handleAdminInvitation} from './helpers/module-domain-admin_invitation.js';
import {inventoryPrivateRetention} from './helpers/module-private-retention.js';
import {fixtureAdminAccount,establishInitialAdminEmail,adminEmailFixtureDatabase} from './helpers/admin-email-fixture.js';
const database=Deno.env.get('COLLECT_INVITATION_TEST_DATABASE_URL');
fencedTest({name:'actual invitation helpers retain current owner authority and refuse unlinked legacy identity shadowing',ignore:!database,sanitizeOps:false,sanitizeResources:false,fn:async t=>{
 const url=new URL(database!);assert.ok(['postgres:','postgresql:'].includes(url.protocol));assert.equal(url.hostname,'127.0.0.1');assert.equal(url.username,'collect_test');assert.ok(url.password.length>0&&!url.search&&!url.hash);assert.ok(url.port==='55439'||(Deno.env.get('COLLECT_CI_SYNTHETIC')==='true'&&['55441','55443'].includes(url.port)));assert.equal(url.pathname,'/collect_admin_invitation_test');
 const adminUrl=new URL(url);adminUrl.pathname='/postgres';const admin=connection(adminUrl.href);if(!(await admin`SELECT 1 FROM pg_database WHERE datname='collect_admin_invitation_test'`).length)await admin.unsafe('CREATE DATABASE collect_admin_invitation_test');await admin.end();
 const sql=connection(database!),originalFetch=globalThis.fetch;try{
  const setup=await sql.reserve();try{await setup.unsafe('DROP SCHEMA IF EXISTS api,private,app,auth,realtime CASCADE');await setup.unsafe(await Deno.readTextFile(new URL('../../../tests/sql/00_local_auth_fixture.sql',import.meta.url)));
  await setup.unsafe('ALTER TABLE auth.users ADD COLUMN email_confirmed_at timestamptz');
  const reviewedPlatform=await loadReviewedPlatformFixture(new URL('../../../../',import.meta.url));await reviewedPlatform.apply(text=>setup.unsafe(text));}finally{setup.release();await initializeSqlFixture(sql);}
  const auth=crypto.randomUUID(),principal=crypto.randomUUID(),staff=crypto.randomUUID(),session=crypto.randomUUID(),factor=crypto.randomUUID(),publicSession=crypto.randomUUID(),stamp=new Date().toISOString(),at=Math.floor(Date.now()/1000)-1,hash=await digest('synthetic-invitation-owner-cookie'),origin='https://admin.example';
  await sql`INSERT INTO auth.users(id,email,email_confirmed_at)VALUES(${auth},'info@ikanisa.com',now())`;
  await sql`INSERT INTO auth.sessions(id,user_id,aal,factor_id)VALUES(${session},${auth},'aal2',${factor})`;
  await sql`INSERT INTO app.users(id,email,public_id,full_name,member_type,created_at,updated_at)VALUES(${principal},'info@ikanisa.com','930001','Synthetic Owner','operator',${stamp},${stamp})`;
  await sql`INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference)VALUES(${auth},${principal},'synthetic-local-invitation-fixture')`;
  await sql`INSERT INTO app.auth_sessions(id,user_id,surface,auth_at,created_at,expires_at)VALUES(${session},${principal},'admin',${at-66},${at-66},app.unixepoch()+3600)`;
  await sql`INSERT INTO app.admin_users(id,email,role,status,password_hash,display_name,created_at,updated_at)VALUES(${staff},'info@ikanisa.com','owner','active','synthetic-managed','Synthetic Owner',app.unixepoch(),app.unixepoch())`;
  await sql`INSERT INTO app.admin_principal_links(admin_user_id,user_id,approved_by,approved_at)VALUES(${staff},${principal},'synthetic-fixture',${stamp})`;
  assert.equal((await sql`SELECT count(*)::int AS n FROM app.admin_grants WHERE user_id=${principal} AND permission='admin_users.manage'`)[0].n,1);
  await sql`INSERT INTO app.admin_sessions(token_hash,public_id,user_id,auth_version,auth_session_id,origin,created_at,expires_at)SELECT ${hash},${publicSession},a.id,a.auth_version,${session},${origin},s.auth_at,s.expires_at FROM app.admin_users a CROSS JOIN app.auth_sessions s WHERE a.id=${staff} AND s.id=${session}`;
  await sql`INSERT INTO auth.mfa_factors(id,user_id,status)VALUES(${factor},${auth},'verified')`;
  await sql`INSERT INTO auth.mfa_amr_claims(session_id,authentication_method,updated_at)VALUES(${session},'totp',to_timestamp(${at}))`;
  await sql`INSERT INTO app.auth_mfa_factors(id,user_id,friendly_name,secret_ciphertext,status,created_at,enrollment_session_id,verified_at,last_totp_counter)VALUES(${factor},${principal},'Synthetic','{"managed_by":"supabase"}','verified',${at},${session},${at},0)`;
  const claims={sub:auth,session_id:session,role:'authenticated',aal:'aal2',amr:[{method:'otp',timestamp:at-66},{method:'totp',timestamp:at}]};const rawOwnerDb=new PostgresDatabase(sql,claims);let db:any=rawOwnerDb;
  await db.prepare('SELECT private.record_mfa_projection(?::uuid)').bind(factor).first();await db.prepare('UPDATE app.auth_sessions SET assurance_level=2,mfa_at=?,mfa_factor_id=? WHERE id=?').bind(at,factor,session).run();
  await sql`UPDATE app.admin_sessions SET issued_assurance_level=2,issued_mfa_at=${at},issued_mfa_factor_id=${factor} WHERE token_hash=${hash}`;
  await sql`INSERT INTO private.bff_sessions(token_hash,auth_user_id,auth_session_id,token_ciphertext)VALUES(${hash},${auth},${session},'{}')`;
  const args=[staff,hash,origin,publicSession];
  const ownerEmailAccount=await fixtureAdminAccount(sql,db,args);await establishInitialAdminEmail(sql,db,ownerEmailAccount);db=adminEmailFixtureDatabase(db,ownerEmailAccount);
  await t.step('real current managed owner/email/cookie tuple reaches read-only recovery',async()=>{const value=await db.prepare('SELECT private.admin_invitation_recover(?,?,?,?,?) AS result').bind(...args,'synthetic-before-prepare').first('result');assert.deepEqual(value,{found:false});});
  await t.step('confirmed managed email without authoritative link cannot shadow an existing local member',async()=>{
   const email='existing.unlinked@example.test',member=crypto.randomUUID(),managed=crypto.randomUUID();
   await sql`INSERT INTO app.users(id,email,public_id,full_name,member_type,created_at,updated_at)VALUES(${member},${email},'930002','Original member','app',${stamp},${stamp})`;
   await sql`INSERT INTO auth.users(id,email,email_confirmed_at)VALUES(${managed},${email},now())`;
   const before=(await sql`SELECT (SELECT count(*)::int FROM app.users) AS users,(SELECT count(*)::int FROM app.admin_users) AS staff,(SELECT count(*)::int FROM private.admin_invitation_attempts) AS attempts`)[0];
   await assert.rejects(()=>db.prepare('SELECT private.admin_invitation_prepare(?,?,?,?,?,?,?,?,?,?,?,?) AS result').bind(...args,'synthetic-unlinked-original','invite',crypto.randomUUID(),crypto.randomUUID(),email,'staff','Existing local member','a'.repeat(64)).first(),(error:any)=>error.message==='admin_invitation_identity_conflict');
   const after=(await sql`SELECT (SELECT count(*)::int FROM app.users) AS users,(SELECT count(*)::int FROM app.admin_users) AS staff,(SELECT count(*)::int FROM private.admin_invitation_attempts) AS attempts`)[0];assert.deepEqual(after,before);assert.equal((await sql`SELECT public_id FROM app.users WHERE id=${member}`)[0].public_id,'930002');
  });

  const prep=async(key:string,email:string,role='staff',name='Synthetic invitation',hashValue='b'.repeat(64),kind='invite',subject=crypto.randomUUID())=>db.prepare('SELECT private.admin_invitation_prepare(?,?,?,?,?,?,?,?,?,?,?,?) AS result').bind(...args,key,kind,subject,crypto.randomUUID(),email,role,name,hashValue).first('result');
  const recover=async(key:string,tuple=args)=>db.prepare('SELECT private.admin_invitation_recover(?,?,?,?,?) AS result').bind(...tuple,key).first('result');
  const claim=async(request:string,nonce:string)=>db.prepare('SELECT private.admin_invitation_claim(?,?,?,?,?::uuid,?::uuid) AS result').bind(...args,request,nonce).first('result');
  const finish=async(request:string,nonce:string,state:string)=>db.prepare('SELECT private.admin_invitation_finish(?,?,?,?,?::uuid,?::uuid,?,?) AS result').bind(...args,request,nonce,state,null).first('result');
  const journalCount=async()=>(await sql`SELECT count(*)::int AS n FROM private.admin_invitation_attempts`)[0].n;
  await t.step('local collision without any managed identity also refuses before writes',async()=>{
   const member=crypto.randomUUID(),email='local.only@example.test';await sql`INSERT INTO app.users(id,email,public_id,created_at,updated_at)VALUES(${member},${email},'930003',${stamp},${stamp})`;
   const before=await journalCount();await assert.rejects(()=>prep('local-only-original',email),(e:any)=>e.message==='admin_invitation_identity_conflict');assert.equal(await journalCount(),before);
  });
  await t.step('verified private identity link reuses exact member principal and public ID without another Auth user',async()=>{
   const member=crypto.randomUUID(),managed=crypto.randomUUID(),email='linked.member@example.test';await sql`INSERT INTO app.users(id,email,public_id,created_at,updated_at)VALUES(${member},${email},'930004',${stamp},${stamp})`;await sql`INSERT INTO auth.users(id,email,email_confirmed_at)VALUES(${managed},${email},now())`;await sql`INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference)VALUES(${managed},${member},'synthetic-verified-link')`;
   const authCount=(await sql`SELECT count(*)::int AS n FROM auth.users`)[0].n;const value=await prep('linked-member-original',email);assert.equal(value.principalId,member);assert.equal(value.emailStatus,'already_registered');assert.equal((await sql`SELECT public_id FROM app.users WHERE id=${member}`)[0].public_id,'930004');assert.equal((await sql`SELECT count(*)::int AS n FROM auth.users`)[0].n,authCount);assert.equal((await claim(value.requestId,crypto.randomUUID())).claimed,false);
  });
  await t.step('actual confirmed phone collision refuses an unlinked target before any local identity writes',async()=>{
   const member=crypto.randomUUID(),managed=crypto.randomUUID(),email='phone.collision@example.test',phone='+250788000123';
   await sql`INSERT INTO app.users(id,phone,public_id,created_at,updated_at)VALUES(${member},${phone},'930005',${stamp},${stamp})`;
   await sql`INSERT INTO auth.users(id,email,email_confirmed_at,phone,phone_confirmed_at)VALUES(${managed},${email},now(),${phone.slice(1)},now())`;
   const before=(await sql`SELECT (SELECT count(*)::int FROM app.users) AS users,(SELECT count(*)::int FROM app.admin_users) AS staff,(SELECT count(*)::int FROM private.admin_invitation_attempts) AS attempts`)[0];
   await assert.rejects(()=>prep('phone-collision-original',email),(e:any)=>e.message==='admin_invitation_identity_conflict');
   assert.deepEqual((await sql`SELECT (SELECT count(*)::int FROM app.users) AS users,(SELECT count(*)::int FROM app.admin_users) AS staff,(SELECT count(*)::int FROM private.admin_invitation_attempts) AS attempts`)[0],before);
  });
  const secondSession=crypto.randomUUID(),secondPublic=crypto.randomUUID(),secondHash=await digest('synthetic-invitation-second-cookie');
  await sql`INSERT INTO auth.sessions(id,user_id,aal,factor_id)VALUES(${secondSession},${auth},'aal2',${factor})`;
  await sql`INSERT INTO auth.mfa_amr_claims(session_id,authentication_method,updated_at)VALUES(${secondSession},'totp',to_timestamp(${at}))`;
  await sql`INSERT INTO app.auth_sessions(id,user_id,surface,auth_at,created_at,expires_at)VALUES(${secondSession},${principal},'admin',${at-5},${at-5},app.unixepoch()+3600)`;
  let secondDb:any=new PostgresDatabase(sql,{...claims,session_id:secondSession,amr:[{method:'otp',timestamp:at-5},{method:'totp',timestamp:at}]});
  await secondDb.prepare('SELECT private.record_mfa_projection(?::uuid)').bind(factor).first();
  await secondDb.prepare('UPDATE app.auth_sessions SET assurance_level=2,mfa_at=?,mfa_factor_id=? WHERE id=?').bind(at,factor,secondSession).run();
  await sql`INSERT INTO app.admin_sessions(token_hash,public_id,user_id,auth_version,auth_session_id,origin,created_at,expires_at,issued_assurance_level,issued_mfa_at,issued_mfa_factor_id)SELECT ${secondHash},${secondPublic},a.id,a.auth_version,${secondSession},${origin},s.auth_at,s.expires_at,1,NULL,NULL FROM app.admin_users a CROSS JOIN app.auth_sessions s WHERE a.id=${staff} AND s.id=${secondSession}`;
  await sql`UPDATE app.admin_sessions SET issued_assurance_level=2,issued_mfa_at=${at},issued_mfa_factor_id=${factor} WHERE token_hash=${secondHash}`;
  await sql`INSERT INTO private.bff_sessions(token_hash,auth_user_id,auth_session_id,token_ciphertext)VALUES(${secondHash},${auth},${secondSession},'{}')`;
  const secondArgs=[staff,secondHash,origin,secondPublic];
  const secondEmailAccount=await fixtureAdminAccount(sql,secondDb,secondArgs);await establishInitialAdminEmail(sql,secondDb,secondEmailAccount);secondDb=adminEmailFixtureDatabase(secondDb,secondEmailAccount);
  await t.step('a second valid owner browser may claim a reserved operation but only its exact dispatch session may finish',async()=>{
   const value=await prep('second-browser-original','second.browser@example.test'),nonce=crypto.randomUUID();
   assert.deepEqual(await secondDb.prepare('SELECT private.admin_invitation_recover(?,?,?,?,?) AS result').bind(...secondArgs,'second-browser-missing').first('result'),{found:false});
   const claimed=await secondDb.prepare('SELECT private.admin_invitation_claim(?,?,?,?,?::uuid,?::uuid) AS result').bind(...secondArgs,value.requestId,nonce).first('result');assert.equal(claimed.claimed,true);
   assert.equal((await sql`SELECT original_session_id::text,dispatch_session_id::text FROM private.admin_invitation_attempts WHERE request_id=${value.requestId}`)[0].original_session_id,session);
   assert.equal((await sql`SELECT dispatch_session_id::text FROM private.admin_invitation_attempts WHERE request_id=${value.requestId}`)[0].dispatch_session_id,secondSession);
   await assert.rejects(()=>finish(value.requestId,nonce,'accepted'),(e:any)=>e.message==='admin_invitation_authority');
   assert.equal((await secondDb.prepare('SELECT private.admin_invitation_finish(?,?,?,?,?::uuid,?::uuid,?,?) AS result').bind(...secondArgs,value.requestId,nonce,'accepted',null).first('result')).emailStatus,'accepted');
  });
  let reserved:any;
  await t.step('new target reserves once and replays original IDs despite different candidate UUIDs',async()=>{
   reserved=await prep('new-invite-original','new.invitation@example.test');assert.equal(reserved.emailStatus,'reserved');const replay=await prep('new-invite-original','new.invitation@example.test');assert.equal(replay.requestId,reserved.requestId);assert.equal(replay.id,reserved.id);assert.equal(replay.principalId,reserved.principalId);assert.equal(replay.replayed,true);
   await assert.rejects(()=>prep('new-invite-original','new.invitation@example.test','staff','Changed body','c'.repeat(64)),(e:any)=>e.message==='admin_invitation_idempotency_conflict');
  });
  await t.step('new duplicate key aliases reserved history and can never claim a second operation',async()=>{
   const duplicate=await prep('new-invite-duplicate','new.invitation@example.test');assert.equal(duplicate.duplicate,true);assert.equal(duplicate.requestId,reserved.requestId);assert.equal(duplicate.emailStatus,'reserved');const alias=(await sql`SELECT request_id FROM private.admin_invitation_attempts WHERE idempotency_key='new-invite-duplicate'`)[0].request_id;await assert.rejects(()=>claim(alias,crypto.randomUUID()),(e:any)=>e.message==='admin_invitation_invalid');
  });
  await t.step('two concurrent current claims yield exactly one winner and wrong nonce cannot finish',async()=>{
   const nonces=[crypto.randomUUID(),crypto.randomUUID()],results=await Promise.all(nonces.map(nonce=>claim(reserved.requestId,nonce)));assert.equal(results.filter(r=>r.claimed===true).length,1);const winner=nonces[results.findIndex(r=>r.claimed===true)],loser=nonces[results.findIndex(r=>r.claimed!==true)];await assert.rejects(()=>finish(reserved.requestId,loser,'accepted'),(e:any)=>e.message==='admin_invitation_authority');assert.equal((await recover('new-invite-original')).emailStatus,'dispatching');const done=await finish(reserved.requestId,winner,'accepted');assert.equal(done.emailStatus,'accepted');assert.equal((await finish(reserved.requestId,winner,'accepted')).emailStatus,'accepted');
  });
  await t.step('unknown dispatched outcome cannot get a new-send reservation, accepted outcome can explicit resend',async()=>{
   const unknown=await prep('unknown-send-original','unknown.send@example.test'),nonce=crypto.randomUUID();assert.equal((await claim(unknown.requestId,nonce)).claimed,true);await finish(unknown.requestId,nonce,'unknown');const alias=await prep('unknown-explicit-resend','unused@example.test','staff','Synthetic invitation','d'.repeat(64),'resend',unknown.id);assert.equal(alias.duplicate,true);assert.equal(alias.requestId,unknown.requestId);assert.equal(alias.emailStatus,'unknown');const next=await prep('accepted-explicit-resend','unused@example.test','staff','Synthetic invitation','e'.repeat(64),'resend',reserved.id);assert.equal(next.emailStatus,'reserved');assert.notEqual(next.requestId,reserved.requestId);
  });
  await t.step('wrong cookie, public session, origin and claims cannot use current owner recovery',async()=>{
   for(const tuple of [[staff,'f'.repeat(64),origin,publicSession],[staff,hash,'https://foreign.example',publicSession],[staff,hash,origin,crypto.randomUUID()]])await assert.rejects(()=>recover('new-invite-original',tuple),(e:any)=>e.message==='admin_invitation_authority');
   const foreign=new PostgresDatabase(sql,{...claims,sub:crypto.randomUUID()});await assert.rejects(()=>foreign.prepare('SELECT private.admin_invitation_recover(?,?,?,?,?) AS result').bind(...args,'new-invite-original').first(),(e:any)=>e.message==='admin_invitation_authority');
  });
  await t.step('prepare, claim and finish each reject a mismatched cookie before any state changes',async()=>{
   const value=await prep('authority-mutators-original','authority.mutators@example.test'),nonce=crypto.randomUUID(),bad=[staff,'f'.repeat(64),origin,publicSession];
   const before=JSON.stringify(await sql`SELECT * FROM private.admin_invitation_attempts ORDER BY attempt_sequence`);
   await assert.rejects(()=>db.prepare('SELECT private.admin_invitation_prepare(?,?,?,?,?,?,?,?,?,?,?,?) AS result').bind(...bad,'foreign-cookie-original','invite',crypto.randomUUID(),crypto.randomUUID(),'foreign.cookie@example.test','staff','Synthetic invitation','a'.repeat(64)).first(),(e:any)=>e.message==='admin_invitation_authority');
   await assert.rejects(()=>db.prepare('SELECT private.admin_invitation_claim(?,?,?,?,?::uuid,?::uuid) AS result').bind(...bad,value.requestId,nonce).first(),(e:any)=>e.message==='admin_invitation_authority');
   assert.equal(JSON.stringify(await sql`SELECT * FROM private.admin_invitation_attempts ORDER BY attempt_sequence`),before);
   assert.equal((await claim(value.requestId,nonce)).claimed,true);const dispatch=JSON.stringify(await sql`SELECT * FROM private.admin_invitation_attempts ORDER BY attempt_sequence`);
   await assert.rejects(()=>db.prepare('SELECT private.admin_invitation_finish(?,?,?,?,?::uuid,?::uuid,?,?) AS result').bind(...bad,value.requestId,nonce,'accepted',null).first(),(e:any)=>e.message==='admin_invitation_authority');
   assert.equal(JSON.stringify(await sql`SELECT * FROM private.admin_invitation_attempts ORDER BY attempt_sequence`),dispatch);await finish(value.requestId,nonce,'rejected');
  });
  await t.step('target identity mutation fences both claim and recovery rather than accepting stale approval',async()=>{
   const value=await prep('target-change-original','target.change@example.test'),before=JSON.stringify(await sql`SELECT * FROM private.admin_invitation_attempts WHERE request_id=${value.requestId}`);
   await sql`UPDATE app.admin_users SET display_name='Changed target identity' WHERE id=${value.id}`;
   for(const op of [()=>claim(value.requestId,crypto.randomUUID()),()=>recover('target-change-original')])await assert.rejects(op,(e:any)=>e.message==='admin_invitation_identity_conflict');
   assert.equal(JSON.stringify(await sql`SELECT * FROM private.admin_invitation_attempts WHERE request_id=${value.requestId}`),before);
  });
  await t.step('recovery is read-only and identities, terminal states and private ACLs remain fenced',async()=>{
   const before=await journalCount(),snapshot=JSON.stringify(await sql`SELECT * FROM private.admin_invitation_attempts ORDER BY attempt_sequence`);await recover('new-invite-original');assert.equal(await journalCount(),before);assert.equal(JSON.stringify(await sql`SELECT * FROM private.admin_invitation_attempts ORDER BY attempt_sequence`),snapshot);
   await assert.rejects(()=>sql`UPDATE private.admin_invitation_attempts SET actor_principal_id=${crypto.randomUUID()} WHERE request_id=${reserved.requestId}`,(e:any)=>e.message==='admin_invitation_identity_conflict');await assert.rejects(()=>sql`UPDATE private.admin_invitation_attempts SET state='reserved',claim_nonce=NULL,dispatch_session_id=NULL,claimed_at=NULL,finished_at=NULL WHERE request_id=${reserved.requestId}`,(e:any)=>e.message==='admin_invitation_invalid');
   for(const role of ['anon','authenticated','collect_runtime']){const c=await sql.reserve();try{await c.unsafe('BEGIN');await c.unsafe('SET LOCAL ROLE '+role);await assert.rejects(()=>c.unsafe(role==='collect_runtime'?"DELETE FROM private.admin_invitation_attempts":"SELECT * FROM private.admin_invitation_attempts"),(e:any)=>e.code==='42501');}finally{await c.unsafe('ROLLBACK');c.release();}}
   assert.equal((await sql`SELECT count(*)::int AS n FROM app.ledger_entries`)[0].n,0);
  });

  let providerCalls=0;
  globalThis.fetch=async(input:RequestInfo|URL,init?:RequestInit)=>{const request=new Request(input,init);assert.equal(request.url,'https://synthetic-invitation.example/auth/v1/invite');assert.equal(request.method,'POST');const body=await request.json();providerCalls++;return Response.json({id:crypto.randomUUID(),email:body.email,email_confirmed_at:null,invited_at:new Date().toISOString()});};
  const account=ownerEmailAccount;
  const environment={DB:db,SUPABASE_URL:'https://synthetic-invitation.example',SUPABASE_SECRET_KEY:'sb_secret_synthetic_invitation_only',SUPABASE_SERVICE_ROLE_KEY:'sb_secret_synthetic_invitation_only',SUPABASE_PUBLISHABLE_KEY:'sb_publishable_synthetic_invitation_only'};
  const makeBody=(email:string)=>({email,role:'staff',displayName:'Synthetic invitation'});
  const callController=async(key:string,body:object,port:unknown=db,recovery=false)=>{const request=new Request(origin+'/api/admin/team/'+(recovery?'invitation-status':'invite'),{method:recovery?'GET':'POST',headers:{'Idempotency-Key':key}});const response=await handleAdminInvitation(request,{...environment,DB:port},account,body,recovery?'/team/invitation-status':'/team/invite');assert.ok(response);return{status:response.status,body:await response.json()};};
  function lostReply(functionName:string){let fired=false;return{prepare(text:string){const statement=db.prepare(text);return{bind(...values:unknown[]){const bound=statement.bind(...values);return{async first(){const row=await bound.first();if(!fired&&text.includes('private.admin_invitation_'+functionName+'(')){fired=true;throw Error('Synthetic committed '+functionName+' acknowledgement lost');}return row;}};}};}};}
  await t.step('actual controller and PostgreSQL recover a lost preparation reply before one explicit original-key send',async()=>{
   const key='controller-lost-prepare',body=makeBody('controller.prepare@example.test'),before=providerCalls;const lost=await callController(key,body,lostReply('prepare'));assert.equal(lost.status,503);assert.equal(lost.body.outcome,'operation_unknown');assert.equal(providerCalls,before);const current=await callController(key,{},db,true);assert.equal(current.body.found,true);const result=await callController(key,body);assert.equal(result.status,200);assert.equal(result.body.requestId,current.body.requestId);assert.equal(providerCalls,before+1);assert.equal((await callController(key,body)).status,200);assert.equal(providerCalls,before+1);
  });
  await t.step('actual controller holds a committed lost-claim reply without any provider call or resend',async()=>{
   const key='controller-lost-claim',body=makeBody('controller.claim@example.test'),before=providerCalls;const lost=await callController(key,body,lostReply('claim'));assert.equal(lost.status,503);assert.equal(lost.body.outcome,'operation_unknown');const recovered=await callController(key,{},db,true);assert.equal(recovered.body.found,true);assert.equal(recovered.body.requestId,lost.body.requestId);const retry=await callController(key,body);assert.equal(retry.status,503);assert.equal(retry.body.outcome,'delivery_unknown');assert.equal(providerCalls,before);
  });
  await t.step('actual controller and PostgreSQL reconcile lost accepted finish with exactly one provider dispatch',async()=>{
   const key='controller-lost-finish',body=makeBody('controller.finish@example.test'),before=providerCalls;const lost=await callController(key,body,lostReply('finish'));assert.equal(lost.status,503);assert.equal(lost.body.outcome,'operation_unknown');assert.equal(providerCalls,before+1);const recovered=await callController(key,{},db,true);assert.equal(recovered.body.found,true);assert.equal(recovered.body.emailStatus,'accepted');assert.equal(recovered.body.requestId,lost.body.requestId);const replay=await callController(key,body);assert.equal(replay.status,200);assert.equal(providerCalls,before+1);assert.equal((await sql`SELECT count(*)::int AS n FROM private.admin_invitation_attempts WHERE idempotency_key=${key}`)[0].n,1);
  });
  await t.step('stale cookie projection is refused and refresh lease, factor and session revocation deny recovery',async()=>{
   // The managed projection guard rejects a fabricated stale cookie itself.
   // This does not emulate aging a complete real managed proof.
   await assert.rejects(()=>sql`UPDATE app.admin_sessions SET issued_mfa_at=${at-601} WHERE token_hash=${hash}`,(e:any)=>e.message==='real_mfa_required');assert.equal((await recover('new-invite-original')).emailStatus,'accepted');
   const journalBefore=JSON.stringify(await sql`SELECT * FROM private.admin_invitation_attempts ORDER BY request_id`),callsBefore=providerCalls;
   const deniedAtBothSqlLayers=async()=>{
    // The fixture's real email-context setter is outside the invitation actor.
    // Its earlier denial must not replace qualification of the inner helper.
    await assert.rejects(()=>recover('new-invite-original'),(e:any)=>e.code==='42501'&&e.message==='admin_email_denied');
    await assert.rejects(()=>rawOwnerDb.prepare('SELECT private.admin_invitation_recover(?,?,?,?,?) AS result').bind(...args,'new-invite-original').first('result'),
     (e:any)=>e.code==='42501'&&e.message==='admin_invitation_authority');
    assert.equal(JSON.stringify(await sql`SELECT * FROM private.admin_invitation_attempts ORDER BY request_id`),journalBefore);assert.equal(providerCalls,callsBefore);
   };
   await sql`UPDATE private.bff_sessions SET refresh_lease='synthetic-refresh' WHERE token_hash=${hash}`;
   try{await deniedAtBothSqlLayers();}finally{await sql`UPDATE private.bff_sessions SET refresh_lease=NULL WHERE token_hash=${hash}`;}
   await sql`UPDATE auth.mfa_factors SET status='unverified' WHERE id=${factor}`;
   try{await deniedAtBothSqlLayers();}finally{await sql`UPDATE auth.mfa_factors SET status='verified' WHERE id=${factor}`;}
   await sql`UPDATE app.auth_sessions SET revoked_at=app.unixepoch(),revocation_reason='synthetic_revoke' WHERE id=${session}`;await deniedAtBothSqlLayers();
  });
  await t.step('a separate current reviewer attributes invitation history after original actor Admin unlink',async()=>{
   const reviewer=crypto.randomUUID(),reviewAuth=crypto.randomUUID(),reviewSession=crypto.randomUUID(),reviewFactor=crypto.randomUUID(),reviewAt=Math.floor(Date.now()/1000)-1;
   await sql`INSERT INTO auth.users(id,email,email_confirmed_at)VALUES(${reviewAuth},'privacy.reviewer@example.test',now())`;
   await sql`INSERT INTO app.users(id,email,public_id,created_at,updated_at)VALUES(${reviewer},'privacy.reviewer@example.test','930006',${stamp},${stamp})`;
   await sql`INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference)VALUES(${reviewAuth},${reviewer},'synthetic-privacy-reviewer')`;
   await sql`INSERT INTO app.admin_grants(user_id,permission,granted_by,granted_at)VALUES(${reviewer},'privacy.review','synthetic-fixture',${stamp})`;
   await sql`INSERT INTO auth.sessions(id,user_id,aal,factor_id)VALUES(${reviewSession},${reviewAuth},'aal2',${reviewFactor})`;
   await sql`INSERT INTO auth.mfa_factors(id,user_id,status)VALUES(${reviewFactor},${reviewAuth},'verified')`;
   await sql`INSERT INTO auth.mfa_amr_claims(session_id,authentication_method,updated_at)VALUES(${reviewSession},'totp',to_timestamp(${reviewAt}))`;
   await sql`INSERT INTO app.auth_sessions(id,user_id,surface,auth_at,created_at,expires_at)VALUES(${reviewSession},${reviewer},'admin',${reviewAt-5},${reviewAt-5},app.unixepoch()+3600)`;
   await sql`INSERT INTO app.auth_mfa_factors(id,user_id,friendly_name,secret_ciphertext,status,created_at,enrollment_session_id,verified_at,last_totp_counter)VALUES(${reviewFactor},${reviewer},'Synthetic reviewer','{"managed_by":"supabase"}','verified',${reviewAt},${reviewSession},${reviewAt},0)`;
   let reviewerDb:any=new PostgresDatabase(sql,{sub:reviewAuth,session_id:reviewSession,role:'authenticated',aal:'aal2',amr:[{method:'otp',timestamp:reviewAt-5},{method:'totp',timestamp:reviewAt}]});
   await reviewerDb.prepare('SELECT private.record_mfa_projection(?::uuid)').bind(reviewFactor).first();await reviewerDb.prepare('UPDATE app.auth_sessions SET assurance_level=2,mfa_at=?,mfa_factor_id=? WHERE id=?').bind(reviewAt,reviewFactor,reviewSession).run();
   const reviewerAdmin=crypto.randomUUID(),reviewerPublic=crypto.randomUUID(),reviewerHash=await digest('synthetic-linked-reviewer-cookie');
   await sql`INSERT INTO app.admin_users(id,email,role,status,password_hash,created_at,updated_at)VALUES(${reviewerAdmin},'privacy.reviewer@example.test','admin','active','synthetic-managed',${reviewAt},${reviewAt})`;
   await sql`INSERT INTO app.admin_principal_links(admin_user_id,user_id,approved_by,approved_at)VALUES(${reviewerAdmin},${reviewer},'synthetic-reviewer-fixture',${stamp})`;
   await sql`INSERT INTO app.admin_sessions(token_hash,public_id,user_id,auth_version,auth_session_id,origin,created_at,expires_at)SELECT ${reviewerHash},${reviewerPublic},a.id,a.auth_version,s.id,${origin},s.auth_at,s.expires_at FROM app.admin_users a CROSS JOIN app.auth_sessions s WHERE a.id=${reviewerAdmin} AND s.id=${reviewSession}`;
   await sql`INSERT INTO private.bff_sessions(token_hash,auth_user_id,auth_session_id,token_ciphertext)VALUES(${reviewerHash},${reviewAuth},${reviewSession},'{}')`;
   const reviewerAccount=await fixtureAdminAccount(sql,reviewerDb,[reviewerAdmin,reviewerHash,origin,reviewerPublic]);await establishInitialAdminEmail(sql,reviewerDb,reviewerAccount);reviewerDb=adminEmailFixtureDatabase(reviewerDb,reviewerAccount);
   // An explicit per-person grant cannot exceed the actual baseline Admin role.
   await assert.rejects(()=>inventoryPrivateRetention({DB:reviewerDb},principal),(error:any)=>error.message==='permission_denied');
   // This local-only policy fixture configures one approved reviewer capability
   // to test independent retained-history attribution. No runtime migration or
   // production role catalog is changed; the baseline denial above is retained.
   await sql`INSERT INTO app.admin_account_role_capabilities(role,permission)VALUES('admin','privacy.review')`;
   const expected=(await sql`SELECT count(*)::int AS n FROM private.admin_invitation_attempts WHERE actor_principal_id=${principal} OR principal_id=${principal}`)[0].n;
   assert.ok(expected>0);const before=await inventoryPrivateRetention({DB:reviewerDb},principal);assert.equal(before.classes['private:admin_invitation_attempts'].count,expected);
   await sql`DELETE FROM app.admin_principal_links WHERE admin_user_id=${staff}`;
   assert.equal((await sql`SELECT count(*)::int AS n FROM app.admin_principal_links WHERE admin_user_id=${staff}`)[0].n,0);
   const after=await inventoryPrivateRetention({DB:reviewerDb},principal);assert.deepEqual(after.classes['private:admin_invitation_attempts'],before.classes['private:admin_invitation_attempts']);assert.equal(after.in_flight_unresolved,true);
   assert.equal((await inventoryPrivateRetention({DB:reviewerDb},reviewer)).classes['private:admin_invitation_attempts'].count,0);
   assert.equal((await sql`SELECT count(*)::int AS n FROM app.ledger_entries`)[0].n,0);
  });
 }finally{globalThis.fetch=originalFetch;await finishSqlFixtureWork();await sql.end();}
}});
