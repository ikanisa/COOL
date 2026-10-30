import {loadReviewedPlatformFixture} from '../../../../scripts/supabase/testing/curated-platform-fixture.mjs';
import {initializeSqlFixture,finishSqlFixtureWork} from './helpers/fenced-postgres.js';
import {fencedTest} from './helpers/fenced-unit.js';
import {assert,assertEquals} from 'jsr:@std/assert@1.0.14';
import {connection,PostgresDatabase} from './helpers/fenced-postgres.js';
import worker from '../domain/index.js';
import {issueAdminSession} from './helpers/module-domain-admin_accounts.js';
import {fixtureAdminAccount,establishInitialAdminEmail} from './helpers/admin-email-fixture.js';
import {projectSession} from './helpers/module-domain-auth.js';
import {processMomoJob,validateMomoExtraction,MOMO_SCHEMA_VERSION,MOMO_PARSER_VERSION} from './helpers/module-domain-momo_pipeline.js';
import {drainMomoJobs} from '../domain/momo_pipeline.js';
import {digest,stableJson} from '../domain/core.js';
import {encrypt} from './helpers/module-domain-encryption.js';

// Real PostgreSQL, producer and HTTP handlers. GoTrue GET /user and private
// object bytes are synthetic local fixtures; no hosted/provider requests occur.
const database=Deno.env.get('COLLECT_RECEIPT_FACTS_TEST_DATABASE_URL');
const root=new URL('../../../../',import.meta.url),front='https://platform-admin.collect.ikanisa.com';
const project='https://rrlduytparvsjfmegalh.supabase.co',unix=()=>Math.floor(Date.now()/1000);
const factsKeys=['contract_version','kind','transaction_id','capture_id','parse_attempt_id','source_body_sha256',
 'parser_version','profile_version','parsed_at','provider','provider_transaction_id','payer_name','payer_identifier_raw',
 'payer_last3','amount_minor','currency','currency_scale','fee_minor','wallet_balance_after_minor',
 'transaction_datetime_raw','transaction_at','normalization_timezone','transaction_time_source','public_reference',
 'provider_confirmation','settlement_status'].sort();

fencedTest({name:'versioned receipt facts: actual MoMo producer/handlers on isolated PostgreSQL',sanitizeResources:false,sanitizeOps:false,fn:async(t)=>{
 assert(database,'COLLECT_RECEIPT_FACTS_TEST_DATABASE_URL is mandatory; this suite never silently skips');
 const target=new URL(database);assert(['postgres:','postgresql:'].includes(target.protocol)&&target.hostname==='127.0.0.1'&&
  target.pathname==='/collect_receipt_facts_test'&&target.username==='collect_test'&&
  ((target.password==='collect_local_fixture_only'&&(target.port==='55439'||Deno.env.get('COLLECT_CI_SYNTHETIC')==='true'&&target.port==='55441'))||
   (Deno.env.get('COLLECT_CI_SYNTHETIC')==='true'&&target.port==='55443'&&target.password.length>0))&&!target.search&&!target.hash,
  'Only the exclusive synthetic receipt-facts loopback database is allowed');
 const sql=connection(database),originalFetch=globalThis.fetch;
 const reviewedPlatform=await loadReviewedPlatformFixture(new URL('../../../../',import.meta.url));
 const sources=[{path:new URL('../../../tests/sql/00_local_auth_fixture.sql',import.meta.url),text:reviewedPlatform.auth},...reviewedPlatform.rawMigrations.map(m=>({path:new URL('../../../migrations/'+m.name,import.meta.url),text:m.sql}))];
 const setup=await sql.reserve();try{
  await setup.unsafe('DROP SCHEMA IF EXISTS app CASCADE; DROP SCHEMA IF EXISTS private CASCADE; DROP SCHEMA IF EXISTS api CASCADE; DROP SCHEMA IF EXISTS auth CASCADE; DROP SCHEMA IF EXISTS realtime CASCADE');
  await reviewedPlatform.apply(text=>setup.unsafe(text),{includeAuth:true});
  await setup.unsafe('ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS email_confirmed_at timestamptz');
 }finally{setup.release();await initializeSqlFixture(sql);}
 const tokens=new Map<string,any>(),objects=new Map<string,string>();let serial=0,storageReads=0,aiCalls=0,authCalls=0;
 let onStorageRead:(()=>Promise<void>)|null=null;
 const base={SUPABASE_URL:project,SUPABASE_PUBLISHABLE_KEY:'sb_publishable_synthetic_receipt_fixture',
  ADMIN_ORIGIN:front,ALLOWED_ORIGINS:front,AUTH_MEMBER_REGISTRATION_ENABLED:'false',MOMO_PROCESSING_PAUSED:'true',
  SESSION_KEY_ID:'receipt-test-v1',SESSION_ENCRYPTION_KEY:btoa('r'.repeat(32)),DATA_KEY_ID:'receipt-test-v1',DATA_ENCRYPTION_KEY:btoa('r'.repeat(32))};
 const env=()=>({...base,DB:new PostgresDatabase(sql),PRIVATE_MEDIA:{get:async(key:string)=>{storageReads++;if(onStorageRead){const effect=onStorageRead;onStorageRead=null;await effect();}const value=objects.get(key);return value?{size:new TextEncoder().encode(value).length,text:async()=>value}:null;}}});
 globalThis.fetch=async(input:Request|string|URL,init?:RequestInit)=>{
  const request=input instanceof Request?input:new Request(input,init),url=new URL(request.url);
  assertEquals(url.origin,project,'Never contact a real provider');assertEquals(url.pathname,'/auth/v1/user');assertEquals(request.method,'GET');authCalls++;
  const value=tokens.get(request.headers.get('Authorization')?.slice(7)??'');return value?Response.json(value.user):Response.json({error_code:'invalid_token'},{status:401});
 };
 const fixture=async(role:'admin'|'staff'|'member'='member')=>{
  const auth=crypto.randomUUID(),sid=crypto.randomUUID(),pid=crypto.randomUUID(),aid=crypto.randomUUID(),at=unix()-3,
   email='receipt-'+(++serial)+'@example.invalid',stamp=new Date().toISOString();
  await sql`insert into auth.users(id,email,email_confirmed_at)values(${auth},${email},now())`;
  await sql`insert into auth.sessions(id,user_id,aal,not_after)values(${sid},${auth},'aal1',now()+interval '1 hour')`;
  await sql`insert into app.users(id,email,public_id,full_name,member_type,created_at,updated_at)values(${pid},${email},${String(600000+serial)},${'Uploader '+serial},${role==='member'?'app':'operator'},${stamp},${stamp})`;
  await sql`insert into private.auth_principal_links(auth_user_id,user_id,proof_reference)values(${auth},${pid},'synthetic-receipt-facts')`;
  const f:any={auth,sid,pid,aid,email,claims:{sub:auth,session_id:sid,role:'authenticated',aud:'authenticated',aal:'aal1',iat:at,exp:unix()+3600,iss:project+'/auth/v1',amr:[{method:'otp',timestamp:at}]},user:{id:auth,email,email_confirmed_at:stamp,factors:[],app_metadata:{provider:'email'}}};
  const token=()=>{f.token=btoa('{}')+'.'+btoa(JSON.stringify(f.claims))+'.synthetic-not-a-hosted-signature';tokens.set(f.token,f);return f.token;};f.tokenFor=token;token();
  if(role==='member')await projectSession(env(),{user:f.user,claims:f.claims,token:f.token});
  else{
   await sql`insert into app.admin_users(id,email,role,status,password_hash,created_at,updated_at)values(${aid},${email},${role},'active','supabase-managed',${at},${at})`;
   await sql`insert into app.admin_principal_links(admin_user_id,user_id,approved_by,approved_at)values(${aid},${pid},'synthetic-receipt-approval',${stamp})`;
   const response=await issueAdminSession(new Request(front+'/api/admin/auth/verify',{method:'POST',headers:{Origin:front,'Content-Type':'application/json','X-Collect-Requested-With':'collect-admin'},body:'{}'}),env(),{access_token:f.token,refresh_token:'synthetic-refresh-'+sid});
   assertEquals(response.status,200);f.cookie=response.headers.get('Set-Cookie')!.split(';')[0];f.csrf=(await response.json()).csrfToken;
  }
  return f;
 };
 const call=async(f:any,path:string,{reason,origin=front,method='GET',csrf=true}:{reason?:string,origin?:string,method?:string,csrf?:boolean}={})=>
  worker.fetch(new Request(front+'/api/admin/'+path,{method,headers:{Origin:origin,...(f?.cookie?{Cookie:f.cookie}:{}),...(reason?{'X-Collect-Review-Reason':reason}:{}),
   ...(method==='GET'?{}:{'Content-Type':'application/json','X-Collect-Requested-With':'collect-admin',...(csrf?{'X-Collect-CSRF':f?.csrf??''}:{})})},...(method==='GET'?{}:{body:'{}'})}),env(),{waitUntil:()=>{}});
 const json=async(response:Response,status=200)=>{const value=await response.json();assertEquals(response.status,status,JSON.stringify(value));return value;};
 const capture=async(owner:any,body:string,receiverHash='d'.repeat(64))=>{
  const id=crypto.randomUUID(),key='sms/'+id,bodyHash=await digest(body),payload=new TextEncoder().encode(JSON.stringify({raw_sender:'MTN MoMo',raw_body:body,received_at_device:'2026-10-20T19:35:00+02:00',completeness:'complete'})),sha=await digest(payload),
   cipher=await encrypt(base,payload,`sms:${id}:${sha}`),sealedHash=await digest(cipher),scope={ownerId:owner.pid,entityId:id,purpose:'sms_receipt'},metadata={sha256:sha,source_fingerprint:'a'.repeat(64)},op=crypto.randomUUID();
  objects.set(key,cipher);
  await sql.begin(async(tx:any)=>{
   await tx`insert into private.storage_payload_reservations(object_key,source_fingerprint,scope,aad,key_id,plaintext_sha256,sealed_body)values(${key},${'a'.repeat(64)},${scope},${`sms:${id}:${sha}`},'receipt-test-v1',${sha},${cipher})`;
   await tx`insert into private.storage_put_intents(operation_id,object_key,fingerprint,sha256,size,scope,http_metadata,custom_metadata,state)values(${op},${key},${'b'.repeat(64)},${sealedHash},${cipher.length},${scope},${{}},${metadata},'committed')`;
   await tx`insert into private.storage_objects(object_key,operation_id,fingerprint,sha256,size,scope,http_metadata,custom_metadata)values(${key},${op},${'b'.repeat(64)},${sealedHash},${cipher.length},${scope},${{}},${metadata})`;
   await tx`insert into app.sms_receipts(id,owner_user_id,originating_session_id,client_envelope_id,body_sha256,receiver_hash,object_key,object_sha256,size_bytes,received_at_device,created_at)values(${id},${owner.pid},${owner.sid},${crypto.randomUUID()},${bodyHash},${receiverHash},${key},${sha},${payload.length},'2026-10-20T19:35:00+02:00',${new Date().toISOString()})`;
  });
  return {id,key,bodyHash,body};
 };
 const account=async(iso=false,identifier='0788000001')=>{
  const id=crypto.randomUUID(),profile={sender_allowlist:['MTN MoMo'],currency_aliases:['RWF','FRW'],incoming_prefixes:['You have received'],transaction_id_prefixes:['TxId:'],date_format:iso?'ISO':'DMY_HMS',utc_offset_minutes:120};
  await sql`insert into app.momo_receiving_accounts(id,provider,public_code,recipient_name,receiver_hash,currency,timezone,profile_status,profile_version,profile_json,created_at)values(${id},'mtn_momo',${identifier},'Recorded Recipient',${await digest(identifier)},'RWF','Africa/Kigali','approved','synthetic-profile.v1',${JSON.stringify(profile)},${new Date().toISOString()})`;
  return (await sql`select * from app.momo_receiving_accounts where id=${id}`)[0];
 };
 const extracted=async(owner:any,a:any,{reference='REF_'+crypto.randomUUID(),payer='**007',name='Source Payer',time='20/10/2026 11:30:00',fee='0',balance='9000'}:{reference?:string,payer?:string|null,name?:string|null,time?:string|null,fee?:string|null,balance?:string|null}={})=>{
  const payerPart=[name,payer].filter(v=>v!==null).join(' '),body=`You have received RWF 1,000 ${payerPart?'from '+payerPart:''}. TxId: ${reference}${time?' on '+time:''}.${fee===null?'':' Fee: '+fee+'.'}${balance===null?'':' Balance: '+balance+'.'} DO_NOT_DISCLOSE_ORIGINAL_SMS`;
  const output={schema_version:MOMO_SCHEMA_VERSION,event_kind:'incoming_receipt',payment_outcome:'successful',transaction_id_raw:reference,original_transaction_id_raw:null,transaction_datetime_raw:time,
   principal_amount_raw:'1,000',currency_raw:'RWF',payer_name_raw:name,payer_identifier_raw:payer,payment_reference_raw:null,fee_amount_raw:fee,wallet_balance_after_raw:balance,
   evidence:{incoming_success:'You have received RWF 1,000',principal:'1,000',transaction_id:reference,transaction_datetime:time,payer:payerPart||null,fee:fee===null?null:'Fee: '+fee,wallet_balance_after:balance===null?null:'Balance: '+balance},issues:[]};
  const validation=validateMomoExtraction(output,{raw_sender:'MTN MoMo',raw_body:body,completeness:'complete'},a);assert(validation.accepted,JSON.stringify(validation));
  const raw=await capture(owner,body,a.receiver_hash),stamp=new Date().toISOString();
  await sql`insert into app.momo_processing_jobs(raw_sms_id,receiving_account_id,mode,state,available_at,created_at,updated_at)values(${raw.id},${a.id},'historical','pending',${unix()},${stamp},${stamp})`;
  const result=await processMomoJob({...env(),AI:{run:async()=>{aiCalls++;return {response:output};}}},raw.id);assert(['accepted','duplicate','conflict'].includes(result.relation),JSON.stringify(result));
  return {...raw,output,result,tx:(await sql`select * from app.momo_transactions where id=${result.transaction_id}`)[0]};
 };
 const financialState=async()=>stableJson(await sql`select (select count(*) from app.payments)::int as payments,(select count(*) from app.payment_evidence)::int as evidence,(select count(*) from app.ledger_entries)::int as ledger,(select count(*) from app.momo_financial_links)::int as links`);
 const receiptState=async()=>{
  const result=[];for(const table of ['sms_receipts','momo_transactions','momo_transaction_sources','momo_parse_attempts','momo_processing_jobs','momo_receiving_accounts','request_receipts','audit_log'])
   result.push([table,await sql.unsafe(`select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]'::jsonb) as rows from app.${table} t`)]);
  return stableJson(result);
 };
 let admin:any,staff:any,member:any,full:any,masked:any,missing:any,iso:any,a:any;
 try{
  admin=await fixture('admin');staff=await fixture('staff');member=await fixture();a=await account();
  await t.step('ordinary capture remains metadata only without registration or financial effects',async()=>{
   const before=await financialState(),raw=await capture(member,'SYNTHETIC unclassified member capture DO_NOT_DISCLOSE_ORIGINAL_SMS');
   const page=await json(await call(admin,'sms/receipts')),row=page.rows.find((r:any)=>r.id===raw.id);assert(row);
   assertEquals(row.source_kind,'capture');assertEquals(row.transaction_id,null);assertEquals(row.extraction_status,'not_extracted');assertEquals(row.payer_name,null);assertEquals(row.momo_transaction_reference,null);assertEquals(row.amount_rwf,null);assertEquals(Object.hasOwn(row,'receipt_facts'),false);
   assertEquals((await sql`select count(*)::int as n from app.momo_gateway_bindings where owner_user_id=${member.pid}`)[0].n,0);assertEquals(await financialState(),before);
  });
  await t.step('actual extraction/list/detail preserve full/masked identifiers and leading zeros with original provenance',async()=>{
   const before=await financialState();full=await extracted(member,a,{payer:'+250788000007'});masked=await extracted(member,a,{payer:'**007'});
   const storageBefore=storageReads,aiBefore=aiCalls,rowsBefore=await receiptState(),page=await json(await call(admin,'momo/transactions?limit=25&offset=0'));
   assertEquals(page.total,2);assertEquals(page.totals,{received_minor:2000,credited_minor:0,unallocated_minor:2000});
   for(const input of [full,masked]){
    const row=page.rows.find((r:any)=>r.id===input.tx.id),facts=row.receipt_facts;assert(row);assertEquals(Object.keys(facts).sort(),factsKeys);
    assertEquals(facts.contract_version,1);assertEquals(facts.kind,'validated_momo_extraction');assertEquals(facts.transaction_id,input.tx.id);assertEquals(facts.capture_id,input.id);assertEquals(facts.parse_attempt_id,input.tx.parse_attempt_id);assertEquals(facts.source_body_sha256,input.bodyHash);
    assertEquals(facts.parser_version,MOMO_PARSER_VERSION);assertEquals(facts.profile_version,'synthetic-profile.v1');assertEquals(facts.payer_identifier_raw,input.output.payer_identifier_raw);assertEquals(facts.payer_last3,'007');assertEquals(facts.payer_name,'Source Payer');assertEquals(facts.fee_minor,0);assertEquals(facts.wallet_balance_after_minor,9000);
    assertEquals(facts.public_reference,null);assertEquals(facts.provider_confirmation,false);assertEquals(facts.settlement_status,'not_asserted');assertEquals(facts.amount_minor,1000);assertEquals(facts.currency,'RWF');assertEquals(facts.currency_scale,0);
    assertEquals(row.receiving_context,{account_id:a.id,identifier_raw:'0788000001',identifier_kind:'number',recipient_name:'Recorded Recipient',basis:'recorded_receiving_account'});
    assertEquals(Object.keys(row).some(k=>k.startsWith('rf_')),false);assertEquals(JSON.stringify(row).includes('DO_NOT_DISCLOSE_ORIGINAL_SMS'),false);
    const detail=await json(await call(admin,'momo/transactions/'+input.tx.id));assertEquals(detail.transaction.receipt_facts,facts);assertEquals(detail.transaction.receiving_context,row.receiving_context);assertEquals(JSON.stringify(detail).includes('DO_NOT_DISCLOSE_ORIGINAL_SMS'),false);
   }
   assertEquals(storageReads,storageBefore,'Ordinary list/detail cannot read original objects');assertEquals(aiCalls,aiBefore,'GET never invokes extraction');assertEquals(await financialState(),before);assertEquals(await receiptState(),rowsBefore,'List/detail must not mutate receipts, facts, jobs, requests or audit rows');
  });
  await t.step('raw time, normalized instant and receiving profile timezone are distinct, absent facts stay null',async()=>{
   missing=await extracted(member,a,{payer:null,name:null,time:null,fee:null,balance:null});
   let detail=await json(await call(admin,'momo/transactions/'+missing.tx.id)),f=detail.transaction.receipt_facts;
   for(const key of ['payer_name','payer_identifier_raw','payer_last3','transaction_datetime_raw','transaction_at','fee_minor','wallet_balance_after_minor'])assertEquals(f[key],null,key);
   assertEquals(f.transaction_time_source,'missing_provider_time');assert(f.transaction_at!==detail.transaction.created_at);assertEquals(f.normalization_timezone,'Africa/Kigali');
   detail=await json(await call(admin,'momo/transactions/'+full.tx.id));f=detail.transaction.receipt_facts;
   assertEquals(f.transaction_datetime_raw,'20/10/2026 11:30:00');assertEquals(f.transaction_at,'2026-10-20T09:30:00.000Z');assertEquals(f.transaction_time_source,'sms_body_and_provider_profile');assertEquals(Object.hasOwn(f,'momo_timezone_offset'),false);
   const codeAccount=await account(true,'123456');iso=await extracted(member,codeAccount,{time:'2026-10-20T11:30:00+02:00'});detail=await json(await call(admin,'momo/transactions/'+iso.tx.id));f=detail.transaction.receipt_facts;
   assertEquals(f.transaction_datetime_raw,'2026-10-20T11:30:00+02:00');assertEquals(f.transaction_at,'2026-10-20T09:30:00.000Z');assertEquals(f.transaction_time_source,'sms_body_explicit_offset_and_provider_profile');assertEquals(detail.transaction.receiving_context.identifier_kind,'code');assertEquals(detail.transaction.receiving_context.identifier_raw,'123456');
  });
  await t.step('duplicate/conflicting source attempts never replace original accepted facts or IDs',async()=>{
   const before=await financialState(),duplicate=await extracted(member,a,{reference:full.tx.provider_transaction_id,payer:'+250788000007'}),conflict=await extracted(member,a,{reference:full.tx.provider_transaction_id,payer:'**999',name:'Conflicting Payer'});
   assertEquals(duplicate.result.relation,'duplicate');assertEquals(conflict.result.relation,'conflict');assertEquals(duplicate.tx.id,full.tx.id);assertEquals(conflict.tx.id,full.tx.id);
   const detail=await json(await call(admin,'momo/transactions/'+full.tx.id)),facts=detail.transaction.receipt_facts;
   assertEquals(facts.capture_id,full.id);assertEquals(facts.parse_attempt_id,full.tx.parse_attempt_id);assertEquals(facts.payer_identifier_raw,'+250788000007');assertEquals(facts.payer_last3,'007');assertEquals(facts.source_body_sha256,full.bodyHash);assertEquals(detail.transaction.has_conflict,1);assertEquals(detail.transaction.status,'needs_review');assertEquals(detail.sources.length,3);assertEquals(await financialState(),before);
   for(let i=0;i<2;i++){const page=await json(await call(admin,'momo/transactions'));assertEquals(page.total,4);assertEquals(page.totals.received_minor,4000);assertEquals(await financialState(),before);}
  });
  await t.step('current permissions/origin and independent email/reason/audit guards remain active',async()=>{
   let response=await call(null,'momo/transactions');assertEquals(response.status,401);
   response=await call(admin,'momo/transactions',{origin:'https://foreign.example'});assertEquals(response.status,403);
   await json(await call(staff,'momo/transactions'));
   const before=storageReads;response=await call(staff,'momo/sources/'+full.id+'/content',{reason:'Synthetic original evidence review'});assertEquals(response.status,403);assertEquals(storageReads,before);
   response=await call(admin,'momo/sources/'+full.id+'/content',{reason:'Synthetic original evidence review'});assertEquals(response.status,403);assertEquals(storageReads,before,'An AAL label without an independent email proof cannot reveal originals');
   const originalCookie=admin.cookie,bff=(await sql`select token_hash,public_id,origin from app.admin_sessions where auth_session_id=${admin.sid}`)[0],emailDb=new PostgresDatabase(sql,admin.claims);
   const emailAccount=await fixtureAdminAccount(sql,emailDb,[admin.aid,bff.token_hash,bff.origin,bff.public_id]);await establishInitialAdminEmail(sql,emailDb,emailAccount);
   const projected=(await sql`select assurance_level,mfa_at,mfa_factor_id from app.auth_sessions where id=${admin.sid}`)[0];assertEquals(projected.assurance_level,1);assertEquals(projected.mfa_at,null);assertEquals(projected.mfa_factor_id,null);assertEquals(admin.cookie,originalCookie);
   response=await call(admin,'momo/sources/'+full.id+'/content');assertEquals(response.status,400);assertEquals(storageReads,before,'Fresh email proof still requires a reason');
   const auditBefore=(await sql`select count(*)::int as n from app.audit_log where action='momo.source.revealed'`)[0].n;
   const reveal=await json(await call(admin,'momo/sources/'+full.id+'/content',{reason:'Synthetic original evidence review'}));assertEquals(reveal.raw_body,full.body);assertEquals(reveal.raw_sms_id,full.id);
   assertEquals((await sql`select count(*)::int as n from app.audit_log where action='momo.source.revealed'`)[0].n,auditBefore+1);
   onStorageRead=async()=>{await sql`delete from app.admin_grants where user_id=${admin.pid} and permission='sms.read'`;};
   const raced=await json(await call(admin,'momo/sources/'+full.id+'/content',{reason:'Synthetic raced read permission revocation'}),403);
   assertEquals(JSON.stringify(raced).includes('DO_NOT_DISCLOSE_ORIGINAL_SMS'),false,'Revocation during Storage read must never return plaintext');
   assertEquals((await sql`select count(*)::int as n from app.audit_log where action='momo.source.revealed'`)[0].n,auditBefore+1);
   await sql`delete from app.admin_grants where user_id=${staff.pid} and permission='payments.read'`;
   response=await call(staff,'momo/transactions');assertEquals(response.status,403,'Current permission revocation blocks the same cookie');
  });
  await t.step('broken accepted relation/digest/attempt provenance fails closed for detail and counted list',async()=>{
   const before=await financialState();
   for(const variant of ['missing_relation','duplicate_relation','wrong_digest','nonaccepted_attempt','wrong_source','unverified_profile','contradictory_time','suffix_only_identifier']){
    const txId=crypto.randomUUID(),attempt=crypto.randomUUID(),raw=await capture(member,'SYNTHETIC provenance fixture '+variant),badAccount=await account(false,String(700000+(++serial))),stamp=new Date().toISOString();
    await sql`insert into app.momo_parse_attempts(id,raw_sms_id,attempt_number,model_id,schema_version,prompt_version,parser_version,profile_version,profile_json,source_body_sha256,output_json,validation_json,outcome,created_at)values(${attempt},${raw.id},1,'synthetic',${MOMO_SCHEMA_VERSION},'synthetic',${MOMO_PARSER_VERSION},${variant==='unverified_profile'?'unverified':'synthetic-profile.v1'},${badAccount.profile_json},${variant==='wrong_digest'?'f'.repeat(64):raw.bodyHash},'{}','[]',${variant==='nonaccepted_attempt'?'duplicate':'accepted'},${stamp})`;
    const record={...missing.tx,id:txId,receiving_account_id:badAccount.id,parse_attempt_id:attempt,provider_transaction_id:'BAD_'+txId,...(variant==='contradictory_time'?{transaction_at:stamp}:{}),...(variant==='suffix_only_identifier'?{payer_identifier:'007',payer_last3:'007'}:{})};
    await sql`insert into app.momo_transactions ${sql(record)}`;
    if(variant!=='missing_relation')await sql`insert into app.momo_transaction_sources(transaction_id,raw_sms_id,parse_attempt_id,relation,created_at)values(${txId},${variant==='wrong_source'?full.id:raw.id},${attempt},${variant==='duplicate_relation'?'duplicate':'accepted'},${stamp})`;
    const detail=await json(await call(admin,'momo/transactions/'+txId),503);assertEquals(detail.error.code,'invalid_source_data',variant);assertEquals(Object.hasOwn(detail,'transaction'),false);
    const page=await json(await call(admin,'momo/transactions?receiving_account_id='+badAccount.id),503);assertEquals(page.error.code,'invalid_source_data',variant);
   }
   assertEquals(await financialState(),before);
  });
  await t.step('periodic one-job drain recovers due backlog and expired leases without new ingest, preserving retry and financial boundaries',async()=>{
   const before=await financialState(),stamp=new Date().toISOString(),at=unix();let calls=0,failNext=false;
   const queued=async(state:string,attempts:number,available:number,lease:number|null=null)=>{
    const reference='SCHEDULED_'+crypto.randomUUID(),raw=await capture(member,`You have received RWF 100 successfully. TxId: ${reference}.`,a.receiver_hash);
    await sql`insert into app.momo_processing_jobs(raw_sms_id,receiving_account_id,mode,state,attempt_count,available_at,lease_token,lease_until,created_at,updated_at)
     values(${raw.id},${state==='source_unresolved'?null:a.id},'historical',${state},${attempts},${available},${lease===null?null:crypto.randomUUID()},${lease},${stamp},${stamp})`;
    return raw.id;
   };
   const pending=await queued('pending',0,at-10),retry=await queued('retry',1,at-9),expired=await queued('processing',1,at-8,at-1),
    future=await queued('pending',0,at+300),held=await queued('processing',1,at-7,at+300),exhausted=await queued('pending',4,at-6),unresolved=await queued('source_unresolved',0,at-5);
   const processing={...env(),MOMO_PROCESSING_PAUSED:'false',MOMO_AI_MODEL:'synthetic-reviewed-model',AI:{run:async(_model:unknown,options:any)=>{
    calls++;if(failNext){failNext=false;throw Error('synthetic temporary extraction refusal');}
    const source=JSON.parse(options.messages.at(-1).content),reference=/TxId: ([^\s.]+)/.exec(source.sms)![1];
    return {response:{schema_version:MOMO_SCHEMA_VERSION,event_kind:'incoming_receipt',payment_outcome:'successful',transaction_id_raw:reference,
     original_transaction_id_raw:null,transaction_datetime_raw:null,principal_amount_raw:'100',currency_raw:'RWF',payer_name_raw:null,payer_identifier_raw:null,
     payment_reference_raw:null,fee_amount_raw:null,wallet_balance_after_raw:null,evidence:{incoming_success:'You have received RWF 100',principal:'100',transaction_id:reference,
      transaction_datetime:null,payer:null,fee:null,wallet_balance_after:null},issues:[]}};
   }}};
   const state=async(id:string)=>(await sql`select state,attempt_count,available_at,lease_token,last_error from app.momo_processing_jobs where raw_sms_id=${id}`)[0];
   let result=await drainMomoJobs(processing,{limit:1});assertEquals(result.processed,1);assertEquals(result.results[0].state,'completed');assertEquals((await state(pending)).state,'completed');
   failNext=true;result=await drainMomoJobs(processing,{limit:1});assertEquals(result.results[0].state,'retry');
   const waiting=await state(retry);assertEquals(Number(waiting.attempt_count),2);assert(Number(waiting.available_at)>at);assertEquals(waiting.lease_token,null);
   result=await drainMomoJobs(processing,{limit:1});assertEquals(result.results[0].state,'completed');assertEquals(Number((await state(expired)).attempt_count),2);
   assertEquals(calls,3);assertEquals((await state(future)).state,'pending');assertEquals((await state(held)).state,'processing');assertEquals((await state(unresolved)).state,'source_unresolved');
   assertEquals((await state(exhausted)).state,'needs_review');assertEquals((await state(exhausted)).last_error,'retry_budget_exhausted');
   result=await drainMomoJobs(processing,{limit:1});assertEquals(result,{processed:0,results:[]});assertEquals(calls,3);
   // Move only the synthetic retry clock. No new source/ingest causes recovery.
   await sql`update app.momo_processing_jobs set available_at=${at-1} where raw_sms_id=${retry}`;
   result=await drainMomoJobs(processing,{limit:1});assertEquals(result.results[0].state,'completed');assertEquals(Number((await state(retry)).attempt_count),3);assertEquals(calls,4);
   assertEquals(await processMomoJob(processing,pending),{state:'not_claimed'});assertEquals(calls,4,'A completed receipt cannot be parsed twice by an old worker');
   assertEquals(await drainMomoJobs({...processing,MOMO_PROCESSING_PAUSED:'true'},{limit:1}),{processed:0,results:[],paused:true});assertEquals(calls,4);
   assertEquals(await financialState(),before,'Extraction and recovery create evidence facts only; no contributions or journal entries');
  });
  assert(authCalls>0);await reviewedPlatform.parity();for(const source of sources)assertEquals(await Deno.readTextFile(source.path),source.text,'Migration inputs changed during isolated qualification');
 }finally{globalThis.fetch=originalFetch;await finishSqlFixtureWork();await sql.end();}
}});
