// Local current14 SQL/domain producer. This never starts or resets PostgreSQL.
// The stopped-admission native profile owns schema/owner setup and final shutdown.
import assert from 'node:assert/strict';
import {readFile,readdir,realpath,mkdir,open,unlink,lstat} from 'node:fs/promises';
import {Buffer} from 'node:buffer';
import {resolve,join,dirname,isAbsolute} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {createHash,randomUUID} from 'node:crypto';
import {spawn,execFile} from 'node:child_process';
import {promisify} from 'node:util';
import process from 'node:process';
const ROOT=resolve(dirname(fileURLToPath(import.meta.url)),'../../..');
const ENTRY='scripts/supabase/testing/current14-member-history.mjs';
const sha=x=>createHash('sha256').update(x).digest('hex');
const need=(ok,code)=>{if(!ok){const error=new Error('Current14 member-history capture unconfirmed');error.captureCode=code;throw error;}};
export function validateMemberHistoryTarget(raw){
 need(typeof raw==='string'&&raw.length<8192,'EXACT_CURRENT14_LOOPBACK_TARGET_REQUIRED');
 let target;try{target=new URL(raw);}catch{need(false,'EXACT_CURRENT14_LOOPBACK_TARGET_REQUIRED');}
 need(target.protocol==='postgres:'&&target.hostname==='127.0.0.1'&&target.username==='postgres'&&target.password.length>0&&target.port!==''&&Number(target.port)>0&&Number(target.port)<=65535&&!target.search&&!target.hash&&/^\/collect_fence_stopped_history_[a-f0-9]{24}_test$/.test(target.pathname),'EXACT_CURRENT14_LOOPBACK_TARGET_REQUIRED');
 let password;try{password=decodeURIComponent(target.password);}catch{need(false,'EXACT_CURRENT14_LOOPBACK_TARGET_REQUIRED');}
 need(password.length<=2048&&!/[\x00-\x20\x7f]/.test(password),'EXACT_CURRENT14_LOOPBACK_TARGET_REQUIRED');return target;
}
export function validateMemberHistoryInvocation(env,nodeVersion=process.versions.node){
 need(/^24\./.test(nodeVersion),'NODE_24_REQUIRED');
 need(env.COLLECT_CI_SYNTHETIC==='true','EXPLICIT_SYNTHETIC_CI_REQUIRED');
 const target=validateMemberHistoryTarget(env.COLLECT_MEMBER_HISTORY_DATABASE_URL);
 for(const key of ['COLLECT_DENO','COLLECT_MEMBER_HISTORY_OUTPUT_DIR'])need(typeof env[key]==='string'&&isAbsolute(env[key])&&resolve(env[key])===env[key]&&!/[\x00-\x1f\x7f]/.test(env[key]),'PHYSICAL_EXECUTABLE_AND_OUTPUT_REQUIRED');
 return {target,deno:env.COLLECT_DENO,output:env.COLLECT_MEMBER_HISTORY_OUTPUT_DIR};
}
export function validateMemberHistoryRunSpec(spec,specPath){
 need(spec?.format==='collect.current14.history.run-spec.v1'&&spec.source===ROOT&&isAbsolute(spec.output)&&specPath===join(spec.output,'RUN-SPEC.private.json'),'FIXED_CAPTURE_SPEC_REQUIRED');
 const target=validateMemberHistoryTarget(spec.url),name=target.pathname.slice(1);
 need(Number.isSafeInteger(spec.port)&&spec.port===Number(target.port),'EXACT_CAPTURE_SPEC_PORT_REQUIRED');
 return {target,name};
}
export async function admitMemberHistoryOutput(path){
 need(isAbsolute(path)&&resolve(path)===path&&await realpath(dirname(path))===dirname(path),'PHYSICAL_PRIVATE_OUTPUT_PARENT_REQUIRED');
 try{await lstat(path);}catch(error){if(error.code==='ENOENT')return;throw error;}
 need(false,'FRESH_MEMBER_HISTORY_OUTPUT_REQUIRED');
}
export function validateMemberHistoryReceipt(value){
 need(value&&Object.keys(value).sort().join(',')==='SQL_statements,actual_runtime_transactions_commit,all_six_legacy_SQL_gates_closed,cases,failure,fixture_data_preserved,format,hosted_acceptance,packet,provider_calls,requests,source_parity_verified,status','EXACT_MEMBER_HISTORY_RESULT_REQUIRED');
 need(value.format==='collect.current14.actual-member-history-native.v1'&&value.status==='PASS'&&value.failure===null&&value.source_parity_verified===true&&value.actual_runtime_transactions_commit===true&&value.fixture_data_preserved===true&&value.provider_calls===0&&value.hosted_acceptance===false&&value.all_six_legacy_SQL_gates_closed===false,'EXACT_MEMBER_HISTORY_SCOPE_REQUIRED');
 for(const key of ['cases','requests','SQL_statements'])need(Number.isSafeInteger(value[key])&&value[key]>0,'ACTUAL_MEMBER_HISTORY_COUNTS_REQUIRED');
 need(value.packet&&Object.keys(value.packet).sort().join(',')==='path,sha256'&&isAbsolute(value.packet.path)&&/^[a-f0-9]{64}$/.test(value.packet.sha256),'MEMBER_HISTORY_PACKET_BINDING_REQUIRED');return value;
}
export async function snapshotMemberHistorySources(root,extraRoles=[]){
 const roles=[];
 async function visit(directory,pattern,skipTests=false){for(const item of await readdir(join(root,directory),{withFileTypes:true})){if(skipTests&&item.name==='tests')continue;const role=directory+'/'+item.name;if(item.isDirectory())await visit(role,pattern,skipTests);else if(item.isFile()&&pattern.test(item.name))roles.push(role);}}
 await visit('supabase/functions',/\.(?:js|mjs)$/,true);
 // The actual money decoder and signed-history implementation are Dart parts,
 // so parent-file pins alone cannot bind the executing consumer implementation.
 await visit('lib/shared/models',/\.dart$/);
 roles.push(...(await readdir(join(root,'supabase/migrations'))).filter(name=>/^\d{14}_.*\.sql$/.test(name)).map(name=>'supabase/migrations/'+name));
 roles.push(ENTRY,'scripts/supabase/test_schema.mjs','scripts/supabase/testing/qualify-stopped-admission-native.mjs','scripts/supabase/testing/curated-platform-fixture.mjs','scripts/supabase/testing/member-realtime-fixture-plan.json','scripts/supabase/testing/member-realtime-interface.sql','scripts/supabase/testing/member-realtime-metadata.sql','supabase/tests/sql/00_local_auth_fixture.sql','supabase/tests/sql/02_financial_authority.sql','supabase/functions/deno.json','supabase/functions/deno.lock','lib/shared/models/member_history_page.dart','lib/shared/models/collect_models.dart','lib/core/data/exact_json_values.dart','lib/shared/repositories/collect_repository_live_reader.dart','test/current14_member_history_sql_receipts_test.dart','.fvmrc','pubspec.yaml','pubspec.lock',...extraRoles);
 const files=[];for(const role of [...new Set(roles)].sort()){const path=resolve(root,role);need(path.startsWith(root+'/')&&await realpath(path)===path,'FIXED_PHYSICAL_CAPTURE_SOURCE_REQUIRED');const bytes=await readFile(path);files.push({role,path,bytes:bytes.length,sha256:sha(bytes)});}return files;
}
async function verifyFiles(files){for(const pin of files)need(await realpath(pin.path)===pin.path&&sha(await readFile(pin.path))===pin.sha256,'MEMBER_HISTORY_SOURCE_CHANGED');}
export {verifyFiles as verifyMemberHistorySources};
async function writeExclusive(path,value){const file=await open(path,'wx',0o600);try{await file.writeFile(JSON.stringify(value,null,2)+'\n');await file.sync();}finally{await file.close();}}
export async function captureBoundedHistoryChild(executable,argv,{cwd,env,deadlineMs=90000}){
 need(Number.isSafeInteger(deadlineMs)&&deadlineMs>0&&deadlineMs<=90000,'BOUNDED_HISTORY_CHILD_REQUIRED');
 const child=spawn(executable,argv,{cwd,env,shell:false,stdio:['ignore','pipe','pipe']});let bytes=0,errors=0,expired=false,overflow=false,reaped=false,spawnError=false,cancelled=false,out=[],err=[];let kill;
 const stop=()=>{child.kill('SIGTERM');kill??=setTimeout(()=>child.kill('SIGKILL'),5000);};
 const cancel=()=>{cancelled=true;stop();};process.on('SIGTERM',cancel);process.on('SIGINT',cancel);
 const timer=setTimeout(()=>{expired=true;stop();},deadlineMs);
 child.stdout.on('data',data=>{bytes+=data.length;if(bytes<=65536)out.push(data);else{overflow=true;stop();}});
 child.stderr.on('data',data=>{errors+=data.length;if(errors<=65536)err.push(data);else{overflow=true;stop();}});
 child.on('error',()=>{spawnError=true;stop();});const exit=await new Promise(done=>child.once('close',(code,signal)=>{reaped=true;done({code,signal});}));clearTimeout(timer);clearTimeout(kill);process.off('SIGTERM',cancel);process.off('SIGINT',cancel);
 return {metadata:{...exit,reaped,expired,overflow,spawn_error:spawnError,cancelled,stdout_bytes:bytes,stdout_sha256:sha(Buffer.concat(out)),stderr_bytes:errors,stderr_sha256:sha(Buffer.concat(err))},stdout:Buffer.concat(out),stderr:Buffer.concat(err)};
}
export async function captureCurrent14MemberHistory(env=process.env){
 process.umask(0o077);const config=validateMemberHistoryInvocation(env);
 need(await realpath(ROOT)===ROOT&&await realpath(config.deno)===config.deno,'PHYSICAL_CAPTURE_ROOT_AND_DENO_REQUIRED');
 await admitMemberHistoryOutput(config.output);
 const files=await snapshotMemberHistorySources(ROOT);await verifyFiles(files);
 const {stdout:headText}=await promisify(execFile)('git',['rev-parse','HEAD'],{cwd:ROOT,timeout:5000,maxBuffer:256});
 const sourceCommit=headText.trim();need(/^[a-f0-9]{40}$/.test(sourceCommit)&&(!env.GITHUB_SHA||sourceCommit===env.GITHUB_SHA),'EXACT_CAPTURE_SOURCE_COMMIT_REQUIRED');
 await mkdir(config.output,{mode:0o700});
 const inputs=join(config.output,'INPUTS.json'),specPath=join(config.output,'RUN-SPEC.private.json');
 await writeExclusive(inputs,{format:'collect.current14.history.inputs.v1',source_commit:sourceCommit,files,deno:{path:config.deno,sha256:sha(await readFile(config.deno))},source_metadata_scope:'Runtime JS, exact14 SQL, reviewed fixture and actual Dart consumer bodies; no live account state asserted.'});
 const spec={format:'collect.current14.history.run-spec.v1',source:ROOT,source_commit:sourceCommit,output:config.output,inputs,url:config.target.href,port:Number(config.target.port)};
 let metadata,failed;
 try{
  await writeExclusive(specPath,spec);const specSha=sha(await readFile(specPath));
  const argv=['run','--check','--cached-only','--frozen','--node-modules-dir=none','--config='+join(ROOT,'supabase/functions/deno.json'),'--lock='+join(ROOT,'supabase/functions/deno.lock'),'--allow-env','--allow-read='+ROOT+','+config.output,'--allow-write='+config.output,'--allow-net=127.0.0.1:'+config.target.port,join(ROOT,ENTRY),'--execute-fixture',specPath,specSha];
  const childEnv={NO_COLOR:'1'};for(const key of ['HOME','PATH','TMPDIR','LANG','LC_ALL','DENO_DIR'])if(env[key]!==undefined)childEnv[key]=env[key];
  const child=await captureBoundedHistoryChild(config.deno,argv,{cwd:ROOT,env:childEnv});metadata=child.metadata;
  const redact=bytes=>bytes.toString('utf8').replaceAll(config.target.href,'[LOCAL_SYNTHETIC_URL]').replaceAll(decodeURIComponent(config.target.password),'[LOCAL_SYNTHETIC_PASSWORD]');
  for(const[name,bytes]of [['CHILD-STDOUT.log',child.stdout],['CHILD-STDERR.log',child.stderr]]){const log=await open(join(config.output,name),'wx',0o600);try{await log.writeFile(redact(bytes));await log.sync();}finally{await log.close();}}
  await writeExclusive(join(config.output,'CHILD-METADATA.json'),metadata);
  need(metadata.code===0&&metadata.reaped&&!metadata.expired&&!metadata.overflow&&!metadata.spawn_error&&!metadata.cancelled,'ACTUAL_MEMBER_HISTORY_CHILD_UNCONFIRMED');
  const receipt=validateMemberHistoryReceipt(JSON.parse(await readFile(join(config.output,'NATIVE-RESULT.json'),'utf8')));
  need(receipt.packet.path===join(config.output,'ACTUAL-HISTORY-PACKET.json')&&sha(await readFile(receipt.packet.path))===receipt.packet.sha256,'MEMBER_HISTORY_PACKET_CHANGED');
  const inputSha=sha(await readFile(inputs)),sqlSha=sha(await readFile(join(config.output,'ACTUAL-SQL-STATEMENTS.json')));
  // Only these three filename values need rebasing after artifact download.
  // Digests bind the original bytes; all source files also carry relative roles.
  await writeExclusive(join(config.output,'DEFINES.json'),{CURRENT14_HISTORY_PACKET:'ACTUAL-HISTORY-PACKET.json',CURRENT14_HISTORY_PACKET_SHA256:receipt.packet.sha256,CURRENT14_HISTORY_INPUTS:'INPUTS.json',CURRENT14_HISTORY_INPUTS_SHA256:inputSha,CURRENT14_HISTORY_SQL:'ACTUAL-SQL-STATEMENTS.json',CURRENT14_HISTORY_SQL_SHA256:sqlSha,CURRENT14_HISTORY_SOURCE_COMMIT:sourceCommit});
  await verifyFiles(files);await writeExclusive(join(config.output,'RESULT.json'),{format:'collect.current14.history.capture.v1',status:'PASS',source_commit:sourceCommit,packet:receipt.packet,inputs:{path:inputs,sha256:inputSha},SQL:{path:join(config.output,'ACTUAL-SQL-STATEMENTS.json'),sha256:sqlSha},defines:{path:join(config.output,'DEFINES.json'),sha256:sha(await readFile(join(config.output,'DEFINES.json')))},native_result:{path:join(config.output,'NATIVE-RESULT.json'),sha256:sha(await readFile(join(config.output,'NATIVE-RESULT.json')))},child:metadata,provider_calls:0,hosted_acceptance:false,legacy_gates_closed:false});
  return JSON.parse(await readFile(join(config.output,'RESULT.json'),'utf8'));
 }catch(error){failed={code:error.captureCode??'CURRENT14_CAPTURE_UNCONFIRMED'};await writeExclusive(join(config.output,'FAILURE.json'),{status:'FAIL',failure:failed,child:metadata??null,provider_calls:0,hosted_acceptance:false,legacy_gates_closed:false});throw error;}
 finally{await unlink(specPath).catch(error=>{if(error.code!=='ENOENT')throw error;});}
}
async function executeFixture(specPath,specSha){
 need(/^[a-f0-9]{64}$/.test(specSha)&&isAbsolute(specPath),'PRIVATE_EXECUTION_SPEC_REQUIRED');
 const specBytes=await readFile(specPath);need(sha(specBytes)===specSha,'PRIVATE_EXECUTION_SPEC_CHANGED');const spec=JSON.parse(specBytes);
 const {target,name}=validateMemberHistoryRunSpec(spec,specPath);
 const inputs=JSON.parse(await readFile(spec.inputs,'utf8'));await verifyFiles(inputs.files);
 const source=role=>pathToFileURL(join(spec.source,role)).href;
 const save=(name,value)=>writeExclusive(join(spec.output,name),value);
 const parity=()=>verifyFiles(inputs.files);
 const postgres=(await import('npm:postgres@3.4.7')).default;
 const {loadReviewedPlatformFixture,ROOT_SQL14_SHA256}=await import(source('scripts/supabase/testing/curated-platform-fixture.mjs'));
 const {connection,fenceConnection,PostgresDatabase}=await import(source('supabase/functions/_shared/postgres.js'));
 const {openApplicationWork,sqlFenceBackend}=await import(source('supabase/functions/_shared/application-fence.js'));
 const {dispatchOperation}=await import(source('supabase/functions/_shared/domain/operations.js'));
 const {requireSession}=await import(source('supabase/functions/_shared/domain/auth.js'));
 const fixtureSource='a'.repeat(64),runtimePools=new Set(),requests=[],statements=[],cases=[],closes=[],runtimeIdentities=[];
 const step=(name,details={})=>cases.push({name,status:'pass',...details});
 const rawOwner=postgres(spec.url,{max:1,prepare:false,ssl:false,onnotice:()=>{}});runtimePools.add(rawOwner);
 const owner={query:async(text,values=[])=>({rows:Array.from(await rawOwner.unsafe(text,values))})},setup=owner;
 let stage='current14_identity',failure=null,packet=null;const originalFetch=globalThis.fetch;
 const fixture=await loadReviewedPlatformFixture(spec.source,{includeStoppedAdmissionLifecycleMigration:true});
 try{
  assert.equal(fixture.names.length,14);
  const observed=(await owner.query("SELECT current_user owner,session_user session,host(inet_server_addr()) host,inet_server_port() port,current_database() database,current_setting('server_version_num') version,(SELECT rolsuper FROM pg_roles WHERE rolname=current_user) superuser,(SELECT rolbypassrls FROM pg_roles WHERE rolname=current_user) bypass,(SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname=current_database()) database_owner,to_regclass('private.collect_fence_stopped_admissions')::text stopped_table,(SELECT count(*)::int FROM app.users) app_users")).rows[0];
  assert.equal(observed.owner,'postgres');assert.equal(observed.session,'postgres');assert.equal(observed.host,'127.0.0.1');assert.equal(observed.port,spec.port);assert.match(observed.database,/^collect_fence_stopped_history_[a-f0-9]{24}_test$/);assert.match(observed.version,/^17\d{4}$/);assert.equal(observed.superuser,false);assert.equal(observed.bypass,false);assert.equal(observed.database_owner,'postgres');assert.equal(observed.stopped_table,'private.collect_fence_stopped_admissions');assert.equal(observed.app_users,0);
  const initial=(await owner.query('SELECT private.collect_fence_owner_status() AS status')).rows[0].status;assert.equal(initial.sourceSha256,fixtureSource);assert.equal(initial.mode,'open');assert.equal(initial.activeAdmissions,0);assert.equal(initial.unresolvedAdmissions,0);assert.equal(initial.retainedUnknownObligations,0);
  await save('SCHEMA-IDENTITY.json',{observed,migrations:fixture.rawMigrations.map(x=>({name:x.name,sha256:x.sha256})),sql14_sha256:ROOT_SQL14_SHA256,source_sql_rewritten:false,provider_calls:0});step('exact current14 and actual normal PostgreSQL owner/runtime profiles');
 const q=(text,values=[])=>setup.query(text,values);
 // Source-owned fixture seeds use the exact retained storage-control helper.
 const financial=await readFile(spec.source+'/supabase/tests/sql/02_financial_authority.sql','utf8');
 const storageHelper=financial.match(/CREATE FUNCTION pg_temp\.seed_storage[\s\S]*?END\$\$;/)?.[0];assert(storageHelper);
 await q('SET search_path=app,pg_catalog');await q(storageHelper);
 const at=Math.floor(Date.now()/1000),stamp='2026-10-26T00:00:00.000Z';
 const actors=[];
 for(let i=0;i<5;i++){
  const a={auth:randomUUID(),id:randomUUID(),session:randomUUID(),phone:'+250788'+String(800000+i),public:String(800000+i),email:'history-'+i+'@example.test'};
  await q('INSERT INTO auth.users(id,email,phone,phone_confirmed_at) VALUES($1,$2,$3,now())',[a.auth,a.email,a.phone.slice(1)]);
  await q("INSERT INTO auth.sessions(id,user_id,aal,not_after) VALUES($1,$2,'aal1',now()+interval '2 hours')",[a.session,a.auth]);
  await q('INSERT INTO app.users(id,phone,email,public_id,full_name,momo_number,created_at,updated_at) VALUES($1,$2,$3,$4,$5,$2,$6,$6)',[a.id,a.phone,a.email,a.public,'Synthetic history '+i,stamp]);
  await q("INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference) VALUES($1,$2,'synthetic-local-history-no-provider')",[a.auth,a.id]);
  await q("INSERT INTO app.auth_sessions(id,user_id,surface,auth_at,created_at,expires_at) VALUES($1,$2,'member',$3,$3,$4)",[a.session,a.id,at,at+7200]);
  const claims={sub:a.auth,session_id:a.session,role:'authenticated',aal:'aal1',aud:'authenticated',iat:at,exp:at+7200,iss:'https://synthetic-history.example/auth/v1',amr:[{method:'otp',timestamp:at}]};
  a.token=Buffer.from('{"alg":"ES256","typ":"JWT"}').toString('base64url')+'.'+Buffer.from(JSON.stringify(claims)).toString('base64url')+'.synthetic-not-a-hosted-signature';actors.push(a);
 }
 const [viewer,other,maximum,concurrent,unsafe]=actors;
 async function group(label,members){const id=randomUUID();await q("INSERT INTO app.collections(id,slug,creator_user_id,title,collection_type,receiver_momo_number,receiver_network,created_at,updated_at) VALUES($1,$2,$3,$4,'ikimina','250788123491','mtn_momo',$5,$5)",[id,'history-'+id,members[0].id,label,stamp]);for(const a of members)await q("INSERT INTO app.memberships(id,collection_id,user_id,role,joined_at) VALUES($1,$2,$3,'member',$4)",[randomUUID(),id,a.id,stamp]);return id;}
 const main=await group('Synthetic Main History',[viewer,other]),empty=await group('Synthetic Empty',[viewer]),maxGroup=await group('Synthetic Maximum',[maximum]),concurrentGroup=await group('Synthetic Concurrent',[concurrent]),unsafeGroup=await group('Synthetic Unsafe Aggregate',[unsafe]),foreign=await group('Synthetic Foreign',[other]);
 const seeded=[];
 async function seedPayment(client,collection,member,amount,ordinal){
  const id=randomUUID(),evidence=randomUUID(),entry=randomUUID(),object='history-fixture/'+evidence;
  await client.query("SELECT pg_temp.seed_storage($1,$2,$3,repeat('a',64),'payment_evidence')",[object,viewer.id,evidence]);
  await client.query("INSERT INTO app.payment_evidence(id,collection_id,owner_user_id,object_key,object_sha256,size_bytes,content_type,authenticity,external_reference,receiver_momo_number,receiver_network,amount_minor,observed_at,created_at) VALUES($1,$2,$3,$4,repeat('a',64),12,'text/plain','operator_recorded',$5,'250788123491','mtn_momo',$6,$7,$7)",[evidence,collection,viewer.id,object,'SYNTHETIC-'+ordinal,amount.toString(),stamp]);
  await client.query("INSERT INTO app.payments(id,collection_id,member_id,evidence_id,amount_minor,status,payer_display_name,created_at) VALUES($1,$2,$3,$4,$5,'reconciled',$6,$7)",[id,collection,member.id,evidence,amount.toString(),'Synthetic supporter '+member.public,stamp]);
  await client.query("INSERT INTO app.ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind,evidence_id,actor_user_id,request_id,posted_at) VALUES($1,$2,$3,$4,$5,'contribution',$6,$7,$8,$9)",[entry,id,collection,member.id,amount.toString(),evidence,viewer.id,randomUUID(),stamp]);
  const value={entry,payment:id,collection,member:member.id,amount:amount.toString()};seeded.push(value);return value;
 }
 let small=0n;for(let i=0;i<66;i++)small+=BigInt(1+i%9);
 for(let i=0;i<67;i++)await seedPayment(setup,main,i%2?other:viewer,i===66?9007199254740991n-small:BigInt(1+i%9),'main-'+i);
 await seedPayment(setup,maxGroup,maximum,9007199254740991n,'max');
 await seedPayment(setup,foreign,other,19n,'foreign');
 await seedPayment(setup,concurrentGroup,concurrent,7n,'concurrent-a');await seedPayment(setup,concurrentGroup,concurrent,31n,'concurrent-b');
 await seedPayment(setup,unsafeGroup,unsafe,9007199254740991n,'unsafe-a');await seedPayment(setup,unsafeGroup,unsafe,1n,'unsafe-b');
 step('synthetic ledger seeds retain actual schema/storage/accounting triggers',{main_rows:67,direct_fixture_seeding:true,financial_posting_acceptance:false});
 const nativeFetch=globalThis.fetch;globalThis.fetch=async(input,options)=>{const url=typeof input==='string'?input:input instanceof URL?input.href:input.url;assert.equal(url,'https://synthetic-history.example/auth/v1/user','Outbound provider/network refused');const headers=new Headers(options?.headers??input?.headers);const actor=actors.find(a=>headers.get('Authorization')==='Bearer '+a.token);assert(actor,'Unknown synthetic managed actor');return Response.json({id:actor.auth,email:actor.email,email_confirmed_at:stamp,phone:actor.phone.slice(1),phone_confirmed_at:stamp,app_metadata:{provider:'phone'},user_metadata:{}});};
 const business=connection(target.href),control=fenceConnection(target.href);runtimePools.add(business);runtimePools.add(control);
 async function call(actor,operation,body){
  const work=await openApplicationWork({backend:sqlFenceBackend(business,control),sourceSha256:fixtureSource,kind:'http_collect'});
  const db=new PostgresDatabase(business,{},work);let serial=0;const actual=db.statement.bind(db);
  db.statement=async(tx,statement)=>{const row={request:requests.length,sequence:serial++,sql:statement.sql,parameters:statement.values};try{const result=await actual(tx,statement);row.actual_result=result;statements.push(row);return result;}catch(e){row.failure={code:e.code??null,message:e.message};statements.push(row);throw e;}};
  const env={DB:db,COLLECT_FENCE_WORK:work,SUPABASE_URL:'https://synthetic-history.example',SUPABASE_PUBLISHABLE_KEY:'synthetic-local-only',MOMO_PROCESSING_PAUSED:'true',AUTH_MEMBER_REGISTRATION_ENABLED:'false'};
  const request={method:'POST',path:'/v1/rpc/'+operation,body,actor_id:actor.id,session_id:actor.session};
  let response;
  try{const resolved=await requireSession(new Request('https://synthetic-history.example'+request.path,{headers:{Authorization:'Bearer '+actor.token}}),env);assert.equal(resolved.userId,actor.id);const runtime=await db.prepare("SELECT current_user AS current_role,session_user AS session_role,current_setting('collect.edge_verified') AS edge_verified").first();assert.equal(runtime.current_role,'collect_runtime');assert.equal(runtime.session_role,'postgres');assert.equal(runtime.edge_verified,'true');runtimeIdentities.push(runtime);const value=await dispatchOperation('rpc',operation,body,env,resolved);response={status:200,body:value};}
  catch(e){response={status:e.status??500,body:{code:e.code??'unexpected_error',message:e.message}};}
  finally{closes.push(await work.finish());}
  requests.push({request,response});return response;
 }
 const pages=[];
 for(const version of [1,2])for(const search of ['', 'Synthetic Main History'])for(const sort of ['newest','oldest','highest','lowest']){
  // V1 searches supporter label; V2 searches the actual group title.
  const query=version===1&&search?'Synthetic supporter':search;let cursor=null;const ids=[],windows=[];
  do{const body={p_contract_version:version,p_query:query,p_sort:sort,p_limit:5,...(cursor?{p_cursor:cursor}:{})};const result=await call(viewer,'list_current_member_history_page',body);assert.equal(result.status,200,JSON.stringify(result));assert.equal(result.body.total_count,67);assert.equal(result.body.totals.RWF,9007199254740991);assert(result.body.items.length>0);assert.equal(new Set(result.body.items.map(x=>version===2?x.entry_id:x.payment_id)).size,result.body.items.length);ids.push(...result.body.items.map(x=>version===2?x.entry_id:x.payment_id));const wire={contract_version:version,query:{collection_id:null,search:query,sort},requested_cursor:cursor,limit:5,response:result.body};pages.push(wire);windows.push(wire);cursor=result.body.next_cursor;}while(cursor);
  assert.equal(ids.length,67);assert.equal(new Set(ids).size,67);step('complete tie-safe four-sort SQL history chain',{version,query,sort,windows:windows.length,total:67});
 }
 for(const version of [1,2])for(const body of [{p_collection_id:empty},{p_query:'ABSENT-SYNTHETIC-HISTORY'}]){const result=await call(viewer,'list_current_member_history_page',{p_contract_version:version,p_sort:'newest',p_limit:5,...body});assert.equal(result.status,200);assert.equal(result.body.total_count,0);pages.push({contract_version:version,query:{collection_id:body.p_collection_id??null,search:body.p_query??'',sort:'newest'},requested_cursor:null,limit:5,response:result.body});}
 step('genuine empty collection and empty-search windows');
 for(const version of [1,2]){const result=await call(maximum,'list_current_member_history_page',{p_contract_version:version,p_limit:5});assert.equal(result.status,200);assert.equal(result.body.items.length,1);assert.equal(result.body.items[0].amount_minor,9007199254740991);pages.push({contract_version:version,query:{collection_id:null,search:'',sort:'newest'},requested_cursor:null,limit:5,response:result.body});}
 step('exact maximum-safe individual and aggregate survive actual adapter');
 const balances=await call(viewer,'list_current_member_collection_balances',{});assert.equal(balances.status,200);assert(balances.body.some(x=>x.balances[0].amount_raised_minor===0));assert(balances.body.some(x=>x.balances[0].amount_raised_minor===9007199254740991));
 const foreignDenial=await call(viewer,'list_current_member_history_page',{p_contract_version:2,p_collection_id:foreign,p_limit:5});assert.equal(foreignDenial.status,200);assert.equal(foreignDenial.body.total_count,0);step('cross-group SQL rows excluded without exposing foreign history');
 const precision=[];
 for(const version of [1,2]){const result=await call(unsafe,'list_current_member_history_page',{p_contract_version:version,p_limit:5});assert.equal(result.status,503);assert.equal(result.body.code,'history_unavailable');precision.push({kind:'actual_current_aggregate_refusal',contract_version:version,response:result});}
 await q('BEGIN');try{await q('INSERT INTO app.payments(id,collection_id,evidence_id,amount_minor,status,created_at) VALUES($1,$2,$3,$4,$5,$6)',[randomUUID(),main,randomUUID(),'9007199254740992','recorded',stamp]);throw Error('Unsafe amount was accepted');}catch(e){assert.equal(e.code,'23514');precision.push({kind:'actual_SQL_precision_constraint_refusal',sqlstate:e.code});}finally{await q('ROLLBACK');}step('actual schema and current handlers refuse unsafe precision');
 const concurrentSorts={};
 for(const sort of ['newest','oldest','highest','lowest']){
  const first=await call(concurrent,'list_current_member_history_page',{p_contract_version:2,p_collection_id:concurrentGroup,p_sort:sort,p_limit:1});assert.equal(first.status,200);assert(first.body.next_cursor);
  await q('BEGIN');await seedPayment(setup,concurrentGroup,concurrent,BigInt(50+Object.keys(concurrentSorts).length),'concurrent-added-'+sort);
  const uncommitted=await call(concurrent,'list_current_member_history_page',{p_contract_version:2,p_collection_id:concurrentGroup,p_sort:sort,p_limit:1,p_cursor:first.body.next_cursor});assert.equal(uncommitted.status,200);await q('COMMIT');
  const stale=await call(concurrent,'list_current_member_history_page',{p_contract_version:2,p_collection_id:concurrentGroup,p_sort:sort,p_limit:1,p_cursor:first.body.next_cursor});assert.equal(stale.status,409);assert.equal(stale.body.code,'history_changed');
  const fresh=[];let cursor=null;do{const r=await call(concurrent,'list_current_member_history_page',{p_contract_version:2,p_collection_id:concurrentGroup,p_sort:sort,p_limit:1,...(cursor?{p_cursor:cursor}:{})});assert.equal(r.status,200);fresh.push(r.body);cursor=r.body.next_cursor;}while(cursor);
  assert.equal(new Set(fresh.flatMap(x=>x.items.map(i=>i.entry_id))).size,fresh[0].total_count);concurrentSorts[sort]={first:first.body,uncommitted_next_page:uncommitted.body,actual_stale_cursor_response:stale,fresh_windows:fresh};step('actual uncommitted/committed cursor fence',{sort});
 }
 const currentRows=await call(viewer,'list_current_user_collections',{});assert.equal(currentRows.status,200);
 await q('UPDATE app.auth_sessions SET revoked_at=$1,revocation_reason=$2 WHERE id=$3',[Math.floor(Date.now()/1000),'synthetic_fixture_revocation',viewer.session]);
 const revoked=await call(viewer,'list_current_member_history_page',{p_contract_version:2,p_limit:5});assert([401,403].includes(revoked.status));step('actual native/app revocation blocks current member history');
 for(const {response}of requests.filter(x=>x.response.status===200&&x.response.body?.items)){for(const row of response.body.items){assert.equal(row.transaction_id,undefined);assert.equal(row.phone,undefined);assert.equal(row.email,undefined);assert.equal(row.raw_body,undefined);assert.equal(row.external_reference,undefined);}}
 step('actual history responses omit transaction/phone/email/raw receipt disclosure');
 await parity();await fixture.parity();
 const controlStatus=(await owner.query('SELECT private.collect_fence_owner_status() AS status')).rows[0].status;assert.equal(controlStatus.activeAdmissions,0);assert.equal(controlStatus.unresolvedAdmissions,0);assert.equal(controlStatus.retainedUnknownObligations,0);
 packet={format:'collect.current14.actual-member-history-sql.v1',source_commit:spec.source_commit,source_inputs_sha256:sha(await readFile(spec.inputs)),fixture:{database:name,synthetic_only:true,source_sha256:fixtureSource,current14:true,normal_runtime_role:'collect_runtime',financial_rows_directly_seeded:true,financial_posting_acceptance:false},pages,balances:balances.body,actual_collection_rows:currentRows.body,precision_observations:precision,concurrent_sorts:concurrentSorts,foreign_response:foreignDenial,revoked_response:revoked,requests,SQL_statement_count:statements.length,runtime_identities:runtimeIdentities,control_status:controlStatus,synthetic_managed_auth:true,provider_calls:0,hosted_acceptance:false};
 await save('ACTUAL-SQL-STATEMENTS.json',statements);await save('ACTUAL-HISTORY-PACKET.json',packet);await save('CASES.json',cases);stage='complete';
}catch(e){failure={stage,type:e.constructor?.name??'Error',message:e.message,sqlstate:e.code??null};}
 finally{globalThis.fetch=originalFetch;for(const pool of runtimePools)try{await pool.end({timeout:2});}catch(e){failure??={stage:'pool_closure',message:e.message};}}
 if(failure){await save('PARTIAL-CASES.json',cases);await save('PARTIAL-REQUESTS.json',requests);await save('PARTIAL-SQL-STATEMENTS.json',statements);}
 const receipt={format:'collect.current14.actual-member-history-native.v1',status:failure?'FAIL':'PASS',failure,cases:cases.length,requests:requests.length,SQL_statements:statements.length,source_parity_verified:!failure,packet:packet?{path:join(spec.output,'ACTUAL-HISTORY-PACKET.json'),sha256:sha(await readFile(join(spec.output,'ACTUAL-HISTORY-PACKET.json')))}:null,actual_runtime_transactions_commit:true,fixture_data_preserved:true,provider_calls:0,hosted_acceptance:false,all_six_legacy_SQL_gates_closed:false};
 await save('NATIVE-RESULT.json',receipt);if(failure)throw Object.assign(new Error('Actual member-history fixture failed'),{captureCode:'ACTUAL_MEMBER_HISTORY_FIXTURE_FAILED'});
 return receipt;
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 try{
  if(typeof Deno!=='undefined'){need(process.argv.length===5&&process.argv[2]==='--execute-fixture','PRIVATE_EXECUTION_ONLY');const value=await executeFixture(process.argv[3],process.argv[4]);console.log(JSON.stringify({status:value.status,cases:value.cases,requests:value.requests,SQL_statements:value.SQL_statements}));}
  else{need(process.argv.length===2,'NO_ARGUMENTS_ALLOWED');console.log(JSON.stringify(await captureCurrent14MemberHistory()));}
 }catch(error){console.error(JSON.stringify({status:'FAIL',code:error.captureCode??'CURRENT14_CAPTURE_UNCONFIRMED'}));process.exitCode=1;}
}
