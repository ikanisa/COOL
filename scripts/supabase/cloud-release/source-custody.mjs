// Point-in-time, encrypted custody copy of the existing application database.
// Application writers are stopped; this preserves all original source rows.
// Ciphertext readback/decryption and archive TOC are checked; no restore claim.
import {execFileSync,spawnSync} from 'node:child_process';
import {createHash,randomUUID} from 'node:crypto';
import {closeSync,fsyncSync,lstatSync,mkdirSync,openSync,readFileSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {sealDatabase,openDatabase} from '/Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-16/burimunsi-cloud-preflight-001/object-custody-code-001/binary-codec.mjs';

const PROJECT='rrlduytparvsjfmegalh',DOCKER='/Applications/Docker.app/Contents/Resources/bin/docker';
const CUSTODY='/Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-16/burimunsi-cloud-preflight-001/object-custody-cloud-001/result.json';
const ROOT='/Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-17/burimunsi-live-cutover-001/source-final-custody';
const mode=process.argv[2];if(!['--dry-run','--create'].includes(mode)||process.argv.length!==3)throw Error('invalid_mode');
const sha=b=>createHash('sha256').update(b).digest('hex');
const need=(ok,code)=>{if(!ok){const e=Error(code);e.code=code;throw e;}};
const docker=(args,opts={})=>execFileSync(DOCKER,['--context','colima-supabase-local',...args],{maxBuffer:46_000_000,timeout:120000,...opts});
function privateFile(path){const s=lstatSync(path);need(s.isFile()&&!s.isSymbolicLink()&&s.uid===process.getuid()&&(s.mode&0o777)===0o600&&s.nlink===1&&s.size<=8192,'private_input_invalid');return readFileSync(path);}
function durable(name,value){const fd=openSync(join(ROOT,name),'wx',0o600);try{writeFileSync(fd,JSON.stringify(value)+'\n');fsyncSync(fd);}finally{closeSync(fd);}const d=openSync(ROOT,'r');try{fsyncSync(d);}finally{closeSync(d);}}
function env(){const source=JSON.parse(docker(['inspect','supabase_edge_runtime_local-app'],{encoding:'utf8'}))[0];return Object.fromEntries(source.Config.Env.map(x=>{const i=x.indexOf('=');return[x.slice(0,i),x.slice(i+1)]}));}
function toc(bytes){
 // pg_restore --list can stop reading a custom archive after its table of
 // contents. Docker then closes stdin early; accept EPIPE only with an actual
 // successful child exit and the required independent TOC content below.
 const result=spawnSync(DOCKER,['--context','colima-supabase-local','exec','-i','supabase_db_local-app','pg_restore','--list'],{input:bytes,maxBuffer:10_000_000,timeout:30000});
 need(result.status===0&&!result.signal&&(!result.error||result.error.code==='EPIPE')&&result.stderr?.length===0,'database_toc_unconfirmed');const out=result.stdout;
 const text=out.toString('utf8');need(text.includes('TABLE DATA app payments ')&&text.includes('TABLE DATA private burimunsi_accounts '),'database_contents_unconfirmed');
 return text.split('\n').filter(line=>line.includes(' TABLE DATA ')).length;
}
async function request(url,options={}){
 need(url.startsWith('https://api.supabase.com/v1/projects/'+PROJECT+'/')||url.startsWith('https://'+PROJECT+'.supabase.co/storage/v1/'),'endpoint_invalid');
 const response=await fetch(url,{...options,redirect:'error',signal:AbortSignal.timeout(120000)});const reader=response.body?.getReader(),chunks=[];let size=0;
 if(reader)try{for(;;){const p=await reader.read();if(p.done)break;size+=p.value.length;need(size<=46_000_000,'response_too_large');chunks.push(Buffer.from(p.value));}}finally{reader.releaseLock();}
 return {status:response.status,body:Buffer.concat(chunks)};
}
async function main(){
 const running=docker(['ps','--format','{{.Names}}'],{encoding:'utf8'}).trim().split('\n').filter(n=>n.startsWith('supabase_')&&n.endsWith('_local-app'));
 need(running.length===1&&running[0]==='supabase_db_local-app','source_writers_must_be_stopped');
 const fence=JSON.parse(docker(['exec','supabase_db_local-app','psql','-X','-qAt','-U','postgres','-d','postgres','-c',"select to_jsonb(mode) from private.collect_fence_control where singleton"],{encoding:'utf8'}));
 need(fence==='quiescing','source_quiesce_required');
 const custody=JSON.parse(privateFile(CUSTODY).toString());
 need(custody.status==='encrypted_object_custody_verified'&&custody.project===PROJECT&&/^collect-evidence-custody-[a-f0-9]{12}$/.test(custody.bucket??''),'custody_bucket_invalid');
 const settings=env(),key=Buffer.from(settings.DATA_ENCRYPTION_KEY??'','base64');
 try{
  need(key.length===32&&key.toString('base64')===settings.DATA_ENCRYPTION_KEY&&/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/.test(settings.DATA_KEY_ID??''),'source_key_invalid');
  const operationId=randomUUID(),startedAt=new Date().toISOString();
  const dump=docker(['exec','supabase_db_local-app','pg_dump','--username','postgres','--format','custom','--lock-wait-timeout=5s','postgres']);
  try{
   need(dump.length>5&&dump.subarray(0,5).toString()==='PGDMP','source_dump_invalid');const tables=toc(dump),completedAt=new Date().toISOString();
   const archive=sealDatabase(dump,key,{project:PROJECT,operationId,keyId:settings.DATA_KEY_ID}),originalSha=sha(dump);
   const reopened=openDatabase(archive,key);try{need(sha(reopened.plaintext)===originalSha&&toc(reopened.plaintext)===tables,'archive_verification_failed');}finally{reopened.plaintext.fill(0);}
   dump.fill(0);
   const token=execFileSync('/usr/bin/security',['find-generic-password','-s','Supabase CLI','-a','supabase','-w'],{encoding:'utf8'}).trim();
   const management='https://api.supabase.com/v1/projects/'+PROJECT+'/',auth={Authorization:'Bearer '+token};
   const secretResponse=await request(management+'secrets',{headers:auth});need(secretResponse.status===200,'secret_read_failed');
   const ring=JSON.stringify({[settings.DATA_KEY_ID]:settings.DATA_ENCRYPTION_KEY});
   need(JSON.parse(secretResponse.body.toString()).find(x=>x.name==='DATA_DECRYPTION_KEYS_JSON')?.value===sha(ring),'cloud_decryption_key_changed');
   const sql="select count(*)::int as n from storage.objects where bucket_id='"+custody.bucket+"' and name like 'source-db/"+operationId+"/%'";
   const probe=await request(management+'database/query',{method:'POST',headers:{...auth,'Content-Type':'application/json'},body:JSON.stringify({query:sql,read_only:true})});
   need(probe.status===201&&JSON.parse(probe.body.toString())?.[0]?.n===0,'target_prefix_not_empty');
   const keyResult=await request(management+'api-keys?reveal=true',{headers:auth});need(keyResult.status===200,'credential_unavailable');
   const candidates=JSON.parse(keyResult.body.toString()).filter(x=>x.name==='service_role'&&x.type==='legacy');need(candidates.length===1&&typeof candidates[0].api_key==='string','credential_unavailable');
   const serviceKey=candidates[0].api_key,headers={apikey:serviceKey,Authorization:'Bearer '+serviceKey},origin='https://'+PROJECT+'.supabase.co/storage/v1/';
   const inspect=async()=>{const r=await request(origin+'bucket/'+custody.bucket,{headers});const b=JSON.parse(r.body.toString());need(r.status===200&&b.id===custody.bucket&&b.public===false,'private_bucket_unconfirmed');};await inspect();
   need(archive.length<50*1024*1024,'archive_exceeds_cloud_limit');
   if(mode==='--dry-run'){console.log(JSON.stringify({status:'read_only_preflight_passed',archiveBytes:archive.length,tableDataEntries:tables,network_writes:0}));return;}
   mkdirSync(ROOT,{mode:0o700});
   const name='source-database-'+operationId+'.enc',path=[custody.bucket,'source-db',operationId,name].map(encodeURIComponent).join('/');
   durable('intent.json',{project:PROJECT,operationId,bucket:custody.bucket,object:'source-db/'+operationId+'/'+name,startedAt,completedAt,archiveBytes:archive.length,archiveSha256:sha(archive),tableDataEntries:tables,keyIncluded:false,sourceQuiesced:true});
   durable('attempt.json',{attempted:true,at:new Date().toISOString()});
   const put=await request(origin+'object/'+path,{method:'POST',headers:{...headers,'Content-Type':'application/octet-stream','x-upsert':'false'},body:archive});
   need([200,201].includes(put.status),'upload_unconfirmed');
   const readback=await request(origin+'object/authenticated/'+path,{headers});need(readback.status===200&&readback.body.equals(archive),'readback_unconfirmed');
   const confirmed=openDatabase(readback.body,key);try{need(confirmed.header.operationId===operationId&&sha(confirmed.plaintext)===originalSha&&toc(confirmed.plaintext)===tables,'cloud_archive_verification_failed');}finally{confirmed.plaintext.fill(0);}
   await inspect();durable('result.json',{status:'encrypted_source_database_custody_verified',project:PROJECT,operationId,bucket:custody.bucket,object:'source-db/'+operationId+'/'+name,archiveSha256:sha(archive),tableDataEntries:tables,readbackMatches:true,archiveDecrypts:true,tableOfContentsReadable:true,restoreTested:false,crossServiceSnapshot:false,at:new Date().toISOString()});
   console.log(JSON.stringify({status:'encrypted_source_database_custody_verified',archiveBytes:archive.length,tableDataEntries:tables,readbackMatches:true,archiveDecrypts:true,restoreTested:false}));
  }finally{dump.fill(0);}
 }finally{key.fill(0);}
}
try{await main();}catch(error){try{durable('failure.json',{status:'unconfirmed_do_not_retry',code:error?.code??'operation_failed',at:new Date().toISOString()});}catch{}console.log(JSON.stringify({status:mode==='--dry-run'?'read_only_preflight_failed_no_writes':'unconfirmed_or_refused_do_not_retry',code:error?.code??'operation_failed'}));process.exitCode=1;}
