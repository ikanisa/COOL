// Synthetic-only owned PostgreSQL 17 fixture. Importing this module does not
// start a process, read a credential, connect to a database or use Docker.
import {createHash,randomInt,randomUUID} from 'node:crypto';
import {spawn,spawnSync} from 'node:child_process';
import {constants} from 'node:fs';
import {access,chmod,lstat,mkdir,mkdtemp,readFile,realpath,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {dirname,isAbsolute,join,relative,resolve,sep} from 'node:path';
import {fileURLToPath} from 'node:url';

const ROOT=resolve(dirname(fileURLToPath(import.meta.url)),'../../../..');
const ORIGINAL_ROOT='/Volumes/T7/01 Projects/COLLECT';
const SQL='supabase/migrations/20261022195747_collect_application_mutation_fence.sql';
export const FENCE_MIGRATION_SHA256='714abf2d24ce3d42a36525d18627362b02ff38c30810e988d365b5796d840497';
const BASELINE='dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3';
const TOOL_ENV=Object.freeze({PATH:'/usr/bin:/bin:/usr/sbin:/sbin',LC_ALL:'C'});
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const fail=code=>{throw Error(code);};
const validPath=value=>typeof value==='string'&&isAbsolute(value)&&resolve(value)===value&&/^[A-Za-z0-9_./-]+$/.test(value);
const contains=(a,b)=>{const r=relative(a,b);return r===''||r!=='..'&&!r.startsWith('..'+sep)&&!isAbsolute(r);};
const separate=(a,b)=>!contains(a,b)&&!contains(b,a);

export function parseFixtureOptions(env){
 if(env.COLLECT_HTTP_ADMISSION_PG_QUALIFY!=='true')fail('HTTP_ADMISSION_SYNTHETIC_OPT_IN_REQUIRED');
 const bin=env.COLLECT_HTTP_ADMISSION_PG_BIN_DIR,requestedTemp=env.COLLECT_HTTP_ADMISSION_PG_TMP_ROOT;
 if(!validPath(bin))fail('HTTP_ADMISSION_PHYSICAL_PG_BIN_REQUIRED');
 if(requestedTemp!==undefined&&!validPath(requestedTemp))fail('HTTP_ADMISSION_PHYSICAL_TEMP_ROOT_REQUIRED');
 return {bin,requestedTemp};
}
export function fixtureTableNames(sql){
 if(typeof sql!=='string'||sha(Buffer.from(sql))!==FENCE_MIGRATION_SHA256)fail('HTTP_ADMISSION_FENCE_SOURCE_CHANGED');
 const matches=[...sql.matchAll(/DECLARE expected jsonb:='(\[[\s\S]*?\])'::jsonb;observed jsonb;/g)];
 if(matches.length!==1)fail('HTTP_ADMISSION_FENCE_SCOPE_CHANGED');
 let names;try{names=JSON.parse(matches[0][1]);}catch{fail('HTTP_ADMISSION_FENCE_SCOPE_CHANGED');}
 if(!Array.isArray(names)||names.length!==110||new Set(names).size!==110||names.some(n=>typeof n!=='string'||!/^(?:app|private)\.[a-z][a-z0-9_]*$/.test(n))||
  names.join('|')!==[...names].sort().join('|'))fail('HTTP_ADMISSION_FENCE_SCOPE_CHANGED');
 return names;
}
async function validatedBins(path){
 if(await realpath(path)!==path)fail('HTTP_ADMISSION_PHYSICAL_PG_BIN_REQUIRED');
 for(const name of ['postgres','initdb','pg_ctl','psql']){
  const file=join(path,name),s=await lstat(file);if(!s.isFile()||s.isSymbolicLink()||await realpath(file)!==file)fail('HTTP_ADMISSION_PG_BINARY_REQUIRED');
  await access(file,constants.X_OK);
  const r=spawnSync(file,['--version'],{env:TOOL_ENV,encoding:'utf8',timeout:15000,maxBuffer:65536});
  if(r.error||r.status!==0||!new RegExp('^'+name.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')+' \\(PostgreSQL\\) 17\\.').test(r.stdout??''))fail('HTTP_ADMISSION_PG17_REQUIRED');
 }
 return path;
}
function command(bin,name,args,{allowed=[0],timeout=30000}={}){
 return new Promise((resolvePromise,reject)=>{
  // Keep a startup/stop command outside the caller's process group. A group
  // TERM must not kill pg_ctl midway through launching an unknown postmaster.
  const child=spawn(join(bin,name),args,{env:TOOL_ENV,stdio:['ignore','ignore','pipe'],detached:true});
  const err=[];let bytes=0,failed=false,expired=false,killTimer;
  const send=signal=>{if(child.pid){try{process.kill(-child.pid,signal);}catch(e){if(e.code!=='ESRCH')failed=true;}}};
  const timer=setTimeout(()=>{expired=true;send('SIGTERM');killTimer=setTimeout(()=>send('SIGKILL'),3000);killTimer.unref();},timeout);
  child.stderr.on('data',data=>{bytes+=data.length;if(bytes<=65536)err.push(data);else{failed=true;send('SIGTERM');}});
  child.on('error',()=>{failed=true;});
  child.on('close',(status,signal)=>{
   clearTimeout(timer);if(killTimer)clearTimeout(killTimer);
   if(failed||expired||signal||!allowed.includes(status)){
    const detail=Buffer.concat(err).toString('utf8').trim().slice(-600);
    reject(Error('HTTP_ADMISSION_'+name.toUpperCase()+'_FAILED'+(detail?': '+detail:'')));
   }else resolvePromise({status});
  });
 });
}
function query(bin,socket,port,sql){
 const args=['-h',socket,'-p',String(port),'-U','postgres','-d','postgres','-XAtq','-v','ON_ERROR_STOP=1'];
 return new Promise((resolvePromise,reject)=>{
  const child=spawn(join(bin,'psql'),args,{env:TOOL_ENV,stdio:['pipe','pipe','pipe']}),out=[],err=[];
  let bytes=0,expired=false,failed=false;
  const stop=()=>{failed=true;child.kill('SIGKILL');};
  const timer=setTimeout(()=>{expired=true;stop();},30000);
  child.stdout.on('data',data=>{bytes+=data.length;if(bytes>1048576)stop();else out.push(data);});
  child.stderr.on('data',data=>{if(err.reduce((n,b)=>n+b.length,0)+data.length<=65536)err.push(data);else stop();});
  child.on('error',()=>{failed=true;});child.stdin.on('error',()=>{failed=true;});
  child.on('close',code=>{clearTimeout(timer);if(failed||expired||code!==0){const detail=Buffer.concat(err).toString('utf8').trim().slice(-600);reject(Error('HTTP_ADMISSION_SYNTHETIC_PSQL_FAILED'+(detail?': '+detail:'')));}
   else resolvePromise(Buffer.concat(out).toString('utf8').trim());});
  child.stdin.end(sql);
 });
}
const quote=value=>"'"+String(value).replaceAll("'","''")+"'";
export async function createOwnedFixture(env=process.env,{signal}={}){
 const checkInterrupted=()=>{if(signal?.aborted)fail('HTTP_ADMISSION_FIXTURE_INTERRUPTED');};
 const {bin,requestedTemp}=parseFixtureOptions(env);
 if(typeof process.getuid!=='function'||process.getuid()===0)fail('HTTP_ADMISSION_NONROOT_REQUIRED');
 await validatedBins(bin);checkInterrupted();
 const tempRoot=await realpath(requestedTemp??tmpdir());
 if(!validPath(tempRoot)||!separate(tempRoot,ROOT)||!separate(tempRoot,ORIGINAL_ROOT))fail('HTTP_ADMISSION_TEMP_ROOT_INVALID');
 const dir=await mkdtemp(join(tempRoot,'collect-http-admission-pg-'));await chmod(dir,0o700);
 const initial=await lstat(dir);
 if(!initial.isDirectory()||initial.isSymbolicLink()||initial.uid!==process.getuid()||(initial.mode&0o777)!==0o700||await realpath(dir)!==dir||dirname(dir)!==tempRoot)fail('HTTP_ADMISSION_OWNED_DIRECTORY_REQUIRED');
 const data=join(dir,'data'),socket=join(dir,'socket'),log=join(dir,'postgres.log'),port=randomInt(20000,60000);
 let initDispatched=false,initConfirmed=false,startDispatched=false,serverPid=null,closing;
 const pidFile=join(data,'postmaster.pid');
 async function ownedServerPid(){
  const s=await lstat(data);
  if(!s.isDirectory()||s.isSymbolicLink()||await realpath(data)!==data)fail('HTTP_ADMISSION_SERVER_IDENTITY_UNCONFIRMED: '+dir);
  const lines=(await readFile(pidFile,'utf8')).split('\n'),pid=Number(lines[0]);
  if(!Number.isSafeInteger(pid)||pid<2||lines[1]!==data)fail('HTTP_ADMISSION_SERVER_IDENTITY_UNCONFIRMED: '+dir);
  return pid;
 }
 function alive(pid){try{process.kill(pid,0);return true;}catch(error){return error.code!=='ESRCH';}}
 function close(){
  if(closing)return closing;
  closing=(async()=>{
  // A failed/terminated initdb may have spawned bootstrap children. Retain
  // the data until initialization is confirmed to have returned successfully.
  if(initDispatched&&!initConfirmed)throw Error('HTTP_ADMISSION_INIT_UNCONFIRMED: '+dir);
  if(startDispatched){
   // pg_ctl can fail or time out after dispatching a postmaster. A status of
   // "not running" alone cannot exclude an as-yet-unacknowledged startup.
   if(serverPid===null)throw Error('HTTP_ADMISSION_START_UNCONFIRMED: '+dir);
   let hasPid=true;try{await access(pidFile);}catch(error){if(error.code==='ENOENT')hasPid=false;else throw error;}
   if(hasPid){
    if(await ownedServerPid()!==serverPid)throw Error('HTTP_ADMISSION_SERVER_IDENTITY_UNCONFIRMED: '+dir);
    try{await command(bin,'pg_ctl',['-D',data,'-m','fast','-w','-t','15','stop'],{timeout:20000});}
    catch{throw Error('HTTP_ADMISSION_SERVER_STOP_UNCONFIRMED: '+dir);}
   }
   const status=spawnSync(join(bin,'pg_ctl'),['-D',data,'status'],{env:TOOL_ENV,encoding:'utf8',timeout:15000,maxBuffer:65536});
   let remains=true;try{await access(pidFile);}catch(error){if(error.code==='ENOENT')remains=false;else throw error;}
   if(status.error||status.status!==3||remains||alive(serverPid))throw Error('HTTP_ADMISSION_SERVER_STOP_UNCONFIRMED: '+dir);
  }
  const current=await lstat(dir);
  if(!current.isDirectory()||current.isSymbolicLink()||current.uid!==process.getuid()||(current.mode&0o777)!==0o700||
   current.dev!==initial.dev||current.ino!==initial.ino||await realpath(dir)!==dir||dirname(dir)!==tempRoot)throw Error('HTTP_ADMISSION_CLEANUP_UNCONFIRMED: '+dir);
  await rm(dir,{recursive:true,force:true});
  })();
  return closing;
 }
 try{
  if(Buffer.byteLength(join(socket,'.s.PGSQL.'+port))>100)fail('HTTP_ADMISSION_SOCKET_PATH_TOO_LONG');
  const migration=await readFile(join(ROOT,SQL),'utf8'),names=fixtureTableNames(migration);
  await mkdir(socket,{mode:0o700});checkInterrupted();
  initDispatched=true;await command(bin,'initdb',['-D',data,'-U','postgres','--auth=trust','--no-locale','--encoding=UTF8'],{timeout:60000});initConfirmed=true;checkInterrupted();
  // No TCP listener. Only this fresh owned directory contains the Unix socket.
  startDispatched=true;await command(bin,'pg_ctl',['-D',data,'-l',log,'-o',"-c listen_addresses='' -k "+socket+' -p '+port+' -c unix_socket_permissions=0700','-w','-t','25','start'],{timeout:30000});
  serverPid=await ownedServerPid();checkInterrupted();
  const psql=sql=>query(bin,socket,port,sql);
  const identity=JSON.parse(await psql("SELECT json_build_object('database',current_database(),'role',current_user,'address',inet_server_addr(),'data',current_setting('data_directory'),'socket',current_setting('unix_socket_directories'),'listen',current_setting('listen_addresses'),'port',current_setting('port'),'version',current_setting('server_version_num'));"));
  if(identity.database!=='postgres'||identity.role!=='postgres'||identity.address!==null||identity.data!==data||identity.socket!==socket||identity.listen!==''||Number(identity.port)!==port||!/^17[0-9]{4}$/.test(identity.version))fail('HTTP_ADMISSION_OWNED_PG_IDENTITY_REQUIRED');
  checkInterrupted();
  const tables=names.map(name=>{const [schema,table]=name.split('.');return 'CREATE TABLE "'+schema+'"."'+table+'"(synthetic_fixture integer);';}).join('\n');
  await psql('CREATE ROLE collect_runtime NOLOGIN;CREATE SCHEMA app;CREATE SCHEMA private;GRANT USAGE ON SCHEMA private TO collect_runtime;\n'+tables+'\n'+migration+
   "\nSELECT private.collect_fence_initialize('"+randomUUID()+"'::uuid,repeat('a',64),'"+BASELINE+"');");
  checkInterrupted();if(sha(await readFile(join(ROOT,SQL)))!==FENCE_MIGRATION_SHA256)fail('HTTP_ADMISSION_FENCE_SOURCE_CHANGED');checkInterrupted();
  async function invoke(fn,args){
   const supported={register:'private.collect_fence_register',close:'private.collect_fence_close',status:'private.collect_fence_work_status'};
   if(!Object.hasOwn(supported,fn)||!Array.isArray(args)||args.some(v=>typeof v==='number'?!Number.isSafeInteger(v)||v<0:typeof v!=='string'||!/^[a-z0-9_-]{1,128}$/.test(v)))fail('HTTP_ADMISSION_FIXTURE_INPUT_INVALID');
   const expressions=args.map(v=>typeof v==='number'?String(v):quote(v)).join(',');
   const result=await psql("BEGIN ISOLATION LEVEL READ COMMITTED READ WRITE;SET LOCAL ROLE collect_runtime;SELECT set_config('collect.edge_verified','true',true);SELECT "+supported[fn]+"("+expressions+");COMMIT;");
   const line=result.split('\n').find(value=>value.trim().startsWith('{'));if(!line)fail('HTTP_ADMISSION_FIXTURE_RESULT_INVALID');return JSON.parse(line);
  }
  async function stored(id){
   if(typeof id!=='string'||!/^[a-f0-9-]{36}$/.test(id))fail('HTTP_ADMISSION_FIXTURE_INPUT_INVALID');
   const result=await psql("BEGIN READ ONLY;SELECT row_to_json(a) FROM private.collect_fence_admissions a WHERE admission_id="+quote(id)+"::uuid;COMMIT;");
   const line=result.split('\n').find(value=>value.startsWith('{'));if(!line)fail('HTTP_ADMISSION_FIXTURE_RESULT_INVALID');return JSON.parse(line);
  }
  return Object.freeze({invoke,stored,close,sourceSha256:FENCE_MIGRATION_SHA256,providerCalls:0});
 }catch(error){
  try{await close();}catch(cleanup){throw cleanup;}
  throw error;
 }
}
