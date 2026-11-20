// The supervised worker checks point-in-time pins before credential reads.
import {createHash} from 'node:crypto';
import {constants,closeSync,fstatSync,lstatSync,openSync,readSync,realpathSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';
import {assertUniqueJson} from '../managed-component-refresh/capture-json.mjs';
import {CaptureError} from './seal.mjs';
const root=realpathSync(fileURLToPath(new URL('../../../',import.meta.url)));
const here='scripts/supabase/managed-edge-capture-live-v1/';
const files=['core.mjs','seal.mjs','multipart.mjs','source-pins.mjs','worker.mjs','supervisor.mjs','fixture.mjs','transport-mock-fixture.mjs','core.test.mjs','multipart.test.mjs','supervisor.test.mjs','README.md'].map(x=>here+x).concat([
 'scripts/supabase/current-archive/bundle.mjs','scripts/supabase/current-archive/codec.mjs','scripts/supabase/managed-component-refresh/capture-json.mjs']);
const node='/Volumes/PRO-G40/Development/Node/bin/node',manifest=join(root,here,'LIVE-SOURCE-PINS.json');
const HASH=/^[0-9a-f]{64}$/;
const fail=()=>{throw new CaptureError('SOURCE_PINS_REFUSED');};
const same=(a,b)=>a.isFile()&&b.isFile()&&['dev','ino','size','uid','mode','nlink','mtimeNs','ctimeNs'].every(k=>a[k]===b[k]);
function inspect(path,limit,readContent=false){
 let fd,parts=[];const buf=Buffer.alloc(65536);
 try{
  if(realpathSync(path)!==path)fail();const before=lstatSync(path,{bigint:true});
  if(!before.isFile()||before.isSymbolicLink()||before.size<1n||before.size>BigInt(limit)||(before.mode&0o022n)!==0n)fail();
  fd=openSync(path,constants.O_RDONLY|(constants.O_NOFOLLOW??0));const opened=fstatSync(fd,{bigint:true});if(!same(before,opened))fail();
  const h=createHash('sha256');let pos=0,size=Number(opened.size);while(pos<size){const n=readSync(fd,buf,0,Math.min(buf.length,size-pos),pos);if(!n)fail();h.update(buf.subarray(0,n));if(readContent)parts.push(Buffer.from(buf.subarray(0,n)));pos+=n;}
  if(readSync(fd,buf,0,1,size)!==0||!same(opened,fstatSync(fd,{bigint:true}))||!same(opened,lstatSync(path,{bigint:true})))fail();
  return {sha256:h.digest('hex'),bytes:readContent?Buffer.concat(parts):null};
 }catch{fail();}finally{buf.fill(0);for(const p of parts)p.fill(0);if(fd!==undefined)closeSync(fd);}
}
export async function verifyPinnedSources(expected){
 if(!HASH.test(expected??''))fail();const m=inspect(manifest,65536,true);let p;
 try{if(m.sha256!==expected)fail();const raw=new TextDecoder('utf-8',{fatal:true}).decode(m.bytes);assertUniqueJson(raw,65536);p=JSON.parse(raw);}
 catch{fail();}finally{m.bytes?.fill(0);}
 if(!p||Object.keys(p).sort().join(',')!=='binaries,files,format'||p.format!=='collect.edge-live-source-pins.v1'||
  !p.files||Object.keys(p.files).sort().join('\0')!==[...files].sort().join('\0')||
  !p.binaries||Object.keys(p.binaries).join(',')!==node||realpathSync(process.execPath)!==node)fail();
 for(const file of files){const pin=p.files[file];if(!HASH.test(pin??'')||inspect(join(root,file),10*1024*1024).sha256!==pin)fail();}
 if(!HASH.test(p.binaries[node]??'')||inspect(node,150*1024*1024).sha256!==p.binaries[node])fail();
 return true;
}
