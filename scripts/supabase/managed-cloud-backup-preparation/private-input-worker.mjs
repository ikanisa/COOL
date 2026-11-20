// Spawned only by the synthetic supervisor. No passwords in argv or env.
import {constants,closeSync,fstatSync,lstatSync,openSync,readSync,realpathSync} from 'node:fs';
import {dirname} from 'node:path';
let request=Buffer.alloc(0),secret;
process.stdin.on('data',b=>{request=Buffer.concat([request,b]);if(request.length>8192)process.exit(2);});
process.stdin.on('end',()=>{
 let fd;try{
  const o=JSON.parse(request.toString('utf8'));request.fill(0);
  if(o.mode!=='synthetic')process.exit(2);
  if(o.testHang===true){setInterval(()=>{},1000);return;}
  const path=o.path,kind=o.kind;if(!['password','key'].includes(kind)||typeof path!=='string'||!path.startsWith('/')||realpathSync(path)!==path)process.exit(2);
  const dir=lstatSync(dirname(path)),before=lstatSync(path);
  if(!dir.isDirectory()||dir.isSymbolicLink()||dir.uid!==process.getuid()||(dir.mode&0o077)!==0||
   !before.isFile()||before.isSymbolicLink()||before.uid!==process.getuid()||(before.mode&0o777)!==0o600||
   before.nlink!==1||before.size<1||before.size>4096||kind==='key'&&before.size!==32)process.exit(2);
  fd=openSync(path,constants.O_RDONLY|(constants.O_NOFOLLOW??0)|(constants.O_NONBLOCK??0));
  const after=fstatSync(fd);if(!after.isFile()||after.dev!==before.dev||after.ino!==before.ino||after.size!==before.size||after.uid!==before.uid||(after.mode&0o777)!==0o600||after.nlink!==1)process.exit(2);
  secret=Buffer.alloc(after.size);let pos=0;while(pos<secret.length){const n=readSync(fd,secret,pos,secret.length-pos,pos);if(!n)process.exit(2);pos+=n;}
  if(kind==='password'&&secret.some(c=>c===0||c===10||c===13))process.exit(2);
  closeSync(fd);fd=undefined;process.stdout.write(secret,()=>{secret.fill(0);process.exit(0);});
 }catch{process.exit(2);}finally{if(fd!==undefined)try{closeSync(fd);}catch{}request.fill(0);}
});
