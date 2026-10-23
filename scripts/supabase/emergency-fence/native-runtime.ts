import {loadReviewedPlatformFixture,EXACT_CURRENT11,MIGRATION_ELEVEN_ROLE,ROOT_SQL11_SHA256} from '../testing/curated-platform-fixture.mjs';
import postgres from 'npm:postgres@3.4.7';
import {dirname,join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';

// Maintained local-only witness. Root supplies a fresh fixture00 + exact current SQL11
// database already initialized once with this synthetic source, never hosted.
const SOURCE='a'.repeat(64),BASELINE='dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3';
const PINS:Record<string,string>={
  "supabase/functions/_shared/application-fence.js": "7abbf94ff699f6942619b6a0409a5623a6fa7322b41cdabe72e32d99689184de",
  "supabase/functions/_shared/postgres.js": "ac92b5bc010596f324d06cf3474119626133d2c3adb3e1627261c0deaa1c1e9d",
  "supabase/functions/_shared/workspace-smtp-email.js": "05833369873f15ef71805a351f9868787d97e74a6df7a5a21a303b8feef24eef",
  "supabase/functions/_shared/domain/email_delivery.js": "55e7f5cdfac654b50f02d120737ee82563da2d154294ebf95252b7e8cd534e36",
  "supabase/functions/_shared/domain/core.js": "18ce95c133a4895d13475338089fb00c9ba4c9283ee72c7d4d6f88ae8ea8723e",
  "supabase/migrations/20261020134444_collect_curated_platform_baseline.sql": "0d943d17ddd92e809856831427cfc81b1264301dabdb867e1c90322d46b5a6f0",
  "supabase/migrations/20261020135932_collect_runtime_role_and_function_paths.sql": "59e4b13ddc81abeb39fb59b005c71a29f947023502727c118c9eb00b479e08a1",
  "supabase/migrations/20261020174856_collect_retention_retry_authority.sql": "d3ba38736fa46b70a0bb66520deffa56fd6f7317deb7c0144f8e06d791f8808c",
  "supabase/migrations/20261020184012_collect_admin_invitation_attempts.sql": "c6dc8aa6ac5130162c6e69904aae7221edde6dcb0c898af2cf9e10dba444b665",
  "supabase/migrations/20261020190301_collect_rls_helper_permissions.sql": "dccb79af17182164dc6afe0b8339b70bd35a80fc4a1c1fa7df1a09408310a645",
  "supabase/migrations/20261020191847_collect_privacy_email_reauthentication.sql": "d6f002a6e904226a88e666c70937a142f06aa5a7e29874c6edb564d59c5fcab4",
  "supabase/migrations/20261020193752_collect_admin_invitation_access_notice_v2.sql": "b48a381169e777160a37396539248325e40b331a61db986622514724517f8467",
  "supabase/migrations/20261020195249_collect_admin_invitation_public_id_preservation.sql": "78f8c454a9825b0d9e25622b0659245d9568e7b95f637d3e20160a945b4e0850",
  "supabase/migrations/20261022195747_collect_application_mutation_fence.sql": "714abf2d24ce3d42a36525d18627362b02ff38c30810e988d365b5796d840497",
  "supabase/tests/sql/00_local_auth_fixture.sql": "b935e17f44219f018cf1a864505d1895d71903885ca6c61c039d7ab6596117ea",
  "supabase/functions/deno.json": "2c3962bd2c4fac761d154c43b0b48a55622142e02a2be70237361c02032f43e4",
  "supabase/functions/deno.lock": "070d1f79d59faebba520e3d14c1b10f4d73a84584eafa8c34f767c013c628b9b"
};
const MIGRATIONS=EXACT_CURRENT11;
const ENV='COLLECT_FENCE_RUNTIME_TEST_DATABASE_URL';
const USER='11111111-1111-4111-8111-111111111111',REQUEST='22222222-2222-4222-8222-222222222222',SESSION='33333333-3333-4333-8333-333333333333';
const QUIESCE='44444444-4444-4444-8444-444444444444';
let stage='preflight',checks=0,sql:any,control:any,owner:any,work:any;
let syntheticSends=0,transportCloses=0,networkFetches=0;
const fail=(code:string):never=>{const error=new Error('Local runtime witness unconfirmed');(error as any).witnessCode=code;throw error;};
const need=(condition:unknown,code:string)=>{checks++;if(!condition)fail(code);};
const deferred=<T>()=>{let resolve!:(value:T)=>void;const promise=new Promise<T>(yes=>{resolve=yes;});return{promise,resolve};};
const sha=async(value:string|Uint8Array)=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',typeof value==='string'?new TextEncoder().encode(value):new Uint8Array(value))),n=>n.toString(16).padStart(2,'0')).join('');
async function observe<T>(promise:Promise<T>,ms:number,code:string):Promise<T>{let timer:ReturnType<typeof setTimeout>|undefined;try{return await Promise.race([promise,new Promise<T>((_,reject)=>{timer=setTimeout(()=>{const error=new Error('Local observation unavailable');(error as any).witnessCode=code;reject(error);},ms);})]);}finally{clearTimeout(timer);}}
const pause=(ms:number)=>new Promise<void>(yes=>setTimeout(yes,ms));
const watchdog=setTimeout(()=>{console.error(JSON.stringify({status:'UNCONFIRMED',code:'WITNESS_BUDGET_EXCEEDED',stage,checks,preserve_database:true,provider_calls:0,sb29Satisfied:false}));Deno.exit(1);},150000);

async function status(){const rows=await owner.unsafe('SELECT private.collect_fence_owner_status() AS result');need(rows.length===1,'OWNER_STATUS_SHAPE');return rows[0].result;}
function statusScope(row:any){need(row?.contractVersion===1&&row.projectRef==='rrlduytparvsjfmegalh'&&row.epoch===1&&row.sourceSha256===SOURCE,'OWNER_SOURCE_BINDING');for(const key of ['wholeSystemAcceptance','providerSettlement','managedInternalWritesFenced','humanMessagesFenced','atomicRecoverySnapshot','sb29Satisfied'])need(row[key]===false,'OWNER_SCOPE_FLAGS');need(row.schedulerStatus?.checked===true&&row.schedulerStatus?.coverageVerified===true&&row.schedulerStatus?.blocking===false,'SCHEDULER_COVERAGE_REQUIRED');}
async function appSnapshot(){
 const names=(await owner.unsafe("SELECT c.relname::text AS name FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='app' AND c.relkind='r' ORDER BY c.relname COLLATE \"C\"" )).map((row:any)=>row.name);
 need(names.length===97&&names.every((name:string)=>/^[a-z_]+$/.test(name)),'EXACT_APP_TABLES_REQUIRED');
 const result:Record<string,{count:number,sha256:string}>={};let total=0;
 for(const name of names){
  const excluded=name==='users'?' WHERE t.id<>$1':name==='request_receipts'?' WHERE NOT(t.user_id=$1 AND t.request_id=$2)':'';
  const values=name==='users'?[USER]:name==='request_receipts'?[USER,REQUEST]:[];
  const rows=await owner.unsafe('SELECT pg_catalog.to_jsonb(t) AS row FROM app."'+name+'" t'+excluded+' ORDER BY pg_catalog.to_jsonb(t)::text COLLATE "C" LIMIT 1001',values);
  total+=rows.length;const encoded=JSON.stringify(rows.map((row:any)=>row.row));need(rows.length<=1000&&total<=20000&&encoded.length<=8000000,'BOUNDED_SYNTHETIC_INVENTORY_REQUIRED');result[name]={count:rows.length,sha256:await sha(encoded)};
 }
 return result;
}
async function journal(){const rows=await owner.unsafe('SELECT pg_catalog.to_jsonb(r) AS row FROM app.request_receipts r WHERE user_id=$1 AND request_id=$2',[USER,REQUEST]);need(rows.length===1,'EXACT_ORIGINAL_RECEIPT_REQUIRED');return JSON.stringify(rows[0].row);}
async function userRow(){const rows=await owner.unsafe('SELECT pg_catalog.to_jsonb(u) AS row FROM app.users u WHERE id=$1',[USER]);need(rows.length===1,'EXACT_SYNTHETIC_USER_REQUIRED');return JSON.stringify(rows[0].row);}
async function heldWorkCount(){const rows=await owner.unsafe("SELECT count(*)::int AS count FROM pg_catalog.pg_locks WHERE database=(SELECT oid FROM pg_catalog.pg_database WHERE datname=current_database()) AND locktype='advisory' AND classid=7346371 AND objid=1 AND objsubid=2 AND mode='ShareLock' AND granted");return rows[0].count;}

try{
 need(Deno.args.length===0,'NO_ARGUMENTS_ALLOWED');const raw=Deno.env.get(ENV);Deno.env.delete(ENV);let target:URL;try{target=new URL(raw??'');}catch{fail('LOCAL_RUNTIME_URL_REQUIRED');}
 need(['postgres:','postgresql:'].includes(target!.protocol)&&['127.0.0.1','[::1]'].includes(target!.hostname)&&/^\d{1,5}$/.test(target!.port)&&Number(target!.port)>0&&Number(target!.port)<=65535&&/^\/collect_fence_runtime_[a-f0-9]{8,32}_test$/.test(target!.pathname)&&!!target!.username&&!!target!.password&&!target!.search&&!target!.hash,'LOCAL_RUNTIME_URL_REQUIRED');
 // Driver environment knobs must not enable debug, alternate session targets
 // or other ambient behavior. No values are read, printed or persisted.
 for(const key of ['PGHOST','PGPORT','PGUSERNAME','PGUSER','PGDATABASE','PGPASSWORD','PGMAX','PGSSL','PGIDLE_TIMEOUT','PGCONNECT_TIMEOUT','PGMAX_LIFETIME','PGMAX_PIPELINE','PGBACKOFF','PGKEEP_ALIVE','PGPREPARE','PGDEBUG','PGFETCH_TYPES','PGPUBLICATIONS','PGTARGET_SESSION_ATTRS','PGAPPNAME','PGTARGETSESSIONATTRS'])Deno.env.delete(key);
 const caller=await Deno.realPath(fileURLToPath(import.meta.url)),root=await Deno.realPath(resolve(dirname(caller),'../../..'));
 need(caller===join(root,'scripts/supabase/emergency-fence/native-runtime.ts'),'FIXED_PHYSICAL_SOURCE_REQUIRED');
 const entries=[];for await(const entry of Deno.readDir(join(root,'supabase/migrations')))if(/^\d{14}_.*\.sql$/.test(entry.name))entries.push(entry.name);
 need(MIGRATIONS.length===11&&JSON.stringify(entries.sort())===JSON.stringify(MIGRATIONS),'EXACT_CURRENT11_MIGRATIONS_REQUIRED');
 const reviewedPlatform=await loadReviewedPlatformFixture(root);
 async function parity(){await reviewedPlatform.parity();for(const [role,pin]of Object.entries(PINS)){const path=join(root,role);need(await Deno.realPath(path)===path&&await sha(await Deno.readFile(path))===pin,'QUALIFIED_SOURCE_CHANGED');}}
 await parity();const closureSha256=await sha(JSON.stringify({original17:PINS,sql10:reviewedPlatform.binding,sql11:{role:MIGRATION_ELEVEN_ROLE,sha256:ROOT_SQL11_SHA256}}));
 const runtime=join(root,'supabase/functions/_shared/');
 const {connection,fenceConnection,PostgresDatabase}=await import(pathToFileURL(join(runtime,'postgres.js')).href);
 const {sqlFenceBackend,openApplicationWork}=await import(pathToFileURL(join(runtime,'application-fence.js')).href);
 const {createWorkspaceSmtpEmail}=await import(pathToFileURL(join(runtime,'workspace-smtp-email.js')).href);
 const {sendTransactionalEmail}=await import(pathToFileURL(join(runtime,'domain/email_delivery.js')).href);
 // No actual provider/Auth/Storage HTTP is a permitted dependency here.
 globalThis.fetch=(()=>{networkFetches++;throw Error('EXTERNAL_FETCH_FORBIDDEN');}) as typeof fetch;
 owner=postgres(target!.href,{max:1,prepare:false,ssl:false,connect_timeout:5,idle_timeout:5,onnotice:()=>{},connection:{application_name:'collect-fence-runtime-witness',statement_timeout:15000,lock_timeout:5000}});
 stage='actual_database_identity';const identity=(await owner.unsafe("SELECT current_database()::text AS database,pg_catalog.host(pg_catalog.inet_server_addr()) AS address,pg_catalog.inet_server_port() AS port,current_setting('server_version_num') AS version,current_setting('default_transaction_isolation') AS isolation")).at(0);
 need(identity?.database===target!.pathname.slice(1)&&['127.0.0.1','::1'].includes(identity?.address)&&identity?.port===Number(target!.port)&&/^17\d{4}$/.test(identity?.version)&&identity?.isolation==='read committed','FRESH_LOCAL_PG17_REQUIRED');
 const role=(await owner.unsafe("SELECT rolcanlogin,rolsuper,rolinherit,rolcreaterole,rolcreatedb,rolbypassrls,rolreplication FROM pg_catalog.pg_roles WHERE rolname='postgres'")).at(0);
 need(role&&Object.values(role).every(value=>value===false),'EXACT_RESTRICTED_POSTGRES_FIXTURE_REQUIRED');
 const initial=await status();statusScope(initial);need(initial.mode==='open'&&initial.activeAdmissions===0&&initial.unresolvedAdmissions===0&&initial.retainedUnknownObligations===0,'PRISTINE_OPEN_CONTROL_REQUIRED');
 const pristine=(await owner.unsafe("SELECT (SELECT count(*)::int FROM private.collect_fence_admissions) AS admissions,(SELECT count(*)::int FROM private.collect_fence_operations) AS operations,(SELECT count(*)::int FROM private.collect_fence_scheduler_lifecycle) AS proofs,(SELECT baseline_manifest_sha256 FROM private.collect_fence_control WHERE singleton) AS baseline,(SELECT count(*)::int FROM app.users WHERE id=$1 OR public_id='999997') AS users,(SELECT count(*)::int FROM app.request_receipts WHERE user_id=$1 OR request_id=$2) AS receipts",[USER,REQUEST])).at(0);
 need(pristine?.admissions===0&&pristine?.operations===1&&pristine?.proofs===0&&pristine?.baseline===BASELINE&&pristine?.users===0&&pristine?.receipts===0,'NEW_UNTOUCHED_WITNESS_DATABASE_REQUIRED');
 const outsideBefore=await appSnapshot(),createdAt=new Date().toISOString();
 stage='synthetic_user_setup';await owner.unsafe("INSERT INTO app.users(id,public_id,full_name,created_at,updated_at) VALUES($1,'999997','Synthetic runtime witness',$2,$2)",[USER,createdAt]);const originalUser=await userRow();
 stage='actual_runtime_admission';sql=connection(target!.href);control=fenceConnection(target!.href);const backend=sqlFenceBackend(sql,control);work=await openApplicationWork({backend,sourceSha256:SOURCE,kind:'http_collect'});
 need((await backend.status(work.id)).state==='active','ACTUAL_DURABLE_ADMISSION_REQUIRED');need(await heldWorkCount()===1,'ACTUAL_SHARED_WORK_REQUIRED');
 const rawSend=deferred<any>(),started=deferred<void>();let rawSettled=false;void rawSend.promise.then(()=>{rawSettled=true;});
 const env:any={COLLECT_FENCE_WORK:work,COLLECT_NOTICE_SMTP_PASSWORD:'synthetic-only-no-provider-secret',AUTH_EMAIL_FROM:'info@ikanisa.com'};
 env.AUTH_EMAIL=createWorkspaceSmtpEmail(env,{createTransport:()=>({sendMail(){syntheticSends++;started.resolve();return rawSend.promise;},close(){transportCloses++;}})});
 stage='actual_smtp_consumer_timeout';const beforeTimeout=performance.now();const observed=sendTransactionalEmail(env,{to:'synthetic@example.invalid',subject:'Collect synthetic local witness',text:'Synthetic local effect, no network transport.'});
 // Attach rejection custody immediately, before waiting for dispatch to start.
 const observation:Promise<{unexpectedSuccess:boolean,code?:string}>=observed.then(()=>({unexpectedSuccess:true}),(error:any)=>({unexpectedSuccess:false,code:error?.code}));await observe(started.promise,15000,'SYNTHETIC_DISPATCH_NOT_STARTED');const outcome=await observe(observation,15000,'CONSUMER_TIMEOUT_NOT_OBSERVED');const elapsed=performance.now()-beforeTimeout;
 need(!outcome.unexpectedSuccess&&'code'in outcome&&outcome.code==='email_unavailable','ACTUAL_EMAIL_UNKNOWN_REQUIRED');need(elapsed>=9500&&elapsed<20000,'ACTUAL_TEN_SECOND_TIMEOUT_REQUIRED');need(syntheticSends===1&&!rawSettled&&transportCloses===0&&networkFetches===0,'ORIGINAL_RAW_SEND_STILL_PENDING');
 stage='original_unknown_receipt';const bodySha256=await sha(JSON.stringify({to:'synthetic@example.invalid',operation:'fence.synthetic.email',request_id:REQUEST}));const response=JSON.stringify({ok:false,code:'email_unavailable',outcome:'unknown',request_id:REQUEST,attempted_dispatches:1,replay_allowed:false});
 const db=new PostgresDatabase(sql,{sub:USER,role:'authenticated'},work);await db.query('INSERT INTO request_receipts(user_id,request_id,operation,session_id,body_sha256,response_json,created_at) VALUES(?,?,?,?,?,?,?)',[USER,REQUEST,'fence.synthetic.email',SESSION,bodySha256,response,new Date().toISOString()]);
 const originalJournal=await journal();need(JSON.parse(originalJournal).response_json===response,'ORIGINAL_UNKNOWN_RESPONSE_EXACT');
 stage='committed_quiesce';const quiescing=(await owner.unsafe('SELECT private.collect_fence_begin_quiesce($1::uuid,$2::bigint,$3::text) AS result',[QUIESCE,1,SOURCE])).at(0)?.result;statusScope(quiescing);need(quiescing.mode==='quiescing'&&quiescing.activeAdmissions===1,'COMMITTED_QUIESCING_REQUIRED');
 let admissionDenied=false;try{await openApplicationWork({backend,sourceSha256:SOURCE,kind:'jobs'});}catch(error){admissionDenied=(error as any)?.code==='application_fenced';}need(admissionDenied,'NEW_WORK_MUST_BE_DENIED');need((await owner.unsafe('SELECT count(*)::int AS count FROM private.collect_fence_admissions')).at(0)?.count===1,'DENIED_REGISTER_MUST_NOT_CREATE_ROW');
 let finished=false;const completion:Promise<any>=work.finish().then((value:any)=>{finished=true;return value;});await pause(50);need(!finished&&!rawSettled,'FINISH_MUST_RETAIN_RAW_WORK');need((await backend.status(work.id)).state==='active'&&await heldWorkCount()===1,'ACTIVE_WORK_AND_REAL_LOCK_RETAINED');
 stage='drain_known_lock_timeout';let lockTimeout=false;try{await owner.begin('ISOLATION LEVEL READ COMMITTED',async(tx:any)=>{await tx.unsafe("SET LOCAL lock_timeout='150ms'");await tx.unsafe('SELECT private.collect_fence_drain($1::uuid,$2::bigint,$3::text) AS result',[QUIESCE,1,SOURCE]);});}catch(error){lockTimeout=(error as any)?.code==='55P03';}
 need(lockTimeout,'REAL_EXCLUSIVE_WORK_DRAIN_MUST_TIME_OUT');const held=await status();statusScope(held);need(held.mode==='quiescing'&&held.activeAdmissions===1&&!held.applicationFenceComplete,'NO_FALSE_DRAIN_WHILE_RAW_PENDING');need(await journal()===originalJournal&&syntheticSends===1&&!rawSettled&&transportCloses===0,'UNKNOWN_RECEIPT_UNCHANGED_WHILE_PENDING');
 stage='original_raw_settlement';rawSend.resolve({messageId:'<synthetic@ikanisa.com>',accepted:['synthetic@example.invalid'],rejected:[],rejectedErrors:[],response:'250 2.0.0 accepted',envelope:{from:'info@ikanisa.com',to:['synthetic@example.invalid']}});const result:any=await observe(completion,15000,'RUNTIME_FINISH_UNCONFIRMED');
 need(result.state==='settled'&&result.reason==='completed_with_unknown_obligation'&&result.externalDispatches===1&&result.uncertainDispatches===1&&result.applicationWorkFinished===true&&result.providerSettlement===false&&result.wholeSystemAcceptance===false,'EXACT_SETTLED_UNKNOWN_RESULT_REQUIRED');
 need(rawSettled&&syntheticSends===1&&transportCloses===1&&networkFetches===0,'ONE_ORIGINAL_SEND_NO_REPLAY');const closed=await backend.status(work.id);need(closed.found===true&&closed.state==='settled'&&closed.reason==='completed_with_unknown_obligation'&&closed.externalDispatches===1&&closed.uncertainDispatches===1,'DURABLE_CLOSE_EXACT');need(await heldWorkCount()===0,'WORK_RELEASE_ONLY_AFTER_RAW_SETTLEMENT');
 stage='final_control_drain';const final=(await owner.unsafe('SELECT private.collect_fence_drain($1::uuid,$2::bigint,$3::text) AS result',[QUIESCE,1,SOURCE])).at(0)?.result;statusScope(final);need(final.mode==='fenced'&&final.activeAdmissions===0&&final.unresolvedAdmissions===0&&final.retainedUnknownObligations===1&&final.applicationFenceComplete===true,'EXACT_LOCAL_FENCED_UNKNOWN_REQUIRED');
 need(await journal()===originalJournal&&await userRow()===originalUser,'OWNED_ROWS_MUST_REMAIN_EXACT');const outsideAfter=await appSnapshot();need(JSON.stringify(outsideAfter)===JSON.stringify(outsideBefore),'UNRELATED_APPLICATION_ROWS_CHANGED');
 const finalFacts=(await owner.unsafe("SELECT (SELECT count(*)::int FROM private.collect_fence_admissions) AS admissions,(SELECT count(*)::int FROM private.collect_fence_operations) AS operations,(SELECT count(*)::int FROM private.collect_fence_scheduler_lifecycle) AS proofs,(SELECT count(*)::int FROM app.request_receipts WHERE user_id=$1 AND request_id=$2) AS receipts",[USER,REQUEST])).at(0);need(finalFacts?.admissions===1&&finalFacts?.operations===3&&finalFacts?.proofs===0&&finalFacts?.receipts===1,'NO_DUPLICATE_LIFECYCLE_OR_RECEIPT');
 await parity();stage='complete';console.log(JSON.stringify({status:'PASS',fixture:'new_unique_loopback_actual_runtime_sql11',migration_count:11,sql11_sha256:ROOT_SQL11_SHA256,checks,source_sha256:SOURCE,source_closure_sha256:closureSha256,sql10_sha256:reviewedPlatform.binding.hosted_sql_sha256,synthetic_sql10_sha256:reviewedPlatform.binding.synthetic_sql_sha256,sql9_sha256:PINS['supabase/migrations/20261022195747_collect_application_mutation_fence.sql'],actual_smtp_timeout:true,synthetic_raw_send_calls:syntheticSends,provider_calls:0,external_fetch_calls:networkFetches,app_tables_unchanged_outside_exact_owned_rows:97,original_unknown_receipt_sha256:await sha(originalJournal),original_unknown_receipt_preserved:true,durable_settled_unknown:1,retained_unknown_obligations:1,held_work_prevented_drain:true,final_mode:'fenced',applicationFenceComplete:true,preserve_database:true,automatic_replay:false,hosted_capacity_accepted:false,providerSettlement:false,wholeSystemAcceptance:false,managedInternalWritesFenced:false,humanMessagesFenced:false,atomicRecoverySnapshot:false,sb29Satisfied:false}));
}catch(error){const own=(error as any)?.witnessCode;console.error(JSON.stringify({status:'UNCONFIRMED',code:typeof own==='string'&&/^[A-Z_0-9]{1,80}$/.test(own)?own:'RUNTIME_WITNESS_UNCONFIRMED',stage,checks,preserve_database:true,automatic_retry:false,provider_calls:0,hosted_capacity_accepted:false,providerSettlement:false,wholeSystemAcceptance:false,sb29Satisfied:false}));Deno.exitCode=1;
}finally{
 // Connection termination is local fixture cleanup only. On failure we do not
 // invent a close, resolve synthetic work, alter journals, release control or
 // erase history. Any unfinished durable admission remains for owner review.
 await Promise.allSettled([sql?.end({timeout:1}),control?.end({timeout:1}),owner?.end({timeout:1})]);clearTimeout(watchdog);
}
