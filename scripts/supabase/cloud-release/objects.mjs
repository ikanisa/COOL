// Copies immutable, already encrypted object bytes to the selected private
// Supabase application bucket. No source object is changed or removed.
import {execFileSync} from 'node:child_process';
import {createDecipheriv} from 'node:crypto';
import {readFileSync,existsSync} from 'node:fs';
import {management,connect,record,ROOT,PROJECT,sha} from './access.mjs';

const DOCKER='/Applications/Docker.app/Contents/Resources/bin/docker',bucket='collect-evidence';
const docker=(args,opts={})=>execFileSync(DOCKER,['--context','colima-supabase-local',...args],{maxBuffer:12_000_000,timeout:30000,...opts});
const sql=`BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY name),'[]'::jsonb) FROM (
 SELECT s.name,s.version,s.bucket_id,to_jsonb(o) object,to_jsonb(r) reservation,to_jsonb(i) intent
 FROM storage.objects s JOIN private.storage_objects o ON o.object_key=s.name
 JOIN private.storage_payload_reservations r ON r.object_key=s.name
 JOIN private.storage_put_intents i ON i.object_key=s.name) x; ROLLBACK;`;
const rows=JSON.parse(docker(['exec','-i','supabase_db_local-app','psql','-X','-qAt','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],{input:sql,encoding:'utf8'}));
if(rows.length!==48||rows.some(x=>x.bucket_id!==bucket||x.intent.state!=='committed'||x.intent.upload_unresolved||x.intent.active_attempt||x.intent.delete_tombstone||x.reservation.sealed_body!==null))throw Error('source_storage_changed');
const files=docker(['exec','supabase_storage_local-app','find','/mnt','-type','f'],{encoding:'utf8'}).trim().split('\n');
if(files.length!==48)throw Error('source_file_count_changed');
const raw=JSON.parse(docker(['inspect','supabase_edge_runtime_local-app'],{encoding:'utf8'}))[0];
const env=Object.fromEntries(raw.Config.Env.map(x=>{const i=x.indexOf('=');return[x.slice(0,i),x.slice(i+1)];}));
const key=Buffer.from(env.DATA_ENCRYPTION_KEY,'base64');if(key.length!==32)throw Error('source_key_invalid');
const metadata=(await management('secrets')).json();
if(metadata.find(x=>x.name==='DATA_DECRYPTION_KEYS_JSON')?.value!==sha(JSON.stringify({[env.DATA_KEY_ID]:env.DATA_ENCRYPTION_KEY})))throw Error('cloud_historical_key_changed');
const keys=(await management('api-keys?reveal=true')).json();
const credential=keys.find(x=>x.name==='service_role'&&x.type==='legacy')?.api_key;
if(!credential)throw Error('cloud_storage_credential_unavailable');
const headers={apikey:credential,Authorization:'Bearer '+credential};
const origin='https://'+PROJECT+'.supabase.co/storage/v1/';
async function request(path,options={}){
 const r=await fetch(origin+path,{...options,headers:{...headers,...options.headers},redirect:'error',signal:AbortSignal.timeout(30000)});
 const bytes=Buffer.from(await r.arrayBuffer());if(bytes.length>8_000_000)throw Error('oversized_object_response');
 return {status:r.status,bytes,etag:r.headers.get('etag')};
}
const b=await request('bucket/'+bucket);const info=JSON.parse(b.bytes);
if(b.status!==200||info.id!==bucket||info.public!==false)throw Error('private_application_bucket_required');
const c=await connect();try{
 const p=(await c.query("select count(*)::int n from pg_policies where schemaname='storage' and tablename='objects'")).rows[0].n;
 if(p!==0)throw Error('storage_public_policy_changed');
}finally{await c.end();}
const proofs={};
try{
 for(const row of rows){
  if(typeof row.name!=='string'||row.name.length>512||/[\r\n\0]/.test(row.name)||row.name.split('/').some(x=>!x||x==='.'||x==='..'))throw Error('object_key_invalid');
  const paths=files.filter(x=>x.endsWith('/'+row.name+'/'+row.version));if(paths.length!==1)throw Error('object_file_unconfirmed');
  const bytes=docker(['exec','supabase_storage_local-app','cat','--',paths[0]]);
  try{
   if(bytes.length!==Number(row.object.size)||sha(bytes)!==row.object.sha256)throw Error('source_ciphertext_changed');
   const d=JSON.parse(bytes.toString('utf8')),packed=Buffer.from(d.data,'base64');
   if(d.v!==1||d.kid!==env.DATA_KEY_ID||d.kid!==row.reservation.key_id)throw Error('source_encryption_key_mismatch');
   const decrypt=createDecipheriv('aes-256-gcm',key,Buffer.from(d.iv,'base64'));
   decrypt.setAAD(Buffer.from(row.reservation.aad));decrypt.setAuthTag(packed.subarray(-16));
   const plain=Buffer.concat([decrypt.update(packed.subarray(0,-16)),decrypt.final()]);
   try{if(sha(plain)!==row.reservation.plaintext_sha256)throw Error('source_plaintext_mismatch');}finally{plain.fill(0);}
   const path=bucket+'/'+row.name.split('/').map(encodeURIComponent).join('/');
   let read=await request('object/authenticated/'+path);
   if(read.status!==200){
    let absent;try{absent=JSON.parse(read.bytes.toString());}catch{}
    if(!([400,404].includes(read.status)&&['NoSuchKey','not_found'].includes(absent?.code??absent?.error)))throw Error('destination_absence_unconfirmed');
    const journal='object-'+sha(row.name);
    if(existsSync(ROOT+'/'+journal+'-attempt.json'))throw Error('prior_object_attempt_requires_readback');
    record(journal+'-attempt.json',{keySha256:sha(row.name),ciphertextSha256:sha(bytes),size:bytes.length,at:new Date().toISOString()});
    // Do not repeat an uncertain POST. Read back its immutable destination.
    let put;try{put=await request('object/'+path,{method:'POST',headers:{'Content-Type':'application/octet-stream','Cache-Control':'no-store','x-upsert':'false'},body:bytes});}catch{}
    read=await request('object/authenticated/'+path);
    if(read.status!==200||!read.bytes.equals(bytes)||!read.etag)throw Error('object_upload_outcome_unconfirmed');
    record(journal+'-complete.json',{keySha256:sha(row.name),ciphertextSha256:sha(read.bytes),size:read.bytes.length,etag:read.etag,at:new Date().toISOString()});
   }
   if(!read.bytes.equals(bytes)||!read.etag)throw Error('destination_object_conflict');
   proofs[row.name]={sha256:sha(read.bytes),size:read.bytes.length,etag:read.etag};
  }finally{bytes.fill(0);}
 }
 record('verified-application-objects.json',proofs);
 record('application-object-copy-complete.json',{project:PROJECT,bucket,objects:Object.keys(proofs).length,plaintextVerified:true,ciphertextReadbackVerified:true,sourceQuiesced:false,at:new Date().toISOString()});
 console.log(JSON.stringify({status:'private_application_objects_copied_and_verified',objects:Object.keys(proofs).length,sourceQuiesced:false}));
}finally{key.fill(0);}
