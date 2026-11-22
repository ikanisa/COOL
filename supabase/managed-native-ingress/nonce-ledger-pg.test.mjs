// This fixture creates and owns a new, socket-only PostgreSQL 17 cluster.
// It never accepts a connection string to an existing database.
import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync,spawn} from 'node:child_process';
import {existsSync,lstatSync,mkdtempSync,mkdirSync,readFileSync,realpathSync,rmSync} from 'node:fs';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {dirname,isAbsolute,join} from 'node:path';
import {setTimeout as delay} from 'node:timers/promises';
import pg from '../../scripts/supabase/node_modules/pg/lib/index.js';
import {nativeNonceAuthoritySql} from '../functions/_shared/private-retention.js';

const binary=process.env.COLLECT_INGRESS_TEST_PG_BIN_DIR;
const {Client}=pg;
const source='c'.repeat(64),profile='a'.repeat(64),policy='b'.repeat(64);
const manifest='dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3';
const migration=await readFile(new URL('../migrations/20261022195747_collect_application_mutation_fence.sql',import.meta.url),'utf8');
const marker='CREATE FUNCTION private.collect_fence_close(';
const end=migration.indexOf(marker);
assert.ok(end>0 && migration.indexOf(marker,end+marker.length)<0,'Expected fence migration preimage');
// Install the unmodified fence tables and functions through assert_write. The
// later application triggers depend on a full application fixture, so this test
// does not claim to validate the complete migration or hosted role graph.
const fenceSql=migration.slice(0,end)+'COMMIT;';
const nonceSql=await readFile(new URL('./nonce-ledger.sql',import.meta.url),'utf8');

test('nonce ledger uses the real fence SQL and serializes concurrent claims', {timeout:150000},async t=>{
 assert.ok(binary && isAbsolute(binary) && realpathSync(binary)===binary,'Set COLLECT_INGRESS_TEST_PG_BIN_DIR to a physical PostgreSQL 17 bin directory');
 assert.ok(typeof process.getuid==='function' && process.getuid()!==0,'The synthetic PostgreSQL fixture must run as non-root');
 for(const name of ['postgres','initdb','pg_ctl']){
  const version=execFileSync(join(binary,name),['--version'],{encoding:'utf8',env:{PATH:'/usr/bin:/bin',LC_ALL:'C'},timeout:10000});
  assert.match(version,new RegExp('^'+name+' \\(PostgreSQL\\) 17\\.'),'PostgreSQL 17 tools required');
 }
 const temporary=realpathSync(process.env.COLLECT_INGRESS_TEST_TMP_ROOT??'/tmp');
 assert.match(temporary,/^\/[A-Za-z0-9_./-]+$/,'PostgreSQL fixture requires a simple physical temporary path');
 const permittedTmp=realpathSync('/tmp');
 assert.ok(temporary===permittedTmp||temporary.startsWith(permittedTmp+'/'),'Fixture root must be under physical /tmp');
 const root=realpathSync(mkdtempSync(join(temporary,'collect-ingress-pg-')));
 assert.equal(dirname(root),temporary,'Fixture root must be in its selected temporary directory');
 const data=join(root,'db'),socket=join(root,'s'),log=join(root,'postgres.log');mkdirSync(socket,{mode:0o700});
 const port=51000+Math.floor(Math.random()*10000),env={PATH:'/usr/bin:/bin',LC_ALL:'C',TMPDIR:root};
 let initAttempted=false,initConfirmed=false,startAttempted=false,serverPid=null,activeChild=null,interrupted=null,cleaning=false,readyRelease;
 const clients=[];
 const stopChild=(sig='SIGTERM')=>{if(activeChild?.pid){try{process.kill(-activeChild.pid,sig);}catch(error){if(error.code!=='ESRCH')throw error;}}};
 const onInterrupt=sig=>{
  if(interrupted)return;
  interrupted=sig;
  if(!cleaning){
   stopChild();
   for(const client of clients){client.on('error',()=>{});client.connection?.stream?.destroy();}
  }
  readyRelease?.();
 };
 const onTerm=()=>onInterrupt('SIGTERM'),onInt=()=>onInterrupt('SIGINT');
 process.on('SIGTERM',onTerm);process.on('SIGINT',onInt);
 const deadline=setTimeout(()=>onInterrupt('TIMEOUT'),90000);deadline.unref();
 const checkInterrupted=()=>{if(interrupted)throw Error('SYNTHETIC_INGRESS_INTERRUPTED: '+interrupted);};
 const run=(name,args,{cleanup=false}={})=>new Promise((resolve,reject)=>{
  if(!cleanup && interrupted){reject(Error('SYNTHETIC_INGRESS_INTERRUPTED: '+interrupted));return;}
  const child=spawn(join(binary,name),args,{env,stdio:'ignore',detached:true});activeChild=child;
  let error=null,timedOut=false,killTimer;
  const timeout=setTimeout(()=>{
   timedOut=true;stopChild();killTimer=setTimeout(()=>stopChild('SIGKILL'),3000);killTimer.unref();
  },30000);
  child.once('error',e=>{error=e;});
  child.once('close',(code,sig)=>{
   clearTimeout(timeout);if(killTimer)clearTimeout(killTimer);activeChild=null;
   if(error || timedOut || code!==0 || sig || (!cleanup && interrupted))reject(Error('SYNTHETIC_INGRESS_TOOL_FAILED: '+name));
   else resolve();
  });
 });
 const ownedPid=()=>{
  if(lstatSync(data).isSymbolicLink() || realpathSync(data)!==data)throw Error('SYNTHETIC_INGRESS_DATA_IDENTITY_UNCONFIRMED');
  const lines=readFileSync(join(data,'postmaster.pid'),'utf8').split('\n');
  const pid=Number(lines[0]);
  if(!Number.isSafeInteger(pid)||pid<2||lines[1]!==data)throw Error('SYNTHETIC_INGRESS_SERVER_IDENTITY_UNCONFIRMED');
  return pid;
 };
 const alive=pid=>{try{process.kill(pid,0);return true;}catch(error){if(error.code==='ESRCH')return false;return true;}};
 const connect=async()=>{const c=new Client({host:socket,port,database:'postgres',user:'collect_fixture',connectionTimeoutMillis:3000});clients.push(c);await c.connect();return c;};
 try{
  initAttempted=true;await run('initdb',['-D',data,'--username=collect_fixture','--auth-local=trust','--auth-host=reject','--encoding=UTF8','--no-instructions']);initConfirmed=true;
  checkInterrupted();startAttempted=true;
  await run('pg_ctl',['-D',data,'-l',log,'-o',`-k ${socket} -p ${port} -c listen_addresses='' -c unix_socket_permissions=0700`,'-w','start']);
  serverPid=ownedPid();checkInterrupted();
  const admin=await connect(),first=await connect(),second=await connect();
  assert.deepEqual((await admin.query("SELECT inet_server_addr() IS NULL AS unix, current_setting('server_version_num')::int / 10000 AS major")).rows[0],{unix:true,major:17});
  await admin.query('CREATE ROLE collect_runtime; CREATE ROLE audit_probe; CREATE SCHEMA private; GRANT USAGE ON SCHEMA private TO collect_runtime,audit_probe');
  await admin.query(fenceSql);await admin.query(nonceSql);
  await admin.query("INSERT INTO private.collect_fence_control(singleton,project_ref,baseline_manifest_sha256,source_sha256,epoch,mode,operation_id) VALUES(true,'rrlduytparvsjfmegalh',$1,$2,1,'open',$3)",[manifest,source,randomUUID()]);
  const admissions=[randomUUID(),randomUUID()];
  for(const id of admissions){
   await admin.query('BEGIN; SET LOCAL ROLE collect_runtime; SELECT set_config(\'collect.edge_verified\',\'true\',true)');
   const registered=await admin.query("SELECT private.collect_fence_register($1,$2,'http_collect') AS result",[id,source]);
   assert.equal(registered.rows[0].result.state,'active');await admin.query('COMMIT');
  }
  if(process.env.COLLECT_INGRESS_TEST_HOLD_READY==='true'){
   console.log('COLLECT_INGRESS_FIXTURE_READY '+JSON.stringify({root,serverPid}));
   await new Promise(resolve=>{readyRelease=resolve;if(interrupted)resolve();});
   checkInterrupted();
  }
  const begin=async(client,id)=>{
   await client.query('BEGIN; SET LOCAL ROLE collect_runtime');
   await client.query("SELECT set_config('collect.edge_verified','true',true),set_config('collect.fence_admission_id',$1,true),set_config('collect.fence_epoch','1',true),set_config('collect.fence_source_sha256',$2,true)",[id,source]);
  };
  const claim=(client,nonce,issued=Date.now())=>client.query('SELECT private.collect_native_ingress_consume($1::uuid,$2,$3,$4::bigint) AS claimed',[nonce,profile,policy,issued]);
  await t.test('a competing session waits for commit and then denies the duplicate',async()=>{
   const nonce=randomUUID();await begin(first,admissions[0]);await begin(second,admissions[1]);
   assert.equal((await claim(first,nonce)).rows[0].claimed,true);
   const pending=claim(second,nonce);let blocked=false;
   for(let i=0;i<80&&!blocked;i++){
    await new Promise(resolve=>setTimeout(resolve,25));
    blocked=(await admin.query('SELECT wait_event_type FROM pg_stat_activity WHERE pid=$1',[second.processID])).rows[0]?.wait_event_type==='Lock';
   }
   assert.equal(blocked,true);await first.query('COMMIT');assert.equal((await pending).rows[0].claimed,false);await second.query('COMMIT');
   assert.equal((await admin.query('SELECT count(*)::int AS n FROM private.collect_native_ingress_nonce_uses WHERE nonce=$1',[nonce])).rows[0].n,1);
  });
  await t.test('a rolled-back claim can be claimed by a later transaction',async()=>{
   const nonce=randomUUID();await begin(first,admissions[0]);assert.equal((await claim(first,nonce)).rows[0].claimed,true);await first.query('ROLLBACK');
   await begin(second,admissions[1]);assert.equal((await claim(second,nonce)).rows[0].claimed,true);await second.query('COMMIT');
  });
  await t.test('expired signatures and non-runtime callers cannot add claims',async()=>{
   await begin(first,admissions[0]);assert.equal((await claim(first,randomUUID(),Date.now()-31000)).rows[0].claimed,false);await first.query('COMMIT');
   await first.query('BEGIN');await assert.rejects(claim(first,randomUUID()),/collect_fence_forbidden/);await first.query('ROLLBACK');
   const access=(await admin.query("SELECT has_table_privilege('collect_runtime','private.collect_native_ingress_nonce_uses','SELECT') AS direct_table, has_function_privilege('audit_probe','private.collect_native_ingress_consume(uuid,text,text,bigint)','EXECUTE') AS other_execute")).rows[0];
   assert.deepEqual(access,{direct_table:false,other_execute:false});
  });
  await t.test('a fenced application denies a previously admitted caller',async()=>{
   const operation=randomUUID();await admin.query("UPDATE private.collect_fence_control SET mode='quiescing',operation_id=$1",[operation]);
   await admin.query("UPDATE private.collect_fence_control SET mode='fenced'");
   await begin(first,admissions[0]);await assert.rejects(claim(first,randomUUID()),/collect_fence_closed/);await first.query('ROLLBACK');
  });
  await t.test('retention authority accepts the exact nonce ledger and rejects privilege drift',async()=>{
   await admin.query('CREATE ROLE postgres; CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role; ALTER TABLE private.collect_native_ingress_nonce_uses OWNER TO postgres; ALTER FUNCTION private.collect_native_ingress_consume(uuid,text,text,bigint) OWNER TO postgres');
   const verdict=async()=>{await admin.query('SET ROLE collect_runtime');try{return (await admin.query(nativeNonceAuthoritySql)).rows[0]?.verified;}finally{await admin.query('RESET ROLE');}};
   assert.equal(await verdict(),true);
   await admin.query('GRANT EXECUTE ON FUNCTION private.collect_native_ingress_consume(uuid,text,text,bigint) TO anon');
   assert.equal(await verdict(),false);
   await admin.query('REVOKE EXECUTE ON FUNCTION private.collect_native_ingress_consume(uuid,text,text,bigint) FROM anon; GRANT SELECT ON private.collect_native_ingress_nonce_uses TO authenticated');
   assert.equal(await verdict(),false);
   await admin.query('REVOKE SELECT ON private.collect_native_ingress_nonce_uses FROM authenticated; GRANT SELECT (profile_sha256) ON private.collect_native_ingress_nonce_uses TO authenticated');
   assert.equal(await verdict(),false);
  });
 }finally{
  cleaning=true;
  try{
   const ending=Promise.allSettled(clients.map(client=>client.end()));
   await Promise.race([ending,delay(3000,undefined,{ref:false})]);
   for(const client of clients){client.on('error',()=>{});client.connection?.stream?.destroy();}
   if(initAttempted&&!initConfirmed)throw Error('SYNTHETIC_INGRESS_INIT_UNCONFIRMED: '+root);
   if(startAttempted){
    if(serverPid===null)throw Error('SYNTHETIC_INGRESS_START_UNCONFIRMED: '+root);
    if(existsSync(join(data,'postmaster.pid'))){
     if(ownedPid()!==serverPid)throw Error('SYNTHETIC_INGRESS_SERVER_CHANGED: '+root);
     try{await run('pg_ctl',['-D',data,'-m','fast','-w','-t','10','stop'],{cleanup:true});}
     catch{throw Error('SYNTHETIC_INGRESS_STOP_UNCONFIRMED: '+root);}
    }
    if(existsSync(join(data,'postmaster.pid'))||alive(serverPid))throw Error('SYNTHETIC_INGRESS_STOP_UNCONFIRMED: '+root);
   }
   if(realpathSync(root)!==root||dirname(root)!==temporary)throw Error('SYNTHETIC_INGRESS_ROOT_CHANGED: '+root);
   rmSync(root,{recursive:true,force:true});
  }finally{
   clearTimeout(deadline);process.off('SIGTERM',onTerm);process.off('SIGINT',onInt);
  }
  checkInterrupted();
 }
});
