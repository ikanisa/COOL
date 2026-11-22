// Private-pipe child for the separately reviewed encrypted-image supervisor.
// Raw archive cells, credentials, keys and paths never go to routine output.
import {constants,fstatSync} from 'node:fs';
import {chmod,lstat,mkdir,open,readFile,realpath,writeFile} from 'node:fs/promises';
import {dirname,isAbsolute,join,relative,resolve,sep} from 'node:path';
import {randomUUID,createHash} from 'node:crypto';
import pg from '../../node_modules/pg/lib/index.js';
import {canonical,sha,PROJECT,HARD_CAPS} from '../../current-archive/codec.mjs';
import {readPrivateFile,privateDirectory,readEncryptedBundle,writeEncryptedBundle} from '../../current-archive/bundle.mjs';
import {restoreInertArchive} from '../../current-archive/restore.mjs';

const exact=(o,keys)=>o&&typeof o==='object'&&!Array.isArray(o)&&Object.keys(o).sort().join('\0')===[...keys].sort().join('\0');
const need=v=>{if(!v)throw Error('restore_unconfirmed');};
const HASH=/^[a-f0-9]{64}$/;
const inside=(p,base)=>{const r=relative(base,p);return r===''||r!=='..'&&!r.startsWith('..'+sep)&&!isAbsolute(r);};
const pathExact=p=>typeof p==='string'&&isAbsolute(p)&&resolve(p)===p&&p.length<=4096&&!p.includes('\0');
async function privateJson(path,pin,maximum=256*1024){
 need(pathExact(path)&&HASH.test(pin??''));const raw=await readPrivateFile(path,maximum);
 try{need(sha(raw)===pin);return JSON.parse(new TextDecoder('utf8',{fatal:true}).decode(raw));}finally{raw.fill(0);}
}
async function safeJson(path,value){
 const f=await open(path,constants.O_CREAT|constants.O_EXCL|constants.O_WRONLY|constants.O_NOFOLLOW,0o600);
 try{await f.writeFile(JSON.stringify(value,null,2)+'\n');await f.sync();}finally{await f.close();}
 const d=await open(dirname(path),constants.O_RDONLY|constants.O_NOFOLLOW);try{await d.sync();}finally{await d.close();}
}
async function ciphertextToImage(source,destination,expectedSize,expectedHash){
 need(pathExact(source)&&Number.isSafeInteger(expectedSize)&&expectedSize>0&&expectedSize<=Math.ceil(HARD_CAPS.serializedBytes*4/3)+65536&&HASH.test(expectedHash));
 await privateDirectory(dirname(source));need(await realpath(source)===source);
 const input=await open(source,constants.O_RDONLY|constants.O_NOFOLLOW|constants.O_NONBLOCK);
 let output,buffer=Buffer.alloc(65536);
 try{
  const before=await input.stat();
  const valid=s=>s.isFile()&&s.nlink===1&&s.uid===process.getuid()&&[0o600,0o700].includes(s.mode&0o777)&&s.size===expectedSize;
  need(valid(before));
  output=await open(destination,constants.O_CREAT|constants.O_EXCL|constants.O_WRONLY|constants.O_NOFOLLOW,0o600);
  const digest=createHash('sha256');let offset=0;
  while(offset<expectedSize){
   const {bytesRead}=await input.read(buffer,0,Math.min(buffer.length,expectedSize-offset),offset);need(bytesRead>0);
   digest.update(buffer.subarray(0,bytesRead));let written=0;
   while(written<bytesRead){const w=await output.write(buffer,written,bytesRead-written,offset+written);need(w.bytesWritten>0);written+=w.bytesWritten;}
   offset+=bytesRead;
  }
  const extra=await input.read(buffer,0,1,expectedSize),after=await input.stat(),pathState=await lstat(source);
  const same=s=>valid(s)&&s.dev===before.dev&&s.ino===before.ino&&s.mtimeMs===before.mtimeMs&&s.ctimeMs===before.ctimeMs;
  need(extra.bytesRead===0&&same(after)&&same(pathState)&&await realpath(source)===source&&digest.digest('hex')===expectedHash);
  await output.sync();const d=await open(dirname(destination),constants.O_RDONLY|constants.O_NOFOLLOW);try{await d.sync();}finally{await d.close();}
 }finally{buffer.fill(0);await input.close();await output?.close();}
}

// Synthetic fixture generation has no provider, archive or credential input.
async function syntheticCapture(mount,tamper){
 const {snapshot}=await import('../../current-archive/fixtures.mjs');
 const {preparePlanCandidate,compileCaptureRequest,assembleManagementSnapshot}=await import('../../current-archive/capture.mjs');
 const old=snapshot();need(old.fixture===true&&sha(canonical(old))==='3575b6a1ef612c9f0e6fde1794cfe1fb39911bf7d98b5b796acf0da0bf693ab9');
 const requestId='00000000-0000-4000-8000-000000000001',fixtureDatabase='collect_archive_source_'+('1'.repeat(32))+'_test';
 const postgres={...old.postgres,database:fixtureDatabase,backend_pid:'1',row_security:'off',application_name:'collect.archive.'+requestId.replaceAll('-','')};delete postgres.rolled_back;
 const metadata={format:'collect.mgmt.metadata.v1',postgres,relations:old.tables.map((t,i)=>({schema:t.schema,name:t.name,kind:t.kind,oid:String(i+1),columns_record:canonical(t.columns)})),
  migrations:old.migrations.map(({sha256,...m})=>m),catalog_record:canonical(old.catalog),sequences_record:'[]'};
 const sourceMigrations=old.migrations.map(({observed_record,observed_record_sha256,...m})=>m);
 const plan=preparePlanCandidate(metadata,{runtimeSourceSha256:old.runtime_source_sha256,sourceMigrations,expectedMigrationCount:8,fixtureDatabase});
 const compiled=compileCaptureRequest(plan,{requestId});
 const tables=old.tables.map((t,i)=>{const cells=t.rows.map(r=>r.cells),lengths=cells.flat().filter(v=>v!==null).map(v=>Buffer.byteLength(v));
  return {schema:t.schema,name:t.name,kind:t.kind,oid:String(i+1),columns_record:canonical(t.columns),
   measure:{index:i,rows:String(cells.length),bytes:String(lengths.reduce((a,b)=>a+b,0)),max_cell:String(Math.max(0,...lengths))},cells};});
 const payload={format:'collect.mgmt.data.v1',postgres,tables,migrations:metadata.migrations,catalog_record:metadata.catalog_record,sequences:[]};
 const snapshotValue=assembleManagementSnapshot({status:201,body:Buffer.from(JSON.stringify([{kind:'capture',payload:JSON.stringify(payload)}]))},plan,compiled);
 need(snapshotValue.fixture===true&&snapshotValue.restore_authority===false);
 const archiveDir=join(mount,'fixture-archive'),keyDir=join(mount,'fixture-key'),metaDir=join(mount,'fixture-meta');
 for(const dir of [archiveDir,keyDir,metaDir])await mkdir(dir,{mode:0o700});
 const receipt=await writeEncryptedBundle(snapshotValue,{archiveDirectory:archiveDir,keyDirectory:keyDir});
 const receiptPath=join(metaDir,'receipt.json'),summaryPath=join(metaDir,'summary.json'),resultPath=join(metaDir,'result.json');
 await safeJson(receiptPath,receipt);
 const snapshotHash=sha(canonical(snapshotValue));
 const summary={source_snapshot_sha256:snapshotHash,runtime_source_sha256:snapshotValue.runtime_source_sha256};await safeJson(summaryPath,summary);
 const result={format:'collect.current-archive.capture.v1',project_ref:PROJECT,fixture:true,runtime_source_sha256:snapshotValue.runtime_source_sha256,
  source_snapshot_sha256:tamper==='snapshot'?'0'.repeat(64):snapshotHash,receipt_path:receiptPath,receipt_sha256:sha(await readFile(receiptPath)),
  summary_path:summaryPath,summary_sha256:sha(await readFile(summaryPath)),receipt,full_recovery_acceptance:false};
 // Keep summary and claimed source snapshot consistent so the snapshot itself
 // catches this synthetic mismatch after authenticated decryption.
 if(tamper==='snapshot'){summary.source_snapshot_sha256=result.source_snapshot_sha256;await writeFile(summaryPath,JSON.stringify(summary,null,2)+'\n');result.summary_sha256=sha(await readFile(summaryPath));}
 await safeJson(resultPath,result);const resultSha=sha(await readFile(resultPath));
 if(tamper==='result')await writeFile(resultPath,'{}\n');
 if(tamper==='receipt')await writeFile(receiptPath,'{}\n');
 if(tamper==='ciphertext')await writeFile(receipt.archive_path,Buffer.alloc(receipt.archive_bytes,0x61));
 if(tamper==='key')await writeFile(receipt.key_path,Buffer.alloc(32,0x31));
 // Simulate the owner's 0700 ciphertext file on a filesystem that cannot
 // represent the archive reader's required 0600 mode.
 await chmod(receipt.archive_path,0o700);
 return {resultPath,resultSha,copyPath:receipt.archive_path};
}

let raw,stage='input';
try{
 const input=fstatSync(0);need(process.argv.length===2&&!process.stdin.isTTY&&(input.isFIFO()||input.isSocket()));
 const chunks=[];let size=0;for await(const chunk of process.stdin){size+=chunk.length;if(size>16384){chunk.fill(0);for(const c of chunks)c.fill(0);throw Error('input_limit');}chunks.push(chunk);}
 raw=Buffer.concat(chunks,size);for(const c of chunks)c.fill(0);need(raw.length>0);
 const v=JSON.parse(raw.toString('utf8'));
 need(exact(v,['port','password','data','cluster','mode','resultPath','resultSha','copyPath','tamper','pause'])&&
  Number.isSafeInteger(v.port)&&v.port>=1024&&v.port<=65535&&/^[a-f0-9]{64}$/.test(v.password??'')&&
  /^collect_inert_[a-f0-9]{24}$/.test(v.cluster??'')&&typeof v.data==='string'&&v.data.startsWith('/private/tmp/collect-encrypted-archive-')&&v.data.endsWith('/mount/data')&&
  ['synthetic','real'].includes(v.mode)&&['','result','receipt','ciphertext','key','snapshot'].includes(v.tamper)&&['','after_snapshot'].includes(v.pause));
 if(v.mode==='real')need(pathExact(v.resultPath)&&HASH.test(v.resultSha??'')&&pathExact(v.copyPath)&&v.tamper===''&&v.pause==='');
 else need(v.resultPath===null&&v.resultSha===null&&v.copyPath===null);
 const mount=dirname(v.data),root=dirname(mount);need(await realpath(mount)===mount&&(await lstat(mount)).dev!==(await lstat(root)).dev);
 const target='collect_archive_'+randomUUID().replaceAll('-','')+'_test';let systemId=null;
 const adminUrl=`postgres://collect_inert_fixture:${v.password}@127.0.0.1:${v.port}/postgres`;
 const makeClient=connectionString=>{
  const u=new URL(connectionString);need(u.protocol==='postgres:'&&u.hostname==='127.0.0.1'&&Number(u.port)===v.port&&u.username==='collect_inert_fixture'&&
   u.password===v.password&&['/postgres','/'+target].includes(u.pathname)&&!u.search&&!u.hash);
  const c=new pg.Client({connectionString,ssl:false,connectionTimeoutMillis:5000,statement_timeout:30000,application_name:'collect_encrypted_archive_restore'});
  c.on('error',()=>{});const connect=c.connect.bind(c);
  c.connect=async()=>{await connect();try{
   const {rows}=await c.query("SELECT current_database()::text AS db,current_user::text AS usr,pg_catalog.host(pg_catalog.inet_server_addr()) AS address,pg_catalog.inet_server_port() AS port,current_setting('data_directory') AS data,current_setting('cluster_name') AS cluster,(SELECT system_identifier::text FROM pg_catalog.pg_control_system()) AS system_id");
   need(rows.length===1&&rows[0].db===u.pathname.slice(1)&&rows[0].usr==='collect_inert_fixture'&&rows[0].address==='127.0.0.1'&&rows[0].port===v.port&&
    rows[0].data===v.data&&rows[0].cluster===v.cluster&&/^\d{1,20}$/.test(rows[0].system_id??''));
   if(systemId===null)systemId=rows[0].system_id;else need(systemId===rows[0].system_id);
  }catch(e){await c.end().catch(()=>{});throw e;}};return c;
 };
 stage='cluster';const probe=makeClient(adminUrl);await probe.connect();await probe.end();
 stage='capture';const selection=v.mode==='synthetic'?await syntheticCapture(mount,v.tamper):{resultPath:v.resultPath,resultSha:v.resultSha,copyPath:v.copyPath};
 if(v.mode==='real')need(!inside(selection.resultPath,mount)&&!inside(selection.copyPath,mount));
 const result=await privateJson(selection.resultPath,selection.resultSha);
 need(exact(result,['format','project_ref','fixture','runtime_source_sha256','source_snapshot_sha256','receipt_path','receipt_sha256','summary_path','summary_sha256','receipt','full_recovery_acceptance'])&&
  result.format==='collect.current-archive.capture.v1'&&result.project_ref===PROJECT&&result.fixture===(v.mode==='synthetic')&&
  HASH.test(result.runtime_source_sha256??'')&&HASH.test(result.source_snapshot_sha256??'')&&result.full_recovery_acceptance===false);
 const receipt=await privateJson(result.receipt_path,result.receipt_sha256),summary=await privateJson(result.summary_path,result.summary_sha256);
 need(canonical(receipt)===canonical(result.receipt)&&receipt.format==='collect.sql-archive.write-receipt.v1'&&receipt.authenticated_readback===true&&
  receipt.full_recovery_acceptance===false&&receipt.production_restore_authority===false&&HASH.test(receipt.archive_sha256??'')&&
  pathExact(receipt.archive_path)&&pathExact(receipt.key_path)&&pathExact(selection.copyPath)&&
  summary.runtime_source_sha256===result.runtime_source_sha256&&summary.source_snapshot_sha256===result.source_snapshot_sha256);
 need(!inside(receipt.key_path,dirname(receipt.archive_path))&&!inside(receipt.archive_path,dirname(receipt.key_path))&&
  !inside(receipt.key_path,dirname(selection.copyPath))&&!inside(selection.copyPath,dirname(receipt.key_path)));
 if(v.mode==='real')need(!inside(receipt.key_path,mount));
 stage='ciphertext';const stageDir=join(mount,'staged-ciphertext');await mkdir(stageDir,{mode:0o700});const stagePath=join(stageDir,'capture.archive.json');
 await ciphertextToImage(selection.copyPath,stagePath,receipt.archive_bytes,receipt.archive_sha256);
 stage='authentication';const {snapshot:captured}=await readEncryptedBundle({archivePath:stagePath,keyPath:receipt.key_path,expectedArchiveSha256:receipt.archive_sha256});
 need(captured.project_ref===PROJECT&&captured.fixture===(v.mode==='synthetic')&&captured.restore_authority===false&&
  captured.runtime_source_sha256===result.runtime_source_sha256&&sha(canonical(captured))===result.source_snapshot_sha256&&
  receipt.tables===captured.tables.length&&receipt.rows===captured.tables.reduce((n,t)=>n+t.rows.length,0));
 if(v.mode==='synthetic'&&v.pause==='after_snapshot'){
  process.stderr.write('COLLECT_SYNTHETIC_CAPTURE_AUTHENTICATED\n');await new Promise(()=>{setInterval(()=>{},1000);});
 }
 stage='restore';const restored=await restoreInertArchive(captured,{adminUrl,makeClient,databaseName:target});
 need(restored.created_new_database===true&&restored.inert_data_only===true&&restored.columns_and_native_cells_exact===true&&
  restored.production_restore_authority===false&&restored.full_recovery_acceptance===false&&restored.tables.length===receipt.tables&&
  restored.tables.reduce((n,t)=>n+t.rows,0)===receipt.rows);
 process.stdout.write(JSON.stringify({format:'collect.encrypted-capture.inert-restore.v1',status:'verified',mode:v.mode,
  capture_result_sha256:selection.resultSha,tables:receipt.tables,rows:receipt.rows,native_cells_verified:true,
  production_restore_authority:false,whole_system_recovery:false})+'\n');
}catch{process.stderr.write('ENCRYPTED_INERT_RESTORE_REFUSED:'+stage+'\n');process.exitCode=1;}
finally{raw?.fill(0);}
