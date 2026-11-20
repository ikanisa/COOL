// Test-only native PostgreSQL fixture. Starts postgres as an owned child rather
// than relying on a pg_ctl start acknowledgement. Never removes an uncertain
// cluster; TERM/INT are forwarded and shutdown is awaited where possible.
import {spawn,spawnSync} from 'node:child_process';
import {accessSync,closeSync,existsSync,mkdirSync,mkdtempSync,openSync,readFileSync,realpathSync,rmSync,constants} from 'node:fs';
import {join} from 'node:path';

const active=new Set();let handling=false,installed=false;
const wait=(promise,ms)=>new Promise(resolve=>{
 let done=false;const timer=setTimeout(()=>{if(!done){done=true;resolve(null);}},ms);
 promise.then(value=>{if(!done){done=true;clearTimeout(timer);resolve(value);}},()=>{if(!done){done=true;clearTimeout(timer);resolve(null);}});
});
const alive=pid=>{try{process.kill(pid,0);return true;}catch(e){return e?.code!=='ESRCH';}};
function register(fixture){
 active.add(fixture);if(installed)return;installed=true;
 process.prependListener('SIGINT',onInt);process.prependListener('SIGTERM',onTerm);
}
function unregister(fixture){
 active.delete(fixture);if(active.size||handling||!installed)return;
 process.removeListener('SIGINT',onInt);process.removeListener('SIGTERM',onTerm);installed=false;
}
function onInt(){void onSignal('SIGINT');}function onTerm(){void onSignal('SIGTERM');}
async function onSignal(signal){
 if(handling)return;handling=true;const fixtures=[...active];
 for(const f of fixtures)f.cancel(signal);
 await Promise.allSettled(fixtures.map(f=>f.close()));
 process.exit(signal==='SIGINT'?130:143);
}
function executable(path){try{accessSync(path,constants.X_OK);return true;}catch{return false;}}
function pg17(dir){
 if(!dir||!['initdb','postgres','pg_ctl','pg_isready'].every(name=>executable(join(dir,name))))return false;
 const version=spawnSync(join(dir,'postgres'),['--version'],{encoding:'utf8',timeout:5000,env:{PATH:'/usr/bin:/bin',LC_ALL:'C'}});
 return version.status===0&&/\bPostgreSQL\)? 17\./.test(version.stdout??'');
}
export function resolvePg17Bin(){
 const configured=process.env.COLLECT_SYNTHETIC_PG_BIN;
 if(configured){if(pg17(configured))return configured;throw new Error('COLLECT_SYNTHETIC_PG_BIN must contain PostgreSQL 17 binaries');}
 const local='/Volumes/PRO-G40/Development/Supabase/Qwen-Validation/cache/stack/slim-services/postgres/17.11.0.004-r1/darwin-arm64/bin';
 if(pg17(local))return local;
 const config=spawnSync('pg_config',['--bindir'],{encoding:'utf8',timeout:5000});
 if(config.status===0&&pg17((config.stdout??'').trim()))return config.stdout.trim();
 for(const dir of (process.env.PATH??'').split(':'))if(pg17(dir))return dir;
 throw new Error('PostgreSQL 17 initdb, postgres, pg_ctl and pg_isready are required');
}
function launch(file,args,options){
 let child;try{child=spawn(file,args,options);}catch{return {child:null,done:Promise.resolve({code:null,signal:null,error:true})};}
 const done=new Promise(resolve=>{let finished=false;const complete=value=>{if(!finished){finished=true;resolve(value);}};
  child.on('error',()=>{if(!child.pid)complete({code:null,signal:null,error:true});});
  child.once('close',(code,signal)=>complete({code,signal,error:false}));
 });
 return {child,done};
}
function signalAux(proc,signal){
 const child=proc?.child;if(!child||child.exitCode!==null||child.signalCode!==null)return;
 try{if(proc.ownsGroup&&child.pid>1)process.kill(-child.pid,signal);else child.kill(signal);}catch{}
}
function pidData(path){
 try{const lines=readFileSync(path,'utf8').split('\n'),pid=Number(lines[0]);return Number.isSafeInteger(pid)&&pid>1?{pid,data:lines[1],port:lines[3],socket:lines[4]}:null;}
 catch{return null;}
}

export class FixtureError extends Error{
 constructor(code,root){super(code);this.name='FixtureError';this.code=code;this.root=root;}
}

export async function startOwnedPg17({prefix,initialUser,clusterName='collect_synthetic_fixture',onPhase,afterInitdbSpawn,beforeReady,forceUnconfirmedStop=false}={}){
 if(!['collect-pg-transfer-','collect-quarantine-'].includes(prefix)||!['collect_fixture','fixture_bootstrap'].includes(initialUser)||
   !/^[a-z_]+$/.test(clusterName)||!['darwin','linux'].includes(process.platform))throw new Error('unsupported fixture configuration');
 if(process.getuid?.()===0)throw new Error('PostgreSQL fixture requires a non-root user');
 const base=process.platform==='darwin'?'/private/tmp':'/tmp';
 if(realpathSync(base)!==base)throw new Error('fixture temporary root must be its physical path');
 const bin=resolvePg17Bin(),root=mkdtempSync(join(base,prefix)),data=join(root,'db'),socket=join(root,'s'),log=join(root,'postgres.log');
 mkdirSync(socket,{mode:0o700});
 const fixture={root,data,socket,log,port:51000+Math.floor(Math.random()*10000),bin,initialUser,clusterName,
  canceled:false,initAttempted:false,initConfirmed:false,startAttempted:false,startConfirmed:false,server:null,serverDone:null,serverPid:null,aux:null,external:new Set(),closePromise:null,
  env:{PATH:'/usr/bin:/bin',LC_ALL:'C',TMPDIR:root},forceUnconfirmedStop};
 fixture.cancel=signal=>{
  fixture.canceled=true;signalAux(fixture.aux,signal);
  for(const proc of fixture.external)if(proc.child.exitCode===null&&proc.child.signalCode===null){try{proc.child.kill(signal);}catch{}}
 };
 fixture.trackChild=child=>{
  const proc={child,done:new Promise(resolve=>{let done=false;const finish=()=>{if(!done){done=true;resolve(true);}};child.on('error',()=>{if(!child.pid)finish();});child.once('close',finish);})};
  fixture.external.add(proc);void proc.done.then(()=>fixture.external.delete(proc));return child;
 };
 fixture.runAux=async(name,args,timeout=30000)=>{
  if(fixture.aux)throw new FixtureError('fixture_auxiliary_overlap',root);
  if(name==='initdb')fixture.initAttempted=true;
  const proc=launch(join(bin,name),args,{env:fixture.env,stdio:'ignore',detached:name==='initdb'});proc.ownsGroup=name==='initdb';fixture.aux=proc;
  if(name==='initdb'){onPhase?.('initdb_spawned',{root,pid:proc.child?.pid??null});if(afterInitdbSpawn)await afterInitdbSpawn();}
  let result=await wait(proc.done,timeout);
  if(!result&&proc.child){signalAux(proc,'SIGTERM');result=await wait(proc.done,2000);}
  if(!result&&proc.child){signalAux(proc,'SIGKILL');result=await wait(proc.done,2000);}
  if(result)fixture.aux=null;
  return result;
 };
 fixture.close=()=>fixture.closePromise??=(async()=>{
  fixture.canceled=true;let auxiliaryConfirmed=true,serverConfirmed=true;
  if(fixture.aux){
   const aux=fixture.aux;signalAux(aux,'SIGTERM');
   let r=await wait(aux.done,2000);if(!r&&aux.child){signalAux(aux,'SIGKILL');r=await wait(aux.done,2000);}
   auxiliaryConfirmed=!!r;if(r&&fixture.aux===aux)fixture.aux=null;
  }
  for(const proc of fixture.external){
   if(proc.child.exitCode===null&&proc.child.signalCode===null){try{proc.child.kill('SIGTERM');}catch{}}
   let r=await wait(proc.done,2000);if(!r){try{proc.child.kill('SIGKILL');}catch{}r=await wait(proc.done,2000);}
   if(!r)auxiliaryConfirmed=false;
  }
  if(fixture.startAttempted){
   const server=fixture.server;
   if(server&&server.exitCode===null&&server.signalCode===null){try{server.kill('SIGINT');}catch{}}
   let exit=fixture.serverDone?await wait(fixture.serverDone,12000):null;
   if(!exit&&server){try{server.kill('SIGKILL');}catch{}await wait(fixture.serverDone,3000);serverConfirmed=false;}
   if(!exit||exit.error||exit.code!==0||exit.signal)serverConfirmed=false;
   if(!fixture.startConfirmed||!fixture.serverPid||alive(fixture.serverPid)||existsSync(join(data,'postmaster.pid')))serverConfirmed=false;
   if(serverConfirmed&&auxiliaryConfirmed){
    const status=await fixture.runAux('pg_ctl',['-D',data,'status'],5000);
    if(!status||status.error||status.signal||status.code!==3)serverConfirmed=false;
   }
  }
  if(fixture.forceUnconfirmedStop)serverConfirmed=false;
  if(fixture.initAttempted&&!fixture.initConfirmed)serverConfirmed=false;
  const safe=auxiliaryConfirmed&&serverConfirmed;
  if(safe){try{rmSync(root,{recursive:true,force:true});}catch{serverConfirmed=false;}}
  unregister(fixture);
  if(!auxiliaryConfirmed||!serverConfirmed){
   process.stderr.write(`[pg-fixture] stop/start unconfirmed; retained ${root}\n`);
   return {removed:false,root};
  }
  return {removed:true,root};
 })();
 register(fixture);
 try{
  const initialized=await fixture.runAux('initdb',['-D',data,'--username='+initialUser,'--auth-local=trust','--auth-host=reject','--encoding=UTF8','--no-instructions']);
  if(fixture.canceled||!initialized||initialized.error||initialized.signal||initialized.code!==0)throw new Error('initdb_unconfirmed');
  fixture.initConfirmed=true;
  fixture.startAttempted=true;
  const fd=openSync(log,'a',0o600);
  try{
   const proc=launch(join(bin,'postgres'),['-D',data,'-k',socket,'-p',String(fixture.port),'-c','listen_addresses=',
    '-c','unix_socket_permissions=0700','-c','cluster_name='+clusterName],{env:fixture.env,stdio:['ignore',fd,fd]});
   fixture.server=proc.child;fixture.serverDone=proc.done;fixture.serverPid=proc.child?.pid??null;
  }finally{closeSync(fd);}
  onPhase?.('server_spawned',{root,pid:fixture.serverPid});
  if(beforeReady)await beforeReady();
  const deadline=Date.now()+20000;
  while(Date.now()<deadline&&!fixture.canceled){
   if(!fixture.server||fixture.server.exitCode!==null||fixture.server.signalCode!==null)break;
   const ready=await fixture.runAux('pg_isready',['-h',socket,'-p',String(fixture.port),'-U',initialUser,'-d','postgres','-t','1','-q'],3000);
   if(!fixture.canceled&&ready&&!ready.error&&!ready.signal&&ready.code===0){
    const p=pidData(join(data,'postmaster.pid'));
    if(p&&p.pid===fixture.serverPid&&p.data===data&&p.port===String(fixture.port)&&p.socket===socket){fixture.startConfirmed=true;onPhase?.('ready',{root,pid:p.pid});return fixture;}
   }
   await new Promise(resolve=>setTimeout(resolve,100));
  }
  throw new Error('start_unconfirmed');
 }catch{
  const outcome=await fixture.close();throw new FixtureError(outcome.removed?'fixture_start_failed':'fixture_start_unconfirmed',root);
 }
}
