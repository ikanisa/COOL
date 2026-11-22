// Private child used by the supervised reader. No passwords in argv or env.
import {constants,closeSync,fstatSync,lstatSync,openSync,readSync,realpathSync} from 'node:fs';
import {dirname} from 'node:path';
import {Socket} from 'node:net';
let request=Buffer.alloc(0),secret;
function same(a,b){return a.isFile()&&b.isFile()&&['dev','ino','size','uid','mode','nlink','mtimeNs','ctimeNs'].every(k=>a[k]===b[k]);}
async function syntheticReadGate(){const s=new Socket({fd:3,readable:true,writable:true});try{const ack=new Promise((resolve,reject)=>{s.once('data',resolve);s.once('end',reject);s.once('error',reject);});s.write('read');await ack;}finally{s.destroy();}}
process.stdin.on('data',b=>{request=Buffer.concat([request,b]);if(request.length>8192)process.exit(2);});
process.stdin.on('end',async()=>{
 let fd;try{
  const o=JSON.parse(request.toString('utf8'));request.fill(0);
  if(!['managed','synthetic'].includes(o.mode))process.exit(2);
  if(o.testHang===true){if(o.mode!=='synthetic')process.exit(2);setInterval(()=>{},1000);return;}
  const path=o.path,kind=o.kind;if(!['password','key'].includes(kind)||typeof path!=='string'||!path.startsWith('/')||realpathSync(path)!==path)process.exit(2);
  const dir=lstatSync(dirname(path)),before=lstatSync(path,{bigint:true});
  if(!dir.isDirectory()||dir.isSymbolicLink()||dir.uid!==process.getuid()||(dir.mode&0o077)!==0||
   !before.isFile()||before.isSymbolicLink()||before.uid!==BigInt(process.getuid())||(before.mode&0o777n)!==0o600n||
   before.nlink!==1n||before.size<1n||before.size>4096n||kind==='key'&&before.size!==32n)process.exit(2);
  fd=openSync(path,constants.O_RDONLY|(constants.O_NOFOLLOW??0)|(constants.O_NONBLOCK??0));
  const after=fstatSync(fd,{bigint:true});if(!same(before,after))process.exit(2);
  secret=Buffer.alloc(Number(after.size));let pos=0;while(pos<secret.length){const n=readSync(fd,secret,pos,secret.length-pos,pos);if(!n)process.exit(2);pos+=n;}
  if(o.testPauseAfterRead===true){if(o.mode!=='synthetic')process.exit(2);await syntheticReadGate();}else if(o.testPauseAfterRead!==undefined)process.exit(2);
  const extra=Buffer.alloc(1);if(readSync(fd,extra,0,1,secret.length)!==0)process.exit(2);
  if(!same(after,fstatSync(fd,{bigint:true}))||!same(after,lstatSync(path,{bigint:true})))process.exit(2);
  let payload=secret;
  if(kind==='password'){
   let end=secret.length;if(secret[end-1]===10){end--;if(end>0&&secret[end-1]===13)end--;}
   payload=secret.subarray(0,end);if(!payload.length||payload.some(c=>c===0||c===10||c===13))process.exit(2);
  }
  closeSync(fd);fd=undefined;process.stdout.write(payload,()=>{secret.fill(0);process.exit(0);});
 }catch{process.exit(2);}finally{if(fd!==undefined)try{closeSync(fd);}catch{}request.fill(0);}
});
