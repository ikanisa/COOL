// One-use encrypted custody of the FINAL fenced source and migration key.
// Source data and credentials remain in process memory; no DB mutations.
// Both provider writes have exclusive, durable intent and never auto-retry.
import {execFileSync,spawnSync} from 'node:child_process';
import {createHash,randomUUID,timingSafeEqual} from 'node:crypto';
import {closeSync,existsSync,fsyncSync,lstatSync,mkdirSync,openSync,readFileSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {sealDatabase,openDatabase} from '/Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-16/burimunsi-cloud-preflight-001/object-custody-code-001/binary-codec.mjs';
import {sealRecoveryCapsule,openRecoveryCapsule} from './recovery-capsule.mjs';
import {captureLocalSource} from './source-reader.mjs';
import {sourceSnapshotHmac,verifyActorLineage} from './compile.mjs';
import {connect,management,ROOT as CUTOVER,PROJECT} from '../cloud-release/access.mjs';
import {readSourceEnvironment} from '../cloud-release/source-env.mjs';

const OUTPUT=join(CUTOVER,'source-fenced-custody-002');
const BUCKET_EVIDENCE='/Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-16/burimunsi-cloud-preflight-001/object-custody-cloud-001/result.json';
const DOCKER='/Applications/Docker.app/Contents/Resources/bin/docker';
const EVIDENCE=['graph-import-attempt-002-intent.json','graph-import-attempt-002-result.json','source-fenced-complete.json',
 'source-writers-stopped.json','source-executors-retired.json','source-retirement-recorded.json',
 'source-retained-unknown.json','source-final-custody-result.json'];
const mode=process.argv[2];if(process.argv.length!==3||!['--dry-run','--create'].includes(mode))throw Error('explicit_mode_required');
const need=(ok,code)=>{if(!ok)throw Error(code);};
const sha=b=>createHash('sha256').update(b).digest('hex');
const stable=x=>Array.isArray(x)?'['+x.map(stable).join(',')+']':x&&typeof x==='object'?'{'+Object.keys(x).sort().map(k=>JSON.stringify(k)+':'+stable(x[k])).join(',')+'}':JSON.stringify(x);
const docker=(args,opts={})=>execFileSync(DOCKER,['--context','colima-supabase-local',...args],{maxBuffer:46_000_000,timeout:120000,...opts});
function privateFile(path,maximum=65536){
 const s=lstatSync(path);need(s.isFile()&&!s.isSymbolicLink()&&s.uid===process.getuid()&&(s.mode&0o777)===0o600&&s.nlink===1&&s.size>0&&s.size<=maximum,'private_input_invalid');
 return readFileSync(path);
}
function jsonFile(path,maximum){return JSON.parse(privateFile(path,maximum).toString('utf8'));}
function durable(name,value){
 const fd=openSync(join(OUTPUT,name),'wx',0o600);try{writeFileSync(fd,JSON.stringify(value)+'\n');fsyncSync(fd);}finally{closeSync(fd);}
 const d=openSync(OUTPUT,'r');try{fsyncSync(d);}finally{closeSync(d);}
}
function checkRunning(){
 const names=docker(['ps','--format','{{.Names}}'],{encoding:'utf8'}).trim().split('\n').filter(n=>n.startsWith('supabase_')&&n.endsWith('_local-app'));
 need(names.length===1&&names[0]==='supabase_db_local-app','source_writers_not_stopped');
}
function readFence(){
 const sql=`SELECT jsonb_build_object('control',(SELECT to_jsonb(c) FROM private.collect_fence_control c WHERE singleton),
 'originalCount',(SELECT count(*) FROM private.collect_fence_admissions WHERE state<>'settled'),
 'unmatched',(SELECT count(*) FROM private.collect_fence_admissions a WHERE state<>'settled'
  AND private._collect_stopped_matches(a.admission_id,a.epoch,a.source_sha256,a.kind) IS NOT TRUE))`;
 return JSON.parse(docker(['exec','-i','supabase_db_local-app','psql','-X','-qAt','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],{input:sql,encoding:'utf8'}));
}
function verifyFence(observed,proof){
 need(observed?.control?.mode==='fenced'&&observed.control.project_ref===PROJECT&&observed.unmatched===0&&
  observed.originalCount===proof.originalCount&&proof.retainedUnknown===true&&
  proof.operation===observed.control.operation_id&&stable(observed.control)===stable(proof.control),'source_fence_changed');
}
function toc(bytes,expected){
 const p=spawnSync(DOCKER,['--context','colima-supabase-local','exec','-i','supabase_db_local-app','pg_restore','--list'],
  {input:bytes,maxBuffer:10_000_000,timeout:30000});
 need(p.status===0&&!p.signal&&(!p.error||p.error.code==='EPIPE')&&p.stderr?.length===0,'database_toc_unconfirmed');
 const text=p.stdout.toString('utf8'),required=['TABLE DATA auth users ','TABLE DATA app audit_log ',
  'TABLE DATA app admin_account_audit ','TABLE DATA app payments ','TABLE DATA app ledger_entries ',
  'TABLE DATA private burimunsi_accounts ','TABLE DATA private collect_fence_control ',
  'TABLE DATA private collect_fence_admissions '];
 need(required.every(x=>text.includes(x)),'database_toc_required_history_missing');
 const count=text.split('\n').filter(x=>x.includes(' TABLE DATA ')).length;
 need(count===expected&&count>=262,'database_toc_count_changed');return count;
}
async function storageRequest(path,headers,options={}){
 need(/^(?:bucket|object)\//.test(path)&&!path.includes('..'),'storage_path_invalid');
 const response=await fetch('https://'+PROJECT+'.supabase.co/storage/v1/'+path,
  {...options,headers:{...headers,...options.headers},redirect:'error',signal:AbortSignal.timeout(120000)});
 const reader=response.body?.getReader(),chunks=[];let size=0;
 if(reader)try{for(;;){const x=await reader.read();if(x.done)break;size+=x.value.length;need(size<=46_000_000,'storage_response_too_large');chunks.push(Buffer.from(x.value));}}finally{reader.releaseLock();}
 return {status:response.status,body:Buffer.concat(chunks)};
}
async function bucketCheck(bucket,headers){
 const r=await storageRequest('bucket/'+bucket,headers);let info;try{info=JSON.parse(r.body);}catch{throw Error('private_bucket_unconfirmed');}
 need(r.status===200&&info.id===bucket&&info.public===false,'private_bucket_unconfirmed');
}
function capsuleInput(documents,lineageKey,op){
 return Buffer.from(JSON.stringify({format:'collect.migration-recovery-material.v1',payloadType:'migration-lineage-key-and-cutover-evidence',
  project:PROJECT,custodyOperation:op,lineageKeyBase64:lineageKey.toString('base64'),documents}));
}
async function verifyLineage(client,key,capture,intent){
 need(sourceSnapshotHmac(capture.snapshot,key,intent.operationId)===intent.snapshotHmac,'lineage_snapshot_mismatch');
 const q=await client.query(`SELECT l.source_actor_id,l.cloud_primary_id,l.operation_id::text,l.snapshot_hmac,l.envelope,
  r.snapshot_hmac AS receipt_hmac FROM private.collect_migration_actor_lineage l
  JOIN private.collect_migration_import_receipts r ON r.operation_id=l.operation_id
  WHERE l.operation_id=$1`,[intent.operationId]);
 const v=q.rows[0],user=capture.snapshot.tables['app.users'].find(x=>x.id===capture.sourceOwnerId),
  accounts=capture.snapshot.tables['private.burimunsi_accounts'].filter(x=>x.principal_user_id===capture.sourceOwnerId);
 need(q.rowCount===1&&v.source_actor_id===capture.sourceOwnerId&&v.operation_id===intent.operationId&&
  v.snapshot_hmac===intent.snapshotHmac&&v.receipt_hmac===intent.snapshotHmac&&
  verifyActorLineage({envelope:v.envelope,operationId:intent.operationId,sourceOwnerId:v.source_actor_id,
   cloudPrimaryId:v.cloud_primary_id,custodyKey:key,originalUser:user,originalAccounts:accounts}),'lineage_key_verification_failed');
}
function decodedCapsule(plain,documents,originalKey,op){
 let x;try{x=JSON.parse(plain.toString('utf8'));}catch{throw Error('recovery_material_invalid');}
 need(x.format==='collect.migration-recovery-material.v1'&&x.payloadType==='migration-lineage-key-and-cutover-evidence'&&
  x.project===PROJECT&&x.custodyOperation===op&&stable(x.documents)===stable(documents),'recovery_material_mismatch');
 const recovered=Buffer.from(x.lineageKeyBase64??'','base64');
 need(recovered.length===32&&recovered.toString('base64')===x.lineageKeyBase64&&timingSafeEqual(recovered,originalKey),'recovery_key_mismatch');
 return recovered;
}
async function main(){
 const root=lstatSync(CUTOVER);need(root.isDirectory()&&!root.isSymbolicLink()&&root.uid===process.getuid()&&(root.mode&0o077)===0,'private_directory_required');
 need(!existsSync(OUTPUT),'prior_custody_attempt_requires_reconciliation');
 const documents={};for(const name of EVIDENCE)documents[name]=privateFile(join(CUTOVER,name)).toString('base64');
 const fenceProof=jsonFile(join(CUTOVER,'source-fenced-complete.json')),
  intent=jsonFile(join(CUTOVER,'graph-import-attempt-002-intent.json')),
  result=jsonFile(join(CUTOVER,'graph-import-attempt-002-result.json')),
  oldCustody=jsonFile(join(CUTOVER,'source-final-custody-result.json')),
  custody=jsonFile(BUCKET_EVIDENCE),lineageKey=privateFile(join(CUTOVER,'graph-import-attempt-002-custody-key.bin'),32);
 let oldKey,dump,dbArchive,material,capsule,client;
 try{
  need(lineageKey.length===32&&intent.project===PROJECT&&result.outcome==='committed_and_receipt_read_back'&&
   result.migration===intent.migration&&oldCustody.status==='encrypted_source_database_custody_verified'&&
   Number.isSafeInteger(oldCustody.tableDataEntries)&&custody.status==='encrypted_object_custody_verified'&&custody.project===PROJECT&&
   /^collect-evidence-custody-[a-f0-9]{12}$/.test(custody.bucket??''),'custody_preconditions_unmet');
  checkRunning();const before=readFence();verifyFence(before,fenceProof);
  const capture=captureLocalSource();need(capture.fenceMode==='fenced'&&capture.effectiveActiveAdmissions===0,'source_fence_changed');
  const env=readSourceEnvironment();oldKey=Buffer.from(env.DATA_ENCRYPTION_KEY??'','base64');
  need(oldKey.length===32&&oldKey.toString('base64')===env.DATA_ENCRYPTION_KEY&&
   /^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/.test(env.DATA_KEY_ID??''),'source_data_key_invalid');
  const secrets=(await management('secrets')).json(),ring=JSON.stringify({[env.DATA_KEY_ID]:env.DATA_ENCRYPTION_KEY});
  need(secrets.find(x=>x.name==='DATA_DECRYPTION_KEYS_JSON')?.value===sha(ring),'cloud_historical_key_unconfirmed');
  const credentials=(await management('api-keys?reveal=true')).json().filter(x=>x.name==='service_role'&&x.type==='legacy');
  need(credentials.length===1&&typeof credentials[0].api_key==='string','storage_credential_unavailable');
  const service=credentials[0].api_key,headers={apikey:service,Authorization:'Bearer '+service};
  client=await connect();await verifyLineage(client,lineageKey,capture,intent);
  const policies=(await client.query("SELECT count(*)::int n FROM pg_policies WHERE schemaname='storage' AND tablename='objects'")).rows[0].n;
  need(policies===0,'storage_policy_preimage_changed');await bucketCheck(custody.bucket,headers);
  const op=randomUUID(),prefix='final-fenced-recovery/'+op+'/',dbName='source-database.enc',capsuleName='migration-material.enc';
  const occupied=await client.query('SELECT count(*)::int n FROM storage.objects WHERE bucket_id=$1 AND name LIKE $2',[custody.bucket,prefix+'%']);
  need(occupied.rows[0]?.n===0,'target_recovery_prefix_not_empty');
  dump=docker(['exec','supabase_db_local-app','pg_dump','--username','postgres','--format','custom','--lock-wait-timeout=5s','postgres']);
  need(dump.length>5&&dump.subarray(0,5).toString()==='PGDMP','source_dump_invalid');
  const tables=toc(dump,oldCustody.tableDataEntries),dumpHash=sha(dump);
  dbArchive=sealDatabase(dump,oldKey,{project:PROJECT,operationId:op,keyId:env.DATA_KEY_ID});
  let reopened=openDatabase(dbArchive,oldKey);try{need(reopened.header.operationId===op&&sha(reopened.plaintext)===dumpHash&&
   toc(reopened.plaintext,tables)===tables,'local_database_archive_mismatch');}finally{reopened.plaintext.fill(0);}
  material=capsuleInput(documents,lineageKey,op);capsule=sealRecoveryCapsule(material,oldKey,{project:PROJECT,operationId:op,keyId:env.DATA_KEY_ID});
  let opened=openRecoveryCapsule(capsule,oldKey),recovered;
  try{need(opened.header.operationId===op,'local_recovery_capsule_mismatch');recovered=decodedCapsule(opened.plaintext,documents,lineageKey,op);
   await verifyLineage(client,recovered,capture,intent);}finally{opened.plaintext.fill(0);recovered?.fill(0);}
  checkRunning();verifyFence(readFence(),fenceProof);
  const after=captureLocalSource();need(after.fenceMode==='fenced'&&after.effectiveActiveAdmissions===0&&
   after.sourceOwnerId===capture.sourceOwnerId&&sourceSnapshotHmac(after.snapshot,lineageKey,intent.operationId)===intent.snapshotHmac,'source_snapshot_changed');
  need(dbArchive.length<50*1024*1024,'database_archive_too_large');
  if(mode==='--dry-run'){
   console.log(JSON.stringify({status:'fenced_custody_read_only_preflight_passed',tableDataEntries:tables,databaseBytes:dbArchive.length,
    historicalRingVerified:true,lineageKeyVerified:true,providerWrites:0}));return;
  }
  mkdirSync(OUTPUT,{mode:0o700});
  const parent=openSync(CUTOVER,'r');try{fsyncSync(parent);}finally{closeSync(parent);}
  durable('intent.json',{project:PROJECT,operationId:op,bucket:custody.bucket,prefix,tableDataEntries:tables,
   database:{object:prefix+dbName,sha256:sha(dbArchive),size:dbArchive.length,payloadType:'postgres-custom-database'},
   capsule:{object:prefix+capsuleName,sha256:sha(capsule),size:capsule.length,payloadType:'migration-lineage-key-and-cutover-evidence'},
   originalUnsettledAdmissionsRetained:before.originalCount,createdAt:new Date().toISOString()});
  async function upload(kind,name,bytes,verify){
   durable(kind+'-attempt.json',{attempted:true,at:new Date().toISOString()});
   const path=[custody.bucket,...(prefix+name).split('/')].map(encodeURIComponent).join('/');
   let putStatus=null;try{putStatus=(await storageRequest('object/'+path,headers,{method:'POST',
    headers:{'Content-Type':'application/octet-stream','Cache-Control':'no-store','x-upsert':'false'},body:bytes})).status;}catch{}
   const read=await storageRequest('object/authenticated/'+path,headers);
   need(read.status===200&&read.body.equals(bytes),'provider_upload_readback_unconfirmed');
   await verify(read.body);
   durable(kind+'-verified.json',{readbackMatches:true,decrypts:true,bytes:bytes.length,ciphertextSha256:sha(bytes),
    responseStatus:putStatus,at:new Date().toISOString()});
  }
  await upload('database',dbName,dbArchive,async bytes=>{
   const x=openDatabase(bytes,oldKey);try{need(x.header.project===PROJECT&&x.header.operationId===op&&x.header.keyId===env.DATA_KEY_ID&&
     sha(x.plaintext)===dumpHash&&toc(x.plaintext,tables)===tables,'cloud_database_archive_mismatch');}finally{x.plaintext.fill(0);}
  });
  await upload('capsule',capsuleName,capsule,async bytes=>{
   const x=openRecoveryCapsule(bytes,oldKey);let recovered;
   try{need(x.header.project===PROJECT&&x.header.operationId===op&&x.header.keyId===env.DATA_KEY_ID,'cloud_recovery_capsule_mismatch');
    recovered=decodedCapsule(x.plaintext,documents,lineageKey,op);await verifyLineage(client,recovered,capture,intent);}
   finally{x.plaintext.fill(0);recovered?.fill(0);}
  });
  await bucketCheck(custody.bucket,headers);checkRunning();verifyFence(readFence(),fenceProof);
  durable('result.json',{status:'fenced_source_and_lineage_custody_verified',project:PROJECT,operationId:op,bucket:custody.bucket,prefix,
   tableDataEntries:tables,databaseReadbackMatches:true,databaseDecrypts:true,databaseTocReadable:true,
   capsuleReadbackMatches:true,capsuleDecrypts:true,lineageKeyAuthenticates:true,oldDataKeyInCloudRing:true,
   sourceFenced:true,originalUnsettledAdmissionsRetained:before.originalCount,providerSettlementAsserted:false,
   restoreTested:false,crossServiceSnapshot:false,at:new Date().toISOString()});
  console.log(JSON.stringify({status:'fenced_source_and_lineage_custody_verified',tableDataEntries:tables,
   databaseReadbackMatches:true,capsuleReadbackMatches:true,lineageKeyAuthenticates:true,restoreTested:false}));
 }finally{lineageKey.fill(0);oldKey?.fill(0);dump?.fill(0);dbArchive?.fill(0);material?.fill(0);capsule?.fill(0);await client?.end().catch(()=>{});}
}
try{await main();}catch(error){
 const code=typeof error?.message==='string'&&/^[a-z][a-z0-9_]{1,95}$/.test(error.message)?error.message:
  typeof error?.code==='string'&&/^[A-Z0-9]{4,6}$/.test(error.code)?error.code:'custody_operation_failed';
 if(mode==='--create'&&existsSync(OUTPUT)){try{durable('failure.json',{status:'unconfirmed_do_not_retry',code,at:new Date().toISOString()});}catch{}}
 console.error(JSON.stringify({status:mode==='--dry-run'?'read_only_preflight_failed':'unconfirmed_or_refused_do_not_retry',code}));process.exitCode=1;
}
