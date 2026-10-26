import {readFile,lstat,mkdir,open,realpath} from 'node:fs/promises';
import {resolve,dirname,isAbsolute,relative,sep} from 'node:path';
import {pathToFileURL} from 'node:url';
import {compilePlanningRequest,decodeManagementResult,preparePlanCandidate,compileCaptureRequest,assembleManagementSnapshot,sealManagementResponse} from './capture.mjs';
import {ArchiveError,PROJECT,HASH,exact,need,canonical,sha} from './codec.mjs';
import {privateDirectory,readPrivateFile,readEncryptedBundle} from './bundle.mjs';
import {restoreInertArchive} from './restore.mjs';
import {createManagementTransport,checkEnvironment} from './transport.mjs';
export const DEFAULT_SOURCE_ROOT=resolve(import.meta.dirname,'../../..');
const hash=x=>HASH.test(x??'');
const within=(p,root)=>{const r=relative(root,p);return r===''||r!=='..'&&!r.startsWith('..'+sep)&&!isAbsolute(r);};
export async function savePrivate(path,value){const f=await open(path,'wx',0o600);try{await f.writeFile(JSON.stringify(value,null,2)+'\n');await f.sync();}finally{await f.close();}const d=await open(dirname(path),'r');try{await d.sync();}finally{await d.close();}}
export async function freshDirectory(path,sourceRoot){need(isAbsolute(path)&&resolve(path)===path&&!within(path,sourceRoot),'OUTPUT_PATH_INVALID');await privateDirectory(dirname(path));await mkdir(path,{mode:0o700});await privateDirectory(path);return path;}
async function pinnedJson(path,pin,max=1024*1024){need(hash(pin),'HASH_REQUIRED');const raw=await readPrivateFile(path,max);need(sha(raw)===pin,'PIN_CHANGED');try{return {raw,value:JSON.parse(raw)};}catch{need(false,'PRIVATE_JSON_INVALID');}}
export async function sourceSet(path,pin,root=DEFAULT_SOURCE_ROOT){
 need(isAbsolute(root)&&await realpath(root)===root,'SOURCE_ROOT_INVALID');const {value:s}=await pinnedJson(path,pin,65536);exact(s,['format','project_ref','runtime_source_sha256','expected_migration_count','migrations']);
 need(s.format==='collect.current-archive.sources.v1'&&s.project_ref===PROJECT&&hash(s.runtime_source_sha256)&&Number.isSafeInteger(s.expected_migration_count)&&s.expected_migration_count>=1&&s.expected_migration_count<=32&&Array.isArray(s.migrations)&&s.migrations.length===s.expected_migration_count,'SOURCE_SET_INVALID');
 let previous='',bytes=0;const migrations=[];
 for(const m of s.migrations){exact(m,['version','name','path','sha256']);need(/^[0-9]{14}$/.test(m.version)&&m.version>previous&&/^[a-z0-9_]+$/.test(m.name)&&m.path==='supabase/migrations/'+m.version+'_'+m.name+'.sql'&&hash(m.sha256),'SOURCE_MIGRATION_INVALID');previous=m.version;const p=resolve(root,m.path),st=await lstat(p);need(st.isFile()&&!st.isSymbolicLink()&&await realpath(p)===p&&st.size<=16*1024*1024,'SOURCE_MIGRATION_INVALID');const data=await readFile(p);bytes+=data.length;need(bytes<=64*1024*1024&&sha(data)===m.sha256,'SOURCE_MIGRATION_CHANGED');migrations.push({version:m.version,name:m.name,sha256:m.sha256});}
 return {set:s,migrations};
}
function planSources(plan,sources){need(plan.fixtureDatabase===null&&plan.runtimeSourceSha256===sources.set.runtime_source_sha256&&plan.expectedMigrationCount===sources.set.expected_migration_count&&canonical(plan.migrations.map(({observed_record_sha256,...m})=>m))===canonical(sources.migrations),'PLAN_SOURCE_MISMATCH');}
function parse(argv){const [mode,...rest]=argv;need(['plan','capture','restore-inert'].includes(mode)&&rest.length%2===0,'ARGUMENTS_INVALID');const v={};for(let i=0;i<rest.length;i+=2){need(/^--[a-z][a-z0-9-]*$/.test(rest[i])&&!Object.hasOwn(v,rest[i])&&rest[i+1]&&!rest[i+1].startsWith('--'),'ARGUMENTS_INVALID');v[rest[i]]=rest[i+1];}return {mode,v};}
function allowed(v,required,optional=[]){need(required.every(k=>Object.hasOwn(v,k))&&Object.keys(v).every(k=>required.includes(k)||optional.includes(k)),'ARGUMENTS_INVALID');}
async function credential(v,env){need(Boolean(v['--token-file'])!==Boolean(v['--token-env']),'ONE_TOKEN_SOURCE_REQUIRED');let token;if(v['--token-file']){const raw=await readPrivateFile(v['--token-file'],16384);try{token=raw.toString('utf8').trim();}finally{raw.fill(0);}}else{need(v['--token-env']==='COLLECT_ARCHIVE_ACCESS_TOKEN','TOKEN_ENV_INVALID');token=env.COLLECT_ARCHIVE_ACCESS_TOKEN;delete env.COLLECT_ARCHIVE_ACCESS_TOKEN;}need(typeof token==='string'&&token.length>=16&&!/\s/.test(token),'TOKEN_INVALID');return token;}
export async function run(argv,{environment=process.env,transportFactory=createManagementTransport,makeClient}={}){
 need(Number(process.versions.node.split('.')[0])===24,'NODE24_REQUIRED');const {mode,v}=parse(argv),root=v['--source-root']??DEFAULT_SOURCE_ROOT;let out;
 const shared=['--source-set','--source-set-sha256','--output-dir'];const auth=['--source-root','--token-file','--token-env'];
 if(mode==='restore-inert')allowed(v,['--capture-result','--capture-result-sha256','--local-connection-file','--output-dir','--execute-reviewed-inert'],['--source-root']);
 else allowed(v,mode==='plan'?shared:[...shared,'--plan','--plan-sha256','--key-dir','--execute-reviewed-read-only'],auth);
 if(mode==='restore-inert')need(v['--execute-reviewed-inert']==='yes','ROOT_REVIEW_REQUIRED');else if(mode==='capture')need(v['--execute-reviewed-read-only']==='yes','ROOT_REVIEW_REQUIRED');
 try{
  if(mode==='restore-inert'){
   const {value:result}=await pinnedJson(v['--capture-result'],v['--capture-result-sha256']);
   need(result.format==='collect.current-archive.capture.v1'&&result.project_ref===PROJECT&&result.fixture===false&&hash(result.runtime_source_sha256)&&hash(result.source_snapshot_sha256),'CAPTURE_RESULT_INVALID');
   const {value:receipt}=await pinnedJson(result.receipt_path,result.receipt_sha256);need(canonical(receipt)===canonical(result.receipt),'RECEIPT_CHANGED');
   const {value:summary}=await pinnedJson(result.summary_path,result.summary_sha256);need(summary.source_snapshot_sha256===result.source_snapshot_sha256&&summary.runtime_source_sha256===result.runtime_source_sha256,'SUMMARY_CHANGED');
   const {snapshot}=await readEncryptedBundle({archivePath:receipt.archive_path,keyPath:receipt.key_path,expectedArchiveSha256:receipt.archive_sha256});need(snapshot.fixture===false&&snapshot.project_ref===PROJECT&&snapshot.runtime_source_sha256===result.runtime_source_sha256&&sha(canonical(snapshot))===result.source_snapshot_sha256,'SNAPSHOT_CHANGED');
   out=await freshDirectory(v['--output-dir'],root);await savePrivate(resolve(out,'INTENT.json'),{stage:mode,capture_result_sha256:v['--capture-result-sha256'],archive_sha256:receipt.archive_sha256,new_inert_database_only:true,automatic_retry:false});
   const urlBytes=await readPrivateFile(v['--local-connection-file'],16384);let url;try{url=urlBytes.toString('utf8').trim();}finally{urlBytes.fill(0);}
   if(!makeClient){const {Client}=await import('pg');makeClient=connectionString=>{const c=new Client({connectionString,ssl:false,statement_timeout:30000,connectionTimeoutMillis:5000});c.on('error',()=>{});return c;};}
   const native=await restoreInertArchive(snapshot,{adminUrl:url,makeClient});const file=resolve(out,'INERT_RESTORE.json');await savePrivate(file,native);return {stage:mode,receipt_path:file,receipt_sha256:sha(await readFile(file)),database:native.database,tables:native.tables.length,rows:native.tables.reduce((n,t)=>n+t.rows,0),columns_and_native_cells_exact:true,full_recovery_acceptance:false};
  }
  checkEnvironment(environment);const sources=await sourceSet(v['--source-set'],v['--source-set-sha256'],root);
  let plan;if(mode==='capture'){plan=(await pinnedJson(v['--plan'],v['--plan-sha256'])).value;planSources(plan,sources);}
  const compiled=mode==='plan'?compilePlanningRequest({expectedMigrationCount:sources.set.expected_migration_count}):compileCaptureRequest(plan);
  out=await freshDirectory(v['--output-dir'],root);await savePrivate(resolve(out,'COMPILED_REQUEST.json'),compiled);await savePrivate(resolve(out,'INTENT.json'),{stage:mode,project_ref:PROJECT,source_set_sha256:v['--source-set-sha256'],source_runtime_sha256:sources.set.runtime_source_sha256,expected_migration_count:sources.set.expected_migration_count,plan_sha256:v['--plan-sha256']??null,query_sha256:compiled.query_sha256,automatic_retry:false,app_private_rows_read:mode==='capture'});
  const token=await credential(v,environment);const transport=transportFactory({token,environment});await transport.readProject();
  if(mode==='capture'){need(!within(v['--key-dir'],out)&&!within(out,v['--key-dir']),'KEY_CUSTODY_SEPARATION_REQUIRED');await freshDirectory(v['--key-dir'],root);}
  let response;try{
   response=await transport.query(compiled);await sourceSet(v['--source-set'],v['--source-set-sha256'],root);const http={status:response.status,response_sha256:sha(response.body),response_bytes:response.body.length,raw_response_written:false,native_rollback_command_complete_observed:false};
   if(mode==='plan'){
    const metadata=decodeManagementResult(response,compiled);const candidate=preparePlanCandidate(metadata,{runtimeSourceSha256:sources.set.runtime_source_sha256,sourceMigrations:sources.migrations,expectedMigrationCount:sources.set.expected_migration_count});
    const metadataPath=resolve(out,'METADATA.private.json'),planPath=resolve(out,'CANDIDATE_PLAN.json');await savePrivate(metadataPath,metadata);await savePrivate(planPath,candidate);await savePrivate(resolve(out,'HTTP_RECEIPT.json'),http);
    return {stage:mode,candidate_plan_path:planPath,candidate_plan_sha256:sha(await readFile(planPath)),relations:candidate.relations.length,migrations:candidate.migrations.length,reviewed_plan:false,actual_data_capture:false};
   }
   const snapshot=assembleManagementSnapshot(response,plan,compiled),receipt=await sealManagementResponse(response,plan,compiled,{archiveDirectory:out,keyDirectory:v['--key-dir']});
   const summary={runtime_source_sha256:snapshot.runtime_source_sha256,source_snapshot_sha256:sha(canonical(snapshot)),postgres:snapshot.postgres,management_provenance:snapshot.management_provenance,tables:snapshot.tables.map(t=>({schema:t.schema,name:t.name,rows:t.row_count,sha256:t.sha256})),full_recovery_acceptance:false};
   const receiptPath=resolve(out,'ARCHIVE_RECEIPT.json'),summaryPath=resolve(out,'SUMMARY.json');await savePrivate(receiptPath,receipt);await savePrivate(summaryPath,summary);await savePrivate(resolve(out,'HTTP_RECEIPT.json'),http);
   const result={format:'collect.current-archive.capture.v1',project_ref:PROJECT,fixture:false,runtime_source_sha256:snapshot.runtime_source_sha256,source_snapshot_sha256:summary.source_snapshot_sha256,receipt_path:receiptPath,receipt_sha256:sha(await readFile(receiptPath)),summary_path:summaryPath,summary_sha256:sha(await readFile(summaryPath)),receipt,full_recovery_acceptance:false};const resultPath=resolve(out,'RESULT.json');await savePrivate(resultPath,result);
   return {stage:mode,result_path:resultPath,result_sha256:sha(await readFile(resultPath)),tables:receipt.tables,rows:receipt.rows,archive_sha256:receipt.archive_sha256,full_recovery_acceptance:false};
  }finally{response?.body.fill(0);}
 }catch(error){if(out)await savePrivate(resolve(out,'FAILED.json'),{stage:mode,code:error instanceof ArchiveError?error.code:'ARCHIVE_UNCONFIRMED',automatic_retry:false,preserve_partial:true});throw error;}
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href)run(process.argv.slice(2)).then(r=>process.stdout.write(JSON.stringify(r)+'\n')).catch(()=>{process.stderr.write('Archive operation refused or unconfirmed; preserve partial files/database; no automatic retry.\n');process.exitCode=1;});
