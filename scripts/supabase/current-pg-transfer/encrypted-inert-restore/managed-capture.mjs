// Private-pipe child; outputs only aggregate, non-secret qualification evidence.
import {constants,fstatSync} from 'node:fs';
import {chmod,lstat,mkdir,open,readFile,realpath,writeFile} from 'node:fs/promises';
import {dirname,isAbsolute,join,relative,resolve,sep} from 'node:path';
import {createHash} from 'node:crypto';
import pg from '../../node_modules/pg/lib/index.js';
import {canonical,sha,PROJECT} from '../../current-archive/codec.mjs';
import {readPrivateFile,privateDirectory} from '../../current-archive/bundle.mjs';

const exact=(o,keys)=>o&&typeof o==='object'&&!Array.isArray(o)&&Object.keys(o).sort().join('\0')===[...keys].sort().join('\0');
const need=v=>{if(!v)throw Error('restore_unconfirmed');};
const HASH=/^[a-f0-9]{64}$/;
const inside=(p,base)=>{const r=relative(base,p);return r===''||r!=='..'&&!r.startsWith('..'+sep)&&!isAbsolute(r);};
const pathExact=p=>typeof p==='string'&&isAbsolute(p)&&resolve(p)===p&&p.length<=4096&&!p.includes('\0');
async function privateJson(path,pin){
 need(pathExact(path)&&HASH.test(pin??''));const raw=await readPrivateFile(path,256*1024);
 try{need(sha(raw)===pin);return JSON.parse(new TextDecoder('utf8',{fatal:true}).decode(raw));}finally{raw.fill(0);}
}
async function safeJson(path,value){
 const f=await open(path,constants.O_CREAT|constants.O_EXCL|constants.O_WRONLY|constants.O_NOFOLLOW,0o600);
 try{await f.writeFile(JSON.stringify(value,null,2)+'\n');await f.sync();}finally{await f.close();}
 const d=await open(dirname(path),constants.O_RDONLY|constants.O_NOFOLLOW);try{await d.sync();}finally{await d.close();}
}
async function ciphertextToImage(source,destination,expectedSize,expectedHash,maxSize){
 need(pathExact(source)&&Number.isSafeInteger(expectedSize)&&expectedSize>0&&expectedSize<=maxSize&&HASH.test(expectedHash));
 await privateDirectory(dirname(source));need(await realpath(source)===source);
 const input=await open(source,constants.O_RDONLY|constants.O_NOFOLLOW|constants.O_NONBLOCK);let output,buffer=Buffer.alloc(65536);
 try{
  const before=await input.stat();
  const valid=s=>s.isFile()&&s.nlink===1&&s.uid===process.getuid()&&[0o600,0o700].includes(s.mode&0o777)&&s.size===expectedSize;
  need(valid(before));output=await open(destination,constants.O_CREAT|constants.O_EXCL|constants.O_WRONLY|constants.O_NOFOLLOW,0o600);
  const digest=createHash('sha256');let offset=0;
  while(offset<expectedSize){
   const {bytesRead}=await input.read(buffer,0,Math.min(buffer.length,expectedSize-offset),offset);need(bytesRead>0);digest.update(buffer.subarray(0,bytesRead));
   let written=0;while(written<bytesRead){const w=await output.write(buffer,written,bytesRead-written,offset+written);need(w.bytesWritten>0);written+=w.bytesWritten;}offset+=bytesRead;
  }
  const extra=await input.read(buffer,0,1,expectedSize),after=await input.stat(),pathState=await lstat(source);
  const same=s=>valid(s)&&s.dev===before.dev&&s.ino===before.ino&&s.mtimeMs===before.mtimeMs&&s.ctimeMs===before.ctimeMs;
  need(extra.bytesRead===0&&same(after)&&same(pathState)&&await realpath(source)===source&&digest.digest('hex')===expectedHash);
  await output.sync();const d=await open(dirname(destination),constants.O_RDONLY|constants.O_NOFOLLOW);try{await d.sync();}finally{await d.close();}
 }finally{buffer.fill(0);await input.close();await output?.close();}
}

async function componentApi(component){
 if(component==='auth'){
  const api=await import('../../managed-auth-archive/auth.mjs');
  return {api,format:'collect.managed-auth.encrypted-write-receipt.v1',scope:'managed-auth-inert-recovery-data-only',tables:27,
   read:api.readAuthBundle,write:api.writeAuthBundle,restore:api.restoreAuthInert,seal:api.sealAuthTable,
   reference:(await import('../../managed-auth-archive/REFERENCE.json',{with:{type:'json'}})).default,
   fixture:await import('../../managed-auth-archive/native-definition.mjs'),caps:(await import('../../managed-auth-archive/counts.mjs')).CAPS};
 }
 need(component==='storage');const api=await import('../../managed-storage-archive-v2/storage.mjs');
 return {api,format:'collect.managed-storage.metadata.encrypted-write-receipt.v1',scope:'managed-storage-metadata-inert-recovery-data-only',tables:10,
  read:api.readStorageMetadataBundle,write:api.writeStorageMetadataBundle,restore:api.restoreStorageMetadataInert,seal:api.sealStorageMetadataTable,
  reference:(await import('../../managed-storage-archive-v2/REFERENCE.json',{with:{type:'json'}})).default,
  fixture:await import('../../managed-storage-archive-v2/native-definition.mjs'),caps:api.CAPS};
}
async function syntheticCapture(mount,tamper,component,c){
 // Only generated values: library writers reject fixture=true, so this mock
 // uses the ordinary receipt/envelope format and is never accepted as real input.
 const snapshot=c.fixture.syntheticSnapshot(),reference=c.reference;
 snapshot.fixture=false;snapshot.reference=reference;snapshot.reference_sha256=sha(canonical(reference));snapshot.postgres.database='postgres';
 const target=component==='auth'?'users':'objects';const relation=reference.relations.find(t=>t.name===target);
 const columns=reference.columns.filter(x=>x.relation_oid===relation.oid);
 // Synthetic values represent native PostgreSQL text output; JSONB inserts
 // normalize whitespace, so use the corresponding native rendering.
 const cells=columns.map(col=>col.type_oid==='3802'?'{"a": 1, "b": 2}':c.fixture.syntheticValue(reference,col,0));
 snapshot.tables=snapshot.tables.map(t=>c.seal(reference,t.name,t.name===target?[cells]:[]));
 const archiveDir=join(mount,'fixture-archive'),keyDir=join(mount,'fixture-key'),metaDir=join(mount,'fixture-meta');
 for(const d of [archiveDir,keyDir,metaDir])await mkdir(d,{mode:0o700});
 const receipt=await c.write(snapshot,{archiveDirectory:archiveDir,keyDirectory:keyDir});
 const result={...receipt,query_sha256:'a'.repeat(64),counts_preflight_sha256:snapshot.counts_preflight_sha256,
  trailing_rollback_requested:true,native_rollback_command_complete_observed:false,automatic_retry:false};
 if(tamper==='receipt')result.scope='synthetic-invalid-scope';
 if(tamper==='snapshot')result.snapshot_sha256='0'.repeat(64);
 const resultPath=join(metaDir,'RESULT.json');await safeJson(resultPath,result);const resultSha=sha(await readFile(resultPath));
 if(tamper==='result')await writeFile(resultPath,'{}\n');
 if(tamper==='ciphertext')await writeFile(receipt.archive_path,Buffer.alloc(receipt.archive_bytes,0x61));
 if(tamper==='key')await writeFile(receipt.key_path,Buffer.alloc(32,0x31));
 await chmod(receipt.archive_path,0o700);
 return {resultPath,resultSha,copyPath:receipt.archive_path,archiveSha:receipt.archive_sha256,
  snapshotSha:tamper==='snapshot'?result.snapshot_sha256:receipt.snapshot_sha256};
}

let raw,stage='input',synthetic=false;
try{
 const input=fstatSync(0);need(process.argv.length===2&&!process.stdin.isTTY&&(input.isFIFO()||input.isSocket()));
 const chunks=[];let size=0;for await(const chunk of process.stdin){size+=chunk.length;if(size>16384){chunk.fill(0);for(const c of chunks)c.fill(0);throw Error('input_limit');}chunks.push(chunk);}
 raw=Buffer.concat(chunks,size);for(const c of chunks)c.fill(0);need(raw.length>0);const v=JSON.parse(raw.toString('utf8'));
 need(exact(v,['port','password','data','cluster','mode','component','resultPath','resultSha','copyPath','archiveSha','snapshotSha','tamper','pause'])&&
  Number.isSafeInteger(v.port)&&v.port>=1024&&v.port<=65535&&/^[a-f0-9]{64}$/.test(v.password??'')&&
  /^collect_inert_[a-f0-9]{24}$/.test(v.cluster??'')&&typeof v.data==='string'&&v.data.startsWith('/private/tmp/collect-encrypted-managed-')&&v.data.endsWith('/mount/data')&&
  ['auth','storage'].includes(v.component)&&['synthetic','real'].includes(v.mode)&&['','result','receipt','ciphertext','key','snapshot'].includes(v.tamper)&&['','after_snapshot'].includes(v.pause));
 if(v.mode==='real')need(pathExact(v.resultPath)&&pathExact(v.copyPath)&&[v.resultSha,v.archiveSha,v.snapshotSha].every(x=>HASH.test(x??''))&&v.tamper===''&&v.pause==='');
 else need([v.resultPath,v.resultSha,v.copyPath,v.archiveSha,v.snapshotSha].every(x=>x===null));
 synthetic=v.mode==='synthetic';
 const mount=dirname(v.data),root=dirname(mount);need(await realpath(mount)===mount&&(await lstat(mount)).dev!==(await lstat(root)).dev);
 const adminUrl=`postgres://collect_inert_fixture:${v.password}@127.0.0.1:${v.port}/postgres`;
 let systemId=null,targetName=null;const targetPattern=new RegExp('^collect_'+v.component+'_archive_[a-f0-9]{32}_test$');
 const makeClient=connectionString=>{
  const u=new URL(connectionString),db=u.pathname.slice(1);
  need(u.protocol==='postgres:'&&u.hostname==='127.0.0.1'&&Number(u.port)===v.port&&u.username==='collect_inert_fixture'&&u.password===v.password&&
   (db==='postgres'||targetPattern.test(db))&&!u.search&&!u.hash);
  if(db!=='postgres'){if(targetName===null)targetName=db;else need(targetName===db);}
  const c=new pg.Client({connectionString,ssl:false,connectionTimeoutMillis:5000,statement_timeout:30000,application_name:'collect_managed_archive_restore'});
  c.on('error',()=>{});const connect=c.connect.bind(c);
  c.connect=async()=>{await connect();try{
   const {rows}=await c.query("SELECT current_database()::text AS db,current_user::text AS usr,pg_catalog.host(pg_catalog.inet_server_addr()) AS address,pg_catalog.inet_server_port() AS port,current_setting('data_directory') AS data,current_setting('cluster_name') AS cluster,(SELECT system_identifier::text FROM pg_catalog.pg_control_system()) AS system_id");
   need(rows.length===1&&rows[0].db===db&&rows[0].usr==='collect_inert_fixture'&&rows[0].address==='127.0.0.1'&&rows[0].port===v.port&&
    rows[0].data===v.data&&rows[0].cluster===v.cluster&&/^\d{1,20}$/.test(rows[0].system_id??''));
   if(systemId===null)systemId=rows[0].system_id;else need(systemId===rows[0].system_id);
  }catch(e){await c.end().catch(()=>{});throw e;}};return c;
 };
 stage='cluster';const probe=makeClient(adminUrl);await probe.connect();await probe.end();const c=await componentApi(v.component);
 stage='capture';const selection=v.mode==='synthetic'?await syntheticCapture(mount,v.tamper,v.component,c):
  {resultPath:v.resultPath,resultSha:v.resultSha,copyPath:v.copyPath,archiveSha:v.archiveSha,snapshotSha:v.snapshotSha};
 if(v.mode==='real')need(!inside(selection.resultPath,mount)&&!inside(selection.copyPath,mount));
 const receipt=await privateJson(selection.resultPath,selection.resultSha);
 need(receipt&&receipt.format===c.format&&receipt.scope===c.scope&&receipt.project_ref===PROJECT&&receipt.authenticated_readback===true&&
  receipt.full_recovery_acceptance===false&&receipt.archive_sha256===selection.archiveSha&&receipt.snapshot_sha256===selection.snapshotSha&&
  HASH.test(receipt.reference_sha256??'')&&pathExact(receipt.archive_path)&&pathExact(receipt.key_path)&&
  Number.isSafeInteger(receipt.rows)&&receipt.rows>=0&&receipt.rows<=50000&&receipt.tables===c.tables&&
  (v.component==='auth'?receipt.managed_auth_data_included===true&&receipt.storage_included===false&&receipt.operational_auth_restored===false:
   receipt.storage_metadata_included===true&&receipt.object_bodies_included===false&&receipt.auth_data_included===false&&receipt.operational_storage_restored===false));
 need(!inside(receipt.key_path,dirname(receipt.archive_path))&&!inside(receipt.archive_path,dirname(receipt.key_path))&&
  !inside(receipt.key_path,dirname(selection.copyPath))&&!inside(selection.copyPath,dirname(receipt.key_path)));
 if(v.mode==='real')need(!inside(receipt.key_path,mount));
 stage='ciphertext';const stageDir=join(mount,'staged-ciphertext');await mkdir(stageDir,{mode:0o700});const stagePath=join(stageDir,'capture.archive.json');
 await ciphertextToImage(selection.copyPath,stagePath,receipt.archive_bytes,receipt.archive_sha256,Math.ceil(c.caps.plaintextBytes*4/3)+65536);
 stage='authentication';const {header,snapshot}=await c.read({archivePath:stagePath,keyPath:receipt.key_path,expectedArchiveSha256:receipt.archive_sha256});
 need(header.archive_id===receipt.archive_id&&header.key_id===receipt.key_id&&snapshot.project_ref===PROJECT&&snapshot.fixture===false&&
  snapshot.reference_sha256===receipt.reference_sha256&&sha(canonical(snapshot))===receipt.snapshot_sha256&&snapshot.tables.length===receipt.tables&&
  snapshot.tables.reduce((n,t)=>n+t.row_count,0)===receipt.rows);
 if(v.mode==='synthetic'&&v.pause==='after_snapshot'){process.stderr.write('COLLECT_SYNTHETIC_CAPTURE_AUTHENTICATED\n');await new Promise(()=>{setInterval(()=>{},1000);});}
 stage='restore';const restored=await c.restore(snapshot,{adminUrl,makeClient});stage='roundtrip';
 need(restored.created_new_database===true&&restored.columns_and_native_cells_exact===true&&restored.fixture===false&&
  restored.production_restore_authority===false&&restored.full_recovery_acceptance===false&&restored.tables.length===receipt.tables&&
  restored.tables.reduce((n,t)=>n+t.rows,0)===receipt.rows&&
  (v.component==='auth'?restored.operational_auth_restored===false:restored.operational_storage_restored===false&&restored.object_bodies_restored===false));
 process.stdout.write(JSON.stringify({format:'collect.managed-capture.inert-restore.v1',status:'verified',mode:v.mode,component:v.component,
  capture_result_sha256:selection.resultSha,tables:receipt.tables,rows:receipt.rows,native_cells_verified:true,
  production_restore_authority:false,whole_system_recovery:false})+'\n');
}catch(e){const code=synthetic&&/^[A-Z][A-Z0-9_]{0,79}$/.test(e?.code??'')?':'+e.code:'';
 process.stderr.write('ENCRYPTED_INERT_RESTORE_REFUSED:'+stage+code+'\n');process.exitCode=1;}
finally{raw?.fill(0);}
