// Isolated native PostgreSQL qualification; never a managed Auth or production
// acceptance receipt. Caller provisions a fresh original16 synthetic database.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash,randomUUID} from 'node:crypto';
import postgres from 'npm:postgres@3.4.7';
import {connection,fenceConnection,PostgresDatabase} from '../../../supabase/functions/_shared/postgres.js';
import {openApplicationWork,sqlFenceBackend,applicationWorkTuple} from '../../../supabase/functions/_shared/application-fence.js';
import {memberHistoryPage} from '../../../supabase/functions/_shared/domain/member_history.js';
import {financialRpc} from '../../../supabase/functions/_shared/domain/payments.js';
import {HISTORY_ADDITIONS,startSelfHostedHistoryCapture,finishSelfHostedHistoryCapture} from './self-hosted-member-history.mjs';
import {installCurrentFixtureAdditions} from './self-hosted-current-schema.mjs';

const passed:string[]=[],observed:Record<string,unknown>={};let stage='invocation',failure:any=null;
let capture:any=null,captureFixture:any=null;
const capturedPages:any[]=[],capturedRequests:any[]=[],capturedStatements:any[]=[],runtimeIdentities:any[]=[],capturedBalances:any[]=[];
const pools:any[]=[];const originalFetch=globalThis.fetch;let externalCalls=0;
async function step(name:string,run:()=>Promise<void>){stage=name;await run();passed.push(name);}
try{
 assert.equal(Deno.env.get('COLLECT_CI_SYNTHETIC'),'true');assert.equal(Deno.args.length,0);
 const descriptorPath=Deno.env.get('COLLECT_SELFHOST_BACKEND_FIXTURE_DESCRIPTOR');
 const descriptor=descriptorPath?JSON.parse(await readFile(descriptorPath,'utf8')):null;
 if(descriptor)assert(descriptor.format==='collect.selfhost.fixture.v1'&&descriptor.purpose==='backend'&&
  descriptor.migration_count===16&&descriptor.synthetic===true&&descriptor.public_acceptance===false&&descriptor.controller_initialized===true);
 const raw=descriptor?.url??Deno.env.get('COLLECT_SELFHOST_BACKEND_DATABASE_URL');Deno.env.delete('COLLECT_SELFHOST_BACKEND_DATABASE_URL');
 assert(raw);const target=new URL(raw);assert(['postgres:','postgresql:'].includes(target.protocol));
 assert.equal(target.hostname,'127.0.0.1');assert(target.port);assert.equal(target.username,'postgres');
 assert.match(target.pathname,/^\/collect_[a-z0-9_]+_test$/);assert.equal(target.search,'');assert.equal(target.hash,'');
 const captureOutput=Deno.env.get('COLLECT_SELFHOST_HISTORY_OUTPUT_DIR');
 if(captureOutput){assert(descriptor,'A private fresh original16 fixture descriptor is required for receipt capture');capture=await startSelfHostedHistoryCapture(captureOutput);}
 globalThis.fetch=()=>{externalCalls++;throw Error('External requests forbidden in native backend qualification');};
 const owner=postgres(raw,{max:1,prepare:false,ssl:false,onnotice:()=>{},connection:{statement_timeout:120000,lock_timeout:5000}});
 const business=connection(raw),control=fenceConnection(raw);pools.push(owner,business,control);
 const identity=(await owner`SELECT current_user AS owner,session_user AS session,current_database() AS database,
  current_setting('server_version_num') AS version,(SELECT rolsuper FROM pg_roles WHERE rolname=current_user) AS superuser`)[0];
 assert.equal(identity.owner,'postgres');assert.equal(identity.session,'postgres');assert.equal(identity.superuser,false);
 assert.equal(Math.floor(Number(identity.version)/10000),17);assert.equal(identity.database,target.pathname.slice(1));
 const state=(await owner`SELECT private.collect_fence_owner_status_v3() AS value`)[0].value;
 assert.equal(state.mode,'open');assert.equal(state.rawActiveAdmissions,0);const source=state.sourceSha256,epoch=state.epoch;
 if(descriptor)assert.equal(descriptor.source_sha256,source);
 captureFixture={database:identity.database,postgres_major:17,controller_source_sha256:source,normal_owner:'postgres',owner_superuser:false};
 const runWork=async(claims:any,fn:(env:any)=>Promise<any>,requestId:number|null=null)=>{
  const work=await (openApplicationWork as any)({backend:sqlFenceBackend(business,control),sourceSha256:source,kind:'http_collect'});
  const db=new (PostgresDatabase as any)(business,claims,work);
  if(capture&&requestId!==null){
   let serial=0;const statement=db.statement.bind(db);
   db.statement=async(tx:any,value:any)=>{
    const receipt:any={request_id:requestId,sequence:serial++,sql:value.sql,parameters:value.values};
    try{const result=await statement(tx,value);receipt.actual_result=result;capturedStatements.push(receipt);return result;}
    catch(error:any){receipt.failure={code:error.code??null,message:error.message};capturedStatements.push(receipt);throw error;}
   };
  }
  try{
   if(capture&&requestId!==null){
    const native=await db.prepare("SELECT current_user AS current_role,session_user AS session_role,current_setting('collect.edge_verified') AS edge_verified").first();
    assert.equal(native.current_role,'collect_runtime');assert.equal(native.session_role,'postgres');assert.equal(native.edge_verified,'true');
    runtimeIdentities.push({request_id:requestId,...native});
   }
   return await fn({DB:db,COLLECT_FENCE_WORK:work,BUILD_SOURCE_ID:source});
  }finally{await work.finish();}
 };
 const safeOld=randomUUID(),unknownOld=randomUUID(),lostOld=randomUUID();
 let originalUnknown:any,originalLost:any;
 await step('upgrade preserves original safe/unknown/lost admissions',async()=>{
  assert.equal((await owner`SELECT to_regclass('private.collect_fence_admission_archive') AS object`)[0].object,null);
  await owner`INSERT INTO private.collect_fence_admissions(admission_id,epoch,source_sha256,kind,state,reason,external_dispatches,uncertain_dispatches,closed_at)
   VALUES(${safeOld},${epoch},${source},'http_collect','settled','completed',0,0,now()),
    (${unknownOld},${epoch},${source},'http_collect','settled','completed_with_unknown_obligation',1,1,now()),
    (${lostOld},${epoch},${source},'http_collect','unresolved','work_lost',0,0,now())`;
  originalUnknown=(await owner`SELECT to_jsonb(a) AS value FROM private.collect_fence_admissions a WHERE admission_id=${unknownOld}`)[0].value;
  originalLost=(await owner`SELECT to_jsonb(a) AS value FROM private.collect_fence_admissions a WHERE admission_id=${lostOld}`)[0].value;
  const installation=await installCurrentFixtureAdditions(owner);
  const pins=installation.migrations.slice(16);
  observed.migrations=pins;
  observed.current_schema=installation;
  captureFixture.additive_migrations=pins;
  const archived=(await owner`SELECT private.collect_fence_archive_settled_v4(1) AS value`)[0].value;
  assert.equal(archived.archived,1);assert.equal(archived.originalRowsDeleted,false);
  assert.equal((await owner`SELECT private.collect_fence_archive_settled_v4(1) AS value`)[0].value.archived,0);
  assert.deepEqual((await owner`SELECT to_jsonb(a) AS value FROM private.collect_fence_admissions a WHERE admission_id=${unknownOld}`)[0].value,originalUnknown);
  assert.deepEqual((await owner`SELECT to_jsonb(a) AS value FROM private.collect_fence_admissions a WHERE admission_id=${lostOld}`)[0].value,originalLost);
  assert.equal(Number((await owner`SELECT count(*) AS n FROM private.collect_fence_working_admissions`)[0].n),2);
 });
 await step('archive/index/counters reject client access and unsafe owner shortcuts',async()=>{
  for(const role of ['anon','authenticated','service_role','collect_runtime','collect_importer']){
   for(const name of ['collect_fence_working_admissions','collect_fence_admission_archive','collect_fence_admission_totals'])
    assert.equal((await owner`SELECT has_table_privilege(${role},${'private.'+name},'SELECT,INSERT,UPDATE,DELETE,TRUNCATE') AS allowed`)[0].allowed,false);
   assert.equal((await owner`SELECT has_function_privilege(${role},'private.collect_fence_archive_settled_v4(integer)','EXECUTE') AS allowed`)[0].allowed,false);
  }
  await assert.rejects(owner`DELETE FROM private.collect_fence_working_admissions WHERE admission_id=${unknownOld}`,/collect_archive_receipt_required/);
  await assert.rejects(owner`DELETE FROM private.collect_fence_admission_archive WHERE admission_id=${safeOld}`,/collect_fence_history_immutable/);
  await assert.rejects(owner`UPDATE private.collect_fence_admission_totals SET archived_total=archived_total+1 WHERE singleton`,/collect_archive_counter_conflict/);
  await assert.rejects(owner`INSERT INTO private.collect_fence_admission_archive(admission_id,snapshot_sha256) SELECT admission_id,encode(sha256(convert_to(to_jsonb(a)::text,'UTF8')),'hex') FROM private.collect_fence_admissions a WHERE admission_id=${unknownOld}`,/collect_archive_unsettled/);
  await assert.rejects(owner`SELECT private.collect_fence_archive_settled_v4(5001)`,/collect_archive_invalid_limit/);
 });
 await step('real runtime close archives atomically and retains exact original evidence',async()=>{
  let id:string|undefined;
  await runWork({},async env=>{id=applicationWorkTuple(env.COLLECT_FENCE_WORK)[0];await env.DB.prepare('SELECT 1 AS value').first();});
  const record=(await owner`SELECT a.state,a.uncertain_dispatches,h.snapshot_sha256=encode(sha256(convert_to(to_jsonb(a)::text,'UTF8')),'hex') AS valid,
   EXISTS(SELECT 1 FROM private.collect_fence_working_admissions w WHERE w.admission_id=a.admission_id) AS working
   FROM private.collect_fence_admissions a JOIN private.collect_fence_admission_archive h USING(admission_id) WHERE admission_id=${id!}`)[0];
  assert.equal(record.state,'settled');assert.equal(Number(record.uncertain_dispatches),0);assert.equal(record.valid,true);assert.equal(record.working,false);
 });
 const at=Math.floor(Date.now()/1000),stamp='2026-10-30T00:00:00.000Z';
 const member={id:randomUUID(),auth:randomUUID(),sid:randomUUID()},other={id:randomUUID(),auth:randomUUID(),sid:randomUUID()};
 const group=randomUUID(),foreign=randomUUID();
 const claims={sub:member.auth,session_id:member.sid,role:'authenticated',aal:'aal1',iat:at,exp:at+3600,amr:[{method:'otp',timestamp:at}]};
 const actor={userId:member.id,sessionId:member.sid};
 const call=async(operation:string,body:any,fn:(env:any)=>Promise<any>)=>{
  const id=capturedRequests.length;
  const request:any={id,case:stage,operation,body:structuredClone(body)};
  if(capture)capturedRequests.push({request,response:null});
  try{
   const value=await runWork(claims,fn,capture?id:null);
   if(capture)capturedRequests[id].response={status:200,body:structuredClone(value)};
   return value;
  }catch(error:any){if(capture)capturedRequests[id].response={status:error.status??500,body:{code:error.code??'unexpected_error',message:error.message}};throw error;}
 };
 const history=async(body:any={})=>{
  const request={p_contract_version:2,...body},requestId=capturedRequests.length;
  const result=await call('list_current_member_history_page',request,env=>memberHistoryPage(request,env,actor));
  if(capture)capturedPages.push({request_id:requestId,contract_version:2,
   query:{collection_id:body.p_collection_id??null,search:(body.p_query??'').trim(),sort:body.p_sort??'newest',from:body.p_from??null,before:body.p_before??null},
   requested_cursor:body.p_cursor??null,limit:body.p_limit??50,response:result});
  return result;
 };
 await step('seed more than ten thousand synthetic financial events with native constraints',async()=>{
  for(const [i,p] of [member,other].entries()){
   await owner`INSERT INTO auth.users(id,email)VALUES(${p.auth},${'backend-'+p.id+'@example.invalid'})`;
   await owner`INSERT INTO auth.sessions(id,user_id,aal,not_after)VALUES(${p.sid},${p.auth},'aal1',now()+interval '1 hour')`;
   await owner`INSERT INTO app.users(id,email,public_id,created_at,updated_at)VALUES(${p.id},${'backend-'+p.id+'@example.invalid'},${String(800000+i)},${stamp},${stamp})`;
   await owner`INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference)VALUES(${p.auth},${p.id},'synthetic-backend-qualification')`;
   await owner`INSERT INTO app.auth_sessions(id,user_id,surface,auth_at,created_at,expires_at)VALUES(${p.sid},${p.id},'member',${at},${at},${at+3600})`;
  }
  for(const [id,user] of [[group,member.id],[foreign,other.id]]){
   await owner`INSERT INTO app.collections(id,slug,creator_user_id,title,collection_type,receiver_momo_number,receiver_network,created_at,updated_at)VALUES(${id},${id},${user},'Native 10% history','ikimina','250788123491','mtn_momo',${stamp},${stamp})`;
   await owner`INSERT INTO app.memberships(id,collection_id,user_id,role,joined_at)VALUES(${randomUUID()},${id},${user},'owner',${stamp})`;
  }
  await owner`INSERT INTO app.memberships(id,collection_id,user_id,role,joined_at)VALUES(${randomUUID()},${group},${other.id},'member',${stamp})`;
  await owner`CREATE TEMP TABLE backend_history_seed AS SELECT n,gen_random_uuid()::text AS evidence,gen_random_uuid()::text AS payment,gen_random_uuid()::text AS entry,
   CASE WHEN n%2=0 THEN ${member.id} ELSE ${other.id} END AS member_id,(n%9+1)::bigint AS amount,
   to_char(('2026-10-30T00:00:00Z'::timestamptz+n*interval '1 second') AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS stamp FROM generate_series(1,10005)n`;
  // Same declared synthetic journal facts as SQL02's seed_storage helper,
  // inserted in bounded statements. Real readiness triggers remain enabled;
  // these fixtures are not actual provider uploads or encryption acceptance.
  // Stay below the real per-owner pending-spool budget; evidence commit
  // clears each completed batch through the shipping lifecycle trigger.
  for(let offset=0;offset<10005;offset+=200){
  await owner`INSERT INTO private.storage_payload_reservations(object_key,source_fingerprint,scope,aad,key_id,plaintext_sha256,sealed_body)
   SELECT 'synthetic-history/'||evidence,repeat('d',64),jsonb_build_object('ownerId',member_id,'entityId',evidence,'purpose','payment_evidence'),
    'synthetic-only','fixture',repeat('a',64),'synthetic-encrypted-envelope' FROM backend_history_seed WHERE n>${offset} AND n<=${offset+200}`;
  await owner`INSERT INTO private.storage_put_intents(operation_id,object_key,fingerprint,sha256,size,scope,http_metadata,custom_metadata,state)
   SELECT 'fixture:synthetic-history/'||evidence,'synthetic-history/'||evidence,repeat('e',64),repeat('f',64),30,
    jsonb_build_object('ownerId',member_id,'entityId',evidence,'purpose','payment_evidence'),'{}',
    jsonb_build_object('sha256',repeat('a',64),'source_fingerprint',repeat('d',64)),'committed' FROM backend_history_seed WHERE n>${offset} AND n<=${offset+200}`;
  await owner`INSERT INTO private.storage_objects(object_key,operation_id,fingerprint,sha256,size,scope,http_metadata,custom_metadata)
   SELECT 'synthetic-history/'||evidence,'fixture:synthetic-history/'||evidence,repeat('e',64),repeat('f',64),30,
    jsonb_build_object('ownerId',member_id,'entityId',evidence,'purpose','payment_evidence'),'{}',
    jsonb_build_object('sha256',repeat('a',64),'source_fingerprint',repeat('d',64)) FROM backend_history_seed WHERE n>${offset} AND n<=${offset+200}`;
  await owner`INSERT INTO app.payment_evidence(id,collection_id,owner_user_id,object_key,object_sha256,size_bytes,content_type,authenticity,external_reference,receiver_momo_number,receiver_network,amount_minor,observed_at,created_at)
   SELECT evidence,${group},member_id,'synthetic-history/'||evidence,repeat('a',64),12,'text/plain','operator_recorded','native-history-'||n,'250788123491','mtn_momo',amount,stamp,stamp FROM backend_history_seed WHERE n>${offset} AND n<=${offset+200}`;
  }
  await owner`INSERT INTO app.payments(id,collection_id,member_id,evidence_id,amount_minor,status,payer_display_name,created_at)
   SELECT payment,${group},member_id,evidence,amount,'reconciled','PRIVATE_RECEIPT_NAME',stamp FROM backend_history_seed`;
  await owner`INSERT INTO app.ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind,evidence_id,actor_user_id,request_id,posted_at)
   SELECT entry,payment,${group},member_id,amount,'contribution',evidence,${member.id},gen_random_uuid()::text,stamp FROM backend_history_seed`;
  await owner`ANALYZE app.ledger_entries`;
  observed.history_rows=10005;
 });
 let first:any;
 await step('large history pages keep exact totals and bounded payload with all four sort orders',async()=>{
  const sums=(await owner`SELECT sum(amount)::text AS total,sum(amount) FILTER(WHERE member_id=${member.id})::text AS own FROM backend_history_seed`)[0];
  first=await history({p_limit:50});assert.equal(first.total_count,10005);assert.equal(first.items.length,50);
  assert.equal(first.totals.RWF,Number(sums.total));assert.equal(first.own_totals.RWF,Number(sums.own));
  assert(!JSON.stringify(first).includes('PRIVATE_RECEIPT_NAME'));assert(JSON.stringify(first).length<50000);
  for(const sort of ['newest','oldest','highest','lowest']){
   const one=await history({p_sort:sort,p_limit:50}),two=await history({p_sort:sort,p_limit:50,p_cursor:one.next_cursor});
   assert.equal(two.revision,one.revision);assert.equal(two.total_count,10005);
   const entries=[...one.items,...two.items];assert.equal(new Set(entries.map((x:any)=>x.entry_id)).size,100);
   const expected=[...entries].sort((a,b)=>{
    if(['highest','lowest'].includes(sort)&&a.amount_minor!==b.amount_minor)return sort==='highest'?b.amount_minor-a.amount_minor:a.amount_minor-b.amount_minor;
    return (sort==='oldest'?a.posted_at.localeCompare(b.posted_at):b.posted_at.localeCompare(a.posted_at))||a.entry_id.localeCompare(b.entry_id);
   });assert.deepEqual(entries,expected);
  }
 });
 await step('half-open dates, literal search and cross-group authority remain scoped',async()=>{
  const page=await history({p_from:'2026-10-30T00:01:00.000Z',p_before:'2026-10-30T00:02:00.000Z',p_limit:50});
  assert.equal(page.total_count,60);assert(page.items.every((r:any)=>r.posted_at>='2026-10-30T00:01:00.000Z'&&r.posted_at<'2026-10-30T00:02:00.000Z'));
  // Capture one complete, bounded date range in addition to the large first
  // windows so the real Dart consumer can check end-of-chain aggregates.
  const end=await history({p_from:'2026-10-30T00:01:00.000Z',p_before:'2026-10-30T00:02:00.000Z',p_limit:50,p_cursor:page.next_cursor});
  assert.equal(end.items.length,10);assert.equal(end.next_cursor,null);assert.equal(end.revision,page.revision);
  assert.equal((await history({p_query:'10%'})).total_count,10005);assert.equal((await history({p_query:'_'})).total_count,0);
  assert.equal((await history({p_query:'native-history-1'})).total_count,1);
  assert.equal((await history({p_collection_id:foreign})).total_count,0);
  for(const invalid of [{p_from:'2026-02-31T00:00:00.000Z'},{p_from:'2026-10-30'},{p_from:stamp,p_before:stamp}])
   await assert.rejects(()=>history(invalid),(e:any)=>e.code==='invalid_history_range');
  await assert.rejects(()=>history({p_cursor:first.next_cursor,p_from:stamp}),(e:any)=>e.code==='history_changed');
 });
 await step('group mutation invalidates old cursors and balances share one exact aggregate',async()=>{
  await owner`UPDATE app.collections SET title='Changed native history',revision=revision+1 WHERE id=${group}`;
  await assert.rejects(()=>history({p_cursor:first.next_cursor}),(e:any)=>e.code==='history_changed');
  const balances=await call('list_current_member_collection_balances',{},async env=>(await financialRpc('list_current_member_collection_balances',{},env,actor)).value);
  assert.equal(balances.length,1);assert.equal(balances[0].balances[0].amount_raised_minor,first.totals.RWF);
  assert.equal(balances[0].balances[0].current_user_balance_minor,first.own_totals.RWF);assert.equal(balances[0].supporter_count,2);
  if(capture)capturedBalances.push(...balances);
 });
 await step('normal service admits beyond the former hundred-thousand lifetime cap',async()=>{
  // Short committed batches avoid making one synthetic command retain a
  // hundred-thousand-version counter chain. Production closes are short too.
  for(let offset=0;offset<100001;offset+=1000)await owner`INSERT INTO private.collect_fence_admissions(admission_id,epoch,source_sha256,kind,state,reason,external_dispatches,uncertain_dispatches,closed_at)
   SELECT gen_random_uuid(),${epoch},${source},'http_collect','settled','completed',0,0,now() FROM generate_series(1,${Math.min(1000,100001-offset)})`;
  await runWork({},async env=>assert.equal((await env.DB.prepare('SELECT 1 AS value').first()).value,1));
  const archive=(await owner`SELECT private.collect_fence_archive_status_v4(true) AS value`)[0].value;
  assert.equal(archive.fullHistoryVerified,true);assert(archive.resourceLimits.retainedAdmissions>100000);
  assert.equal(archive.resourceLimits.workingAdmissions,2);assert.equal(archive.resourceLimits.activeAndUnresolvedAdmissions,1);
  assert.equal(archive.resourceLimits.capacityBlocked,false);observed.archive=archive;
 });
 await step('eight retained stopped proofs release effective slots without rewriting unknown history',async()=>{
  const lost=[lostOld,...Array.from({length:7},()=>randomUUID())],operation=randomUUID();
  for(const id of lost.slice(1))await owner`INSERT INTO private.collect_fence_admissions(admission_id,epoch,source_sha256,kind,state,reason,closed_at)
   VALUES(${id},${epoch},${source},'http_collect','unresolved','work_lost',now())`;
  const blocked=(await owner`SELECT private.collect_fence_archive_status_v4() AS value`)[0].value;
  assert.equal(blocked.resourceLimits.activeAndUnresolvedAdmissions,8);assert.equal(blocked.resourceLimits.capacityBlocked,true);
  await owner`SELECT private.collect_fence_begin_quiesce(${operation}::uuid,${epoch}::bigint,${source})`;
  // Explicit synthetic owner evidence: the test does not claim actual process
  // loss or real provider settlement. The production SQL still verifies the
  // named role/OID are absent before admitting each stopped-work proof.
  const role='collect_cf_preserve_91234567',oid=4294967000;
  assert.equal(Number((await owner`SELECT count(*) AS n FROM pg_roles WHERE rolname=${role} OR oid=${oid}::oid`)[0].n),0);
  for(const id of lost)await owner`SELECT private.collect_fence_record_stopped_admission_v3(
   ${randomUUID()}::uuid,${operation}::uuid,${state.projectRef},${id}::uuid,${epoch}::bigint,${source},'http_collect',
   ${'a'.repeat(64)},${oid}::oid,${role},${'b'.repeat(64)},true,${randomUUID()}::uuid,${'c'.repeat(64)})`;
  const drained=(await owner`SELECT private.collect_fence_drain_v3(${operation}::uuid,${epoch}::bigint,${source}) AS value`)[0].value;
  assert.equal(drained.mode,'fenced');
  const released=(await owner`SELECT private.collect_fence_release_v3(${randomUUID()}::uuid,${epoch}::bigint,${source}) AS value`)[0].value;
  assert.equal(released.mode,'open');assert.equal(released.resourceLimits.activeAndUnresolvedAdmissions,0);
  assert.equal(released.resourceLimits.rawActiveAndUnresolvedAdmissions,8);assert.equal(released.resourceLimits.stoppedLocalAdmissions,8);
  assert.equal(released.unknownObligationSettled,false);assert.equal(released.resourceLimits.capacityBlocked,false);
  assert.deepEqual((await owner`SELECT to_jsonb(a) AS value FROM private.collect_fence_admissions a WHERE admission_id=${lostOld}`)[0].value,originalLost);
  await runWork({},async env=>assert.equal((await env.DB.prepare('SELECT 1 AS value').first()).value,1));
  observed.stopped={raw:8,effective:0,original_unknown_preserved:true,provider_settlement:false};
 });
 await step('revoked actual fixture session cannot use a retained history cursor',async()=>{
  await owner`UPDATE app.auth_sessions SET revoked_at=${at+1},revocation_reason='synthetic-native-test' WHERE id=${member.sid}`;
  await assert.rejects(()=>history({p_cursor:first.next_cursor}),(e:any)=>e.code==='session_changed');
 });
 assert.equal(externalCalls,0);
}catch(error:any){failure={stage,code:String(error?.code??error?.name??'failure'),message:'Native backend qualification did not complete',
 diagnostic:String(error?.message??'').replace(/postgres(?:ql)?:\/\/\S+/g,'[database URL redacted]').slice(0,240)};}
finally{globalThis.fetch=originalFetch;for(const pool of pools)try{await pool.end({timeout:5});}catch{failure??={stage:'pool_shutdown',code:'unconfirmed',message:'Pool shutdown unconfirmed'};}}
if(capture&&!failure){
 try{observed.history_capture=await finishSelfHostedHistoryCapture(capture,{fixture:captureFixture,pages:capturedPages,balances:capturedBalances,
  requests:capturedRequests,statements:capturedStatements,runtimeIdentities,cases:passed});}
 catch(error:any){failure={stage:'source_bound_history_capture',code:error?.message??'capture_unconfirmed',message:'History receipt source or packet validation failed'};}
}
console.log(JSON.stringify({format:'collect.selfhost.backend.native.v2',status:failure?'FAIL':'PASS',cases:passed,observed,failure,
 real_postgres:true,synthetic_auth:true,external_calls:externalCalls,production_acceptance:false}));
if(failure)Deno.exit(1);
