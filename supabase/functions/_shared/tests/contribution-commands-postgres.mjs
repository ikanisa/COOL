import assert from 'node:assert/strict';
import {contributionCommandRpc} from '../domain/contribution_commands.js';
import {financialRpc,normalizeContributionSender} from '../domain/payments.js';
import {projectSession} from '../domain/auth.js';
import {digest,stableJson} from '../domain/core.js';
import worker from '../domain/index.js';
import {PostgresDatabase} from './helpers/fenced-postgres.js';

// Called only by an independently owned fresh native-PG fixture. This function
// neither starts a cluster nor accepts a hosted URL. Real SQL/roles/handlers and
// HTTP serialization execute; the caller supplies synthetic verified GoTrue
// facts. This is not provider signature, device or production acceptance.
export async function assertContributionCommandsOnPostgres(context){
 const {sql,db,member,authId,sid,group}=context;
 const [identity]=await sql.unsafe("SELECT current_database() AS name,host(inet_server_addr()) AS host,inet_server_port() AS port,current_setting('server_version_num')::integer AS version");
 assert.equal(identity.name,'collect_payment_route_test');assert.equal(identity.host,'127.0.0.1');assert.equal(identity.port,55447);assert.equal(identity.version,170010);
 const env={...context.env,COLLECT_FENCE_WORK:db.applicationWork,SUPABASE_URL:'https://synthetic-payment.example'};
 assert.equal(env.AUTH_VERIFIED.claims.iss,env.SUPABASE_URL+'/auth/v1');assert.equal(env.AUTH_ACTOR.userId,member);assert.equal(env.AUTH_ACTOR.sessionId,sid);
 const checks=[],fail=(status,code)=>error=>error.status===status&&error.code===code;
 const done=name=>{checks.push(name);console.log('PASS '+name);};
 // Keep the actual callable postgres pool and its .reserve method intact.
 // Binding every function-valued property through a database Proxy would turn
 // sql into a bare bound function and fail reservation before this interleave.
 async function afterReadContext(target,interleave,check){
  const descriptor=Object.getOwnPropertyDescriptor(target,'readContext'),original=target.readContext.bind(target),originalSql=target.sql;let entered=false;
  Object.defineProperty(target,'readContext',{configurable:true,writable:true,value:async(tx,options)=>{
   await original(tx,options);if(!entered){entered=true;await interleave();}
  }});
  try{return await check();}
  finally{if(descriptor)Object.defineProperty(target,'readContext',descriptor);else delete target.readContext;assert.equal(target.sql,originalSql);}
 }
 const names={session:'get_current_member_contribution_session_v1',lookup:'get_current_member_contribution_command_v1',review:'review_current_member_contribution_intent_v1'};
 const call=(operation,body,current=env)=>contributionCommandRpc(operation,body,current,current.AUTH_ACTOR);
 const immutableCounts=async()=>{
  const [row]=await sql.unsafe('SELECT (SELECT count(*) FROM app.payment_intents)::integer AS intents,(SELECT count(*) FROM app.request_receipts)::integer AS receipts,(SELECT count(*) FROM app.ledger_entries)::integer AS ledger');return row;
 };
 async function http(operation,body,current=env,authenticated=true){
  const work=[];
  const response=await worker.fetch(new Request('https://backend.example/v1/rpc/'+operation,{method:'POST',headers:{'Content-Type':'application/json',...(authenticated?{Authorization:'Bearer '+current.AUTH_VERIFIED.token}:{})},body:JSON.stringify(body)}),current,{waitUntil:promise=>work.push(promise)});
  await Promise.all(work);return {status:response.status,body:await response.json()};
 }
 const [profile]=await sql`select momo_number from app.users where id=${member}`;
 const normalized=normalizeContributionSender(profile?.momo_number);assert.ok(normalized);
 const body={collection:group,p_expected_amount_rwf:710,p_sender_phone_hash:await digest(normalized),p_request_id:crypto.randomUUID()};
 const initial=await financialRpc('create_contribution_intent',body,env,env.AUTH_ACTOR);
 const lookup={p_contract_version:1,p_original_request_id:body.p_request_id,p_original_session_id:sid,p_collection_id:group,p_original_body:body};
 const review={p_contract_version:1,p_intent_id:initial.value.id,p_collection_id:group};
 const receipt=(await sql`select response_json from app.request_receipts where user_id=${member} and request_id=${body.p_request_id}`)[0].response_json;
 const before=await immutableCounts();
 const sessionResult=await http(names.session,{p_contract_version:1});assert.equal(sessionResult.status,200);
 assert.equal(sessionResult.body.owner_id,member);assert.equal(sessionResult.body.auth_subject,authId);assert.equal(sessionResult.body.session_id,sid);assert.equal(sessionResult.body.binding_kind,'current_contribution_session');assert.equal(sessionResult.body.launch_authorized,false);assert.equal(sessionResult.body.retry_authorized,false);
 const observed=await http(names.lookup,lookup);assert.equal(observed.status,200);assert.equal(observed.body.command_status,'receipt_retained');assert.deepEqual(observed.body.observed_intent,{id:initial.value.id,status:'pending'});assert.equal(observed.body.external_payment,'unknown');assert.equal(observed.body.retry_authorized,false);assert.equal(observed.body.launch_authorized,false);
 const current=await http(names.review,review);assert.equal(current.status,200);assert.deepEqual(current.body.intent,initial.value);assert.equal(current.body.reviewed_session_id,sid);assert.equal(current.body.launch_authorized,true);assert.equal(current.body.external_payment,'unknown');
 assert.deepEqual(await immutableCounts(),before);
 done('actual_HTTP_typed_session_lookup_review_and_no_domain_writes');

 const noAuth=await http(names.session,{p_contract_version:1},env,false);assert.equal(noAuth.status,401);
 const extra=await http(names.lookup,{...lookup,extra:true});assert.equal(extra.status,400);assert.equal(extra.body.code,'invalid_contribution_command_query');
 done('actual_HTTP_missing_bearer_and_extra_fields_denied');

 const absentBody={...body,p_request_id:crypto.randomUUID()},absent=await call(names.lookup,{...lookup,p_original_request_id:absentBody.p_request_id,p_original_body:absentBody});
 assert.equal(absent.value.command_status,'unknown');assert.equal(absent.value.observed_intent,null);assert.equal(absent.value.retry_authorized,false);assert.equal(absent.value.launch_authorized,false);assert.equal(absent.value.external_payment,'unknown');
 const changedBody={...body,p_expected_amount_rwf:711};
 assert.equal((await call(names.lookup,{...lookup,p_original_body:changedBody})).value.command_status,'unknown');
 assert.equal((await call(names.lookup,{...lookup,p_original_session_id:crypto.randomUUID()})).value.command_status,'unknown');
 done('actual_SQL_absence_body_and_original_session_mismatch_never_grant_actions');

 // A synthetic corrupt-projection receipt is inserted under the fixture owner;
 // valid JSON/PK/CHECKs remain enforced and immutable existing receipts remain.
 const malformedKey=crypto.randomUUID(),malformedBody={...body,p_request_id:malformedKey};
 await sql`insert into app.request_receipts(user_id,request_id,operation,session_id,body_sha256,response_json,created_at)values(${member},${malformedKey},'create_contribution_intent',${sid},${await digest(stableJson(malformedBody))},${JSON.stringify({id:initial.value.id,status:'pending'})},${new Date().toISOString()})`;
 const malformed=await call(names.lookup,{...lookup,p_original_request_id:malformedKey,p_original_body:malformedBody});assert.equal(malformed.value.command_status,'unknown');assert.equal(malformed.value.observed_intent,null);
 done('actual_SQL_malformed_historical_projection_stays_unknown');

 async function newCurrent({differentOwner=false,surface='member'}={}){
  const managed= differentOwner?crypto.randomUUID():authId,owner=differentOwner?crypto.randomUUID():member,session=crypto.randomUUID(),stamp=Math.floor(Date.now()/1000)-4;
  let user=env.AUTH_VERIFIED.user;
  if(differentOwner){
   const [next]=await sql.unsafe("SELECT lpad(min(candidate)::text,6,'0') AS id FROM(SELECT 0 AS candidate UNION ALL SELECT public_id::integer+1 FROM app.users WHERE public_id<>'999999') c WHERE candidate<1000000 AND NOT EXISTS(SELECT 1 FROM app.users WHERE public_id=lpad(candidate::text,6,'0'))");
   const phone='+250789'+next.id;
   await sql`insert into auth.users(id,phone,phone_confirmed_at)values(${managed},${phone.slice(1)},now())`;
   await sql`insert into app.users(id,phone,public_id,full_name,momo_number,country_code,created_at,updated_at)values(${owner},${phone},${next.id},'Synthetic Other Member',${phone},'RW',${new Date().toISOString()},${new Date().toISOString()})`;
   await sql`insert into private.auth_principal_links(auth_user_id,user_id,proof_reference)values(${managed},${owner},'synthetic-contribution-denial')`;
   await sql`insert into app.memberships(id,collection_id,user_id,role,joined_at)values(${crypto.randomUUID()},${group},${owner},'member',${new Date().toISOString()})`;
   user={id:managed,phone:phone.slice(1),phone_confirmed_at:new Date().toISOString(),app_metadata:{provider:'phone'},user_metadata:{}};
  }
  await sql`insert into auth.sessions(id,user_id,aal,not_after)values(${session},${managed},'aal1',now()+interval '2 hours')`;
  const claims={...env.AUTH_VERIFIED.claims,sub:managed,session_id:session,iat:stamp,exp:stamp+900};
  const targetDb=new PostgresDatabase(sql,claims),target={DB:targetDb,COLLECT_FENCE_WORK:targetDb.applicationWork,SUPABASE_URL:env.SUPABASE_URL,...(surface==='admin'?{ADMIN_AUTH_EXCHANGE:true}:{})};
  await projectSession(target,{claims,token:'synthetic-server-verified-'+session,user},{surface});
  return target;
 }
 const other=await newCurrent({differentOwner:true});
 const foreign=await http(names.lookup,lookup,other);assert.equal(foreign.status,200);assert.equal(foreign.body.command_status,'unknown');assert.equal(foreign.body.observed_intent,null);
 const foreignReview=await http(names.review,review,other);assert.equal(foreignReview.status,404);assert.equal(foreignReview.body.code,'contribution_intent_unavailable');
 done('actual_SQL_other_active_member_cannot_read_or_review_another_owner_intent');

 const replacement=await newCurrent();
 const recovered=await http(names.lookup,lookup,replacement);assert.equal(recovered.status,200);assert.equal(recovered.body.command_status,'receipt_retained');assert.equal(recovered.body.original_session_id,sid);assert.equal(recovered.body.retry_authorized,false);assert.equal(recovered.body.launch_authorized,false);
 const oldLaunch=await http(names.review,review,replacement);assert.equal(oldLaunch.status,404);
 const noRebind=await immutableCounts();await assert.rejects(()=>financialRpc('create_contribution_intent',body,replacement,replacement.AUTH_ACTOR),fail(409,'request_conflict'));assert.deepEqual(await immutableCounts(),noRebind);
 done('actual_SQL_replacement_session_observes_but_cannot_launch_or_rebind_original');

 const unadmittedAdmin=await newCurrent({surface:'admin'});
 await assert.rejects(()=>call(names.session,{p_contract_version:1},unadmittedAdmin),fail(403,'contribution_access_changed'));
 await assert.rejects(()=>call(names.lookup,lookup,unadmittedAdmin),fail(403,'contribution_access_changed'));
 done('actual_SQL_projected_Admin_without_current_cookie_admission_denied');

 await sql`update app.memberships set active=0 where collection_id=${group} and user_id=${member}`;
 await assert.rejects(()=>call(names.review,review),fail(404,'contribution_intent_unavailable'));
 assert.equal((await call(names.lookup,lookup)).value.command_status,'receipt_retained','Own historical receipt remains read-only evidence after membership removal.');
 await sql`update app.memberships set active=1 where collection_id=${group} and user_id=${member}`;
 await sql`update app.collections set status='suspended' where id=${group}`;
 await assert.rejects(()=>call(names.review,review),fail(404,'contribution_intent_unavailable'));
 await sql`update app.collections set status='active' where id=${group}`;
 done('actual_SQL_removed_membership_and_suspended_group_never_allow_launch');

 // Expired/changed-profile cases use separate fixtures, never weaken immutable
 // receipt or managed-session constraints, and do not post any contribution.
 await sql`update app.users set country_code='KE' where id=${member}`;
 await assert.rejects(()=>call(names.review,review),fail(404,'contribution_intent_unavailable'));
 await sql`update app.users set country_code='RW' where id=${member}`;
 await sql`update app.users set momo_number='+250788123499' where id=${member}`;
 await assert.rejects(()=>call(names.review,review),fail(404,'contribution_intent_unavailable'));
 await sql`update app.users set momo_number=${profile.momo_number} where id=${member}`;
 done('actual_SQL_sender_profile_change_denies_review');
 done('actual_SQL_current_profile_geography_required_for_launch_review');

 const route=(number,label)=>[
  db.prepare('UPDATE collections SET receiver_display_label=?,receiver_network=?,receiver_momo_number=?,revision=revision+1,updated_at=? WHERE id=?').bind(label,'mtn_momo',number,new Date().toISOString(),group),
  db.prepare("UPDATE payment_intents SET status='cancelled' WHERE collection_id=? AND status='pending'").bind(group),
 ];
 // Negative control: actual default RR acquired a snapshot during context
 // setup. The writer's committed route is intentionally invisible to it.
 const oldNumber=(await sql`select receiver_momo_number from app.collections where id=${group}`)[0].receiver_momo_number;
 const rr=await sql.reserve();let rrIdle=false;
 try{
  await rr.unsafe('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');await db.readContext(rr);
  await db.batch(route('250788123496','Read-committed receiver'));
  assert.equal((await rr.unsafe('SELECT receiver_momo_number FROM collections WHERE id=$1',[group]))[0].receiver_momo_number,oldNumber);
  await rr.unsafe('COMMIT');rrIdle=true;
 }finally{if(!rrIdle){await rr.unsafe('ROLLBACK');rrIdle=true;}if(rrIdle)rr.release();}
 done('actual_SQL_default_RR_early_snapshot_negative_control');

 const freshBody={...body,p_expected_amount_rwf:712,p_request_id:crypto.randomUUID()},fresh=await financialRpc('create_contribution_intent',freshBody,env,env.AUTH_ACTOR);
 const freshReview={p_contract_version:1,p_intent_id:fresh.value.id,p_collection_id:group};
 let interleaved=false;
 await afterReadContext(db,async()=>{interleaved=true;await db.batch(route('250788123497','Committed after context'));},
  ()=>assert.rejects(()=>call(names.review,freshReview),fail(404,'contribution_intent_unavailable')));
 assert.equal(interleaved,true);assert.equal((await sql`select status from app.payment_intents where id=${fresh.value.id}`)[0].status,'cancelled');
 const cancelled=await call(names.lookup,{p_contract_version:1,p_original_request_id:freshBody.p_request_id,p_original_session_id:sid,p_collection_id:group,p_original_body:freshBody});assert.deepEqual(cancelled.value.observed_intent,{id:fresh.value.id,status:'cancelled'});assert.equal(cancelled.value.launch_authorized,false);
 assert.equal((await sql`select response_json from app.request_receipts where user_id=${member} and request_id=${body.p_request_id}`)[0].response_json,receipt);
 done('actual_SQL_commit_after_context_before_domain_SELECT_is_visible_and_refused');

 const revokeTarget=await newCurrent(),revokeDb=revokeTarget.DB;let revoked=false;
 await afterReadContext(revokeDb,async()=>{revoked=true;await sql`update app.auth_sessions set revoked_at=${Math.floor(Date.now()/1000)},revocation_reason='synthetic-race' where id=${revokeTarget.AUTH_ACTOR.sessionId}`;},
  ()=>assert.rejects(()=>call(names.session,{p_contract_version:1},revokeTarget),fail(403,'contribution_access_changed')));
 assert.equal(revoked,true);
 done('actual_SQL_session_revocation_after_context_before_domain_SELECT_denied');

 const deadlineTarget=await newCurrent(),deadlineDb=deadlineTarget.DB;let expired=false;
 await afterReadContext(deadlineDb,async()=>{expired=true;await sql`update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id=${deadlineTarget.AUTH_ACTOR.sessionId}::uuid`;},
  ()=>assert.rejects(()=>call(names.session,{p_contract_version:1},deadlineTarget),fail(403,'contribution_access_changed')));
 assert.equal(expired,true);
 done('actual_SQL_managed_deadline_change_after_context_before_domain_SELECT_denied');
 return {format:'collect.contribution-commands.actual-pg.v1',checks,check_count:checks.length,http_uses_synthetic_verified_GoTrue:true,provider_calls:0,domain_receipt_creation_unchanged:true,production_acceptance:false};
}
