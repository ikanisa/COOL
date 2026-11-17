// Read-only point-in-time verification of completed artifact and journal.
import {createHash} from 'node:crypto';
import {constants,closeSync,fstatSync,lstatSync,openSync,readSync,realpathSync} from 'node:fs';
import {join} from 'node:path';
import {readAttempt} from './journal.mjs';
import {readPrivateKey} from './private-input.mjs';
import {cleanManagedEnvironment} from './snapshot.mjs';
import {authenticateAndInspectArchive} from './archive.mjs';
import {openInventory} from './manifest-crypto.mjs';
export class VerifyError extends Error{constructor(code){super(code);this.name='VerifyError';this.code=code;}}
const fail=c=>{throw new VerifyError(c);},sha=b=>createHash('sha256').update(b).digest('hex'),UUID=/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/,HASH=/^[0-9a-f]{64}$/;
function privateDir(path){if(typeof path!=='string'||!path.startsWith('/')||realpathSync(path)!==path)fail('private_root_refused');const s=lstatSync(path);if(!s.isDirectory()||s.isSymbolicLink()||s.uid!==process.getuid()||(s.mode&0o777)!==0o700)fail('private_root_refused');return path;}
function openPrivate(path){const fd=openSync(path,constants.O_RDONLY|(constants.O_NOFOLLOW??0));const s=fstatSync(fd);if(!s.isFile()||s.uid!==process.getuid()||(s.mode&0o777)!==0o600||s.nlink!==1){closeSync(fd);fail('artifact_refused');}return {fd,s};}
function exact(fd,n,pos){const b=Buffer.alloc(n);let done=0;while(done<n){const k=readSync(fd,b,done,n-done,pos+done);if(!k)fail('artifact_refused');done+=k;}return b;}
export async function verifyCompletedBundle(q){
 if(!q||typeof q!=='object'||Object.keys(q).sort().join(',')!=='artifactRoot,expectedPlanSha256,journalRoot,keyPath,mode,operationId'||!['managed','synthetic'].includes(q.mode)||!UUID.test(q.operationId??'')||!HASH.test(q.expectedPlanSha256??'')||typeof q.keyPath!=='string')fail('invalid_input');
 if(q.mode==='managed'&&!cleanManagedEnvironment())fail('managed_environment_refused');privateDir(q.journalRoot);privateDir(q.artifactRoot);
 let key,dump,meta;try{
  const recorded=readAttempt({mode:q.mode,root:q.journalRoot,operationId:q.operationId,planSha256:q.expectedPlanSha256});if(recorded.status!=='completed')fail('completed_receipt_required');
  key=await readPrivateKey({mode:q.mode,path:q.keyPath,signal:null,testHang:false});const base=join(q.artifactRoot,'backup-'+q.operationId);
  dump=openPrivate(base+'.pgc.gcm');meta=openPrivate(base+'.inventory.gcm');if(meta.s.size<1||meta.s.size>131072)fail('artifact_refused');
  const magic=Buffer.byteLength('COLLECTPGBKUP1'),prefix=exact(dump.fd,magic+16,0),length=prefix.readUInt32BE(magic+12);if(length<1||length>4096)fail('artifact_refused');
  let metadata;try{metadata=JSON.parse(exact(dump.fd,length,prefix.length).toString('utf8'));}catch{fail('artifact_refused');}
  if(metadata.scope!==q.mode||metadata.operation_id!==q.operationId||metadata.plan_sha256!==q.expectedPlanSha256)fail('artifact_refused');
  const checked=await authenticateAndInspectArchive({fd:dump.fd,key,expectedMetadata:metadata}),side=exact(meta.fd,meta.s.size,0);let inventory;
  try{inventory=openInventory({key,operationId:q.operationId,bytes:side});const inventoryHash=sha(Buffer.from(JSON.stringify(inventory))),sideHash=sha(side);
   if(inventoryHash!==metadata.inventory_sha256)fail('bundle_mismatch');
   const bundle=sha(Buffer.from(checked.ciphertextSha256+'\0'+sideHash+'\0'+metadata.snapshot_sha256+'\0'+inventoryHash));if(bundle!==recorded.artifactSha256)fail('bundle_mismatch');
   const currentDump=lstatSync(base+'.pgc.gcm'),currentMeta=lstatSync(base+'.inventory.gcm');if(currentDump.dev!==dump.s.dev||currentDump.ino!==dump.s.ino||currentMeta.dev!==meta.s.dev||currentMeta.ino!==meta.s.ino)fail('artifact_changed');
   return {status:'bundle_verified_point_in_time',operationId:q.operationId,planSha256:q.expectedPlanSha256,bundleSha256:bundle,dumpSha256:checked.ciphertextSha256,inventorySha256:sideHash,snapshotSha256:metadata.snapshot_sha256,retryAuthorized:false};
  }finally{side.fill(0);}
 }catch(e){if(e instanceof VerifyError)throw e;fail('bundle_unavailable');}finally{if(dump)closeSync(dump.fd);if(meta)closeSync(meta.fd);key?.fill(0);}
}
