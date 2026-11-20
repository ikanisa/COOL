// Manifest verification happens before private input. This does not attest
// code, libraries, environment or binaries already loaded before startup.
import {constants} from 'node:fs';
import {open,lstat,realpath} from 'node:fs/promises';
import {isAbsolute,normalize} from 'node:path';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
const FIXED=fileURLToPath(new URL('./SOURCE-PINS.json',import.meta.url));
const HASH=/^[a-f0-9]{64}$/,MAX_FILE=256*1024*1024,MAX_TOTAL=512*1024*1024;
const fail=()=>{throw Object.assign(Error('SOURCE_MANIFEST_REFUSED'),{archiveCode:'SOURCE_MANIFEST_REFUSED'});};
const exact=(o,k)=>o&&typeof o==='object'&&!Array.isArray(o)&&Object.getPrototypeOf(o)===Object.prototype&&Object.keys(o).sort().join(',')===[...k].sort().join(',');
const same=(a,b)=>a.dev===b.dev&&a.ino===b.ino&&a.size===b.size&&a.mtimeNs===b.mtimeNs&&a.ctimeNs===b.ctimeNs;
async function readChecked(path,limit,collect=false){
 if(typeof path!=='string'||!isAbsolute(path)||normalize(path)!==path||path.includes('\0'))fail();let h;
 try{
  if(await realpath(path)!==path)fail();h=await open(path,constants.O_RDONLY|constants.O_NOFOLLOW);
  const a=await h.stat({bigint:true});if(!a.isFile()||a.size<0n||a.size>BigInt(limit))fail();
  const hash=createHash('sha256'),parts=[],buffer=Buffer.allocUnsafe(1024*1024);let offset=0;
  while(offset<Number(a.size)){
   const {bytesRead}=await h.read(buffer,0,Math.min(buffer.length,Number(a.size)-offset),offset);if(!bytesRead)fail();
   hash.update(buffer.subarray(0,bytesRead));if(collect)parts.push(Buffer.from(buffer.subarray(0,bytesRead)));offset+=bytesRead;
  }
  if((await h.read(buffer,0,1,offset)).bytesRead!==0)fail();
  const b=await h.stat({bigint:true}),p=await lstat(path,{bigint:true});if(!same(a,b)||!same(a,p)||!p.isFile()||await realpath(path)!==path)fail();
  return {sha256:hash.digest('hex'),size:offset,bytes:collect?Buffer.concat(parts):null};
 }catch{fail();}finally{await h?.close().catch(()=>{});}
}
// Public for owned-fixture regression only; the worker and supervisor always
// call verifyReviewedSourceManifest with the fixed source-manifest path.
export async function verifyManifestFile(path,expected,{required=[]}={}){
 if(!HASH.test(expected??'')||!Array.isArray(required))fail();
 const m=await readChecked(path,1024*1024,true);if(m.sha256!==expected)fail();
 let v,raw;try{raw=new TextDecoder('utf-8',{fatal:true}).decode(m.bytes);v=JSON.parse(raw);
  if(raw!==JSON.stringify(v)&&raw!==JSON.stringify(v,null,2)+'\n')fail();}catch{fail();}
 if(!exact(v,['format','inputs'])||v.format!=='collect.managed-archive-operator.source-pins.v2'||!Array.isArray(v.inputs)||v.inputs.length<1||v.inputs.length>500)fail();
 let previous='',total=0;const found=new Set();
 for(const item of v.inputs){
  if(!exact(item,['path','sha256'])||typeof item.path!=='string'||item.path<=previous||!HASH.test(item.sha256??''))fail();
  previous=item.path;const actual=await readChecked(item.path,MAX_FILE);total+=actual.size;if(total>MAX_TOTAL||actual.sha256!==item.sha256)fail();found.add(item.path);
 }
 if(required.some(p=>!found.has(p)))fail();return {status:'source_verified',manifestSha256:expected};
}
export async function verifyReviewedSourceManifest(expected){
 const required=[process.execPath,...['supervisor.mjs','worker.mjs','input.mjs','operator.mjs','archive-core.mjs','journal.mjs','source-manifest.mjs','verify-worker.mjs'].map(n=>fileURLToPath(new URL('./'+n,import.meta.url))),
  fileURLToPath(new URL('../../../supabase/migrations/20261101012309_collect_admission_archive.sql',import.meta.url)),
  fileURLToPath(new URL('../managed-cloud-migrations/supabase-root-2021.pem',import.meta.url))];
 return verifyManifestFile(FIXED,expected,{required});
}
