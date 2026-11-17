import test from 'node:test';
import assert from 'node:assert/strict';
import {createDecipheriv,createHash,randomBytes,randomUUID} from 'node:crypto';
import crypto from 'node:crypto';
import {ChildProcess,spawn,spawnSync} from 'node:child_process';
import {EventEmitter,getEventListeners} from 'node:events';
import {syncBuiltinESMExports} from 'node:module';
import {constants,chmodSync,closeSync,copyFileSync,createReadStream,mkdirSync,openSync,readFileSync,readdirSync,statSync,unlinkSync,writeFileSync,writeSync} from 'node:fs';
import net from 'node:net';
import tls from 'node:tls';
import {join} from 'node:path';
import {pipeline} from 'node:stream/promises';
import pg from '../node_modules/pg/lib/index.js';
import {resolvePg17Bin,startOwnedPg17} from '../current-pg-transfer/test-support/owned-pg17.mjs';
import {createSyntheticEncryptedBackup,inspectSyntheticEncryptedBackup,SyntheticBackupError,syntheticTestHelpers} from './synthetic-backup.mjs';
const {Client}=pg;
const sha=b=>createHash('sha256').update(b).digest('hex');
const code=x=>e=>e instanceof SyntheticBackupError&&e.code===x;
const password=Buffer.from('synthetic:password\\private-fixture');
function certificate(root,name,host){
 const key=join(root,name+'.key'),cert=join(root,name+'.crt');
 const p=spawnSync('/usr/bin/openssl',['req','-new','-x509','-newkey','rsa:2048','-nodes','-days','1','-keyout',key,'-out',cert,'-subj','/CN='+host,'-addext','subjectAltName=DNS:'+host],{stdio:'ignore',timeout:15000});
 assert.equal(p.status,0);return {key:readFileSync(key),cert:readFileSync(cert)};
}
async function proxyFor(f,material){
 const sockets=new Set();let startupReadOnly=false;const secure=tls.createServer(material,s=>{
  sockets.add(s);s.on('close',()=>sockets.delete(s));s.on('error',()=>{});
  s.on('data',b=>{if(b.includes(Buffer.from('default_transaction_read_only=on')))startupReadOnly=true;});
  const backend=net.connect(join(f.socket,`.s.PGSQL.${f.port}`));sockets.add(backend);backend.on('close',()=>sockets.delete(backend));backend.on('error',()=>s.destroy());s.pipe(backend).pipe(s);
 });
 secure.on('tlsClientError',()=>{});
 const proxy=net.createServer(socket=>{sockets.add(socket);socket.on('close',()=>sockets.delete(socket));socket.on('error',()=>{});
  let message=Buffer.alloc(0);const first=b=>{message=Buffer.concat([message,b]);if(message.length<8)return;
   socket.removeListener('data',first);if(message.length!==8||message.readInt32BE(0)!==8||message.readInt32BE(4)!==80877103){socket.destroy();return;}
   socket.pause();socket.write('S',()=>{secure.emit('connection',socket);socket.resume();});};socket.on('data',first);
 });
 await new Promise((resolve,reject)=>{proxy.once('error',reject);proxy.listen(0,'127.0.0.1',resolve);});
 return {port:proxy.address().port,hasReadOnlyStartup:()=>startupReadOnly,close:async()=>{for(const s of sockets)s.destroy();await new Promise(r=>proxy.close(r));secure.close();}};
}
function inputFd(scratch,bytes){const path=join(scratch,'input-'+randomUUID());const fd=openSync(path,constants.O_CREAT|constants.O_EXCL|constants.O_RDWR,0o600);unlinkSync(path);writeSync(fd,bytes,0,bytes.length,0);return fd;}
async function restoreIntoFixture(f,artifact,key){
 const fd=openSync(artifact,'r'),header=Buffer.alloc(25),tag=Buffer.alloc(16),size=statSync(artifact).size;
 const fs=await import('node:fs');fs.readSync(fd,header,0,header.length,0);fs.readSync(fd,tag,0,tag.length,size-16);
 assert.equal(header.subarray(0,13).toString(),'COLLECTPGGCM1');
 const d=createDecipheriv('aes-256-gcm',key,header.subarray(13));d.setAAD(header);d.setAuthTag(tag);
 const child=spawn(join(resolvePg17Bin(),'pg_restore'),['--exit-on-error','--no-owner','--no-acl','-h',f.socket,'-p',String(f.port),'-U','fixture_bootstrap','-d','collect_restore_fixture'],{stdio:['pipe','ignore','pipe'],env:{PATH:'/usr/bin:/bin',LC_ALL:'C'}});
 let stderr='';child.stderr.on('data',x=>stderr+=x);const done=new Promise(resolve=>child.on('close',(exit,signal)=>resolve({exit,signal})));
 await pipeline(createReadStream(null,{fd,autoClose:false,start:25,end:size-17}),d,child.stdin);const result=await done;closeSync(fd);
 assert.deepEqual(result,{exit:0,signal:null},stderr);
}

test('synthetic encrypted custom backup on loopback TLS',{timeout:180000},async t=>{
 const f=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_cloud_backup_fixture'}),clients=[],fds=[];let proxy,wrongProxy;
 const scratch=join(f.root,'scratch');mkdirSync(scratch,{mode:0o700});
 async function connect(db='postgres'){const c=new Client({host:f.socket,port:f.port,database:db,user:'fixture_bootstrap'});await c.connect();clients.push(c);return c;}
 try{
  const admin=await connect();await admin.query("CREATE ROLE fixture_backup LOGIN PASSWORD 'synthetic:password\\private-fixture'");
  await admin.query('CREATE DATABASE collect_backup_fixture OWNER fixture_backup');await admin.query('CREATE DATABASE collect_restore_fixture OWNER fixture_bootstrap');
  const source=await connect('collect_backup_fixture');
  await source.query(`SET ROLE fixture_backup;
   CREATE SCHEMA app;CREATE SCHEMA private;CREATE SCHEMA auth;CREATE SCHEMA storage;
   CREATE TABLE app.records(id integer PRIMARY KEY,value text);INSERT INTO app.records VALUES(1,'sensitive-fixture-never-log');
   CREATE TABLE private.metadata(id integer PRIMARY KEY);INSERT INTO private.metadata VALUES(2);
   CREATE TABLE auth.users(id integer PRIMARY KEY);INSERT INTO auth.users VALUES(3);
   CREATE TABLE storage.objects(id integer PRIMARY KEY);INSERT INTO storage.objects VALUES(4);RESET ROLE`);
  writeFileSync(join(f.data,'pg_hba.conf'),'local collect_backup_fixture fixture_backup scram-sha-256\nlocal all all trust\nhost all all 127.0.0.1/32 reject\n',{mode:0o600});
  await admin.query('SELECT pg_reload_conf()');
  const good=certificate(f.root,'ca-good','localhost'),bad=certificate(f.root,'ca-wrong','wronghost');proxy=await proxyFor(f,good);wrongProxy=await proxyFor(f,bad);
  const bin=resolvePg17Bin(),dumpToolSha256=sha(readFileSync(join(bin,'pg_dump'))),restoreToolSha256=sha(readFileSync(join(bin,'pg_restore'))),
   dumpExecutableSha256=sha(readFileSync(join(bin,'.pg_dump-wrapped'))),restoreExecutableSha256=sha(readFileSync(join(bin,'.pg_restore-wrapped'))),key=randomBytes(32);
  function options({pass=password,material=good,port=proxy.port}={}){const passwordFd=inputFd(scratch,pass),keyFd=inputFd(scratch,key),caFd=inputFd(scratch,material.cert);fds.push(passwordFd,keyFd,caFd);
   return {mode:'synthetic',scratchPath:scratch,port,passwordFd,keyFd,caFd,caSha256:sha(material.cert),dumpToolSha256,restoreToolSha256,dumpExecutableSha256,restoreExecutableSha256};}
  await t.test('managed mode closes before reading supplied descriptors',async()=>{
   await assert.rejects(createSyntheticEncryptedBackup({mode:'managed',passwordFd:-1,keyFd:-1,caFd:-1}),code('managed_execution_closed'));
   await assert.rejects(inspectSyntheticEncryptedBackup({mode:'managed',keyFd:-1}),code('managed_execution_closed'));
  });
  await t.test('already-aborted requests do not read inputs and open pipes are refused',async()=>{
   const path=join(scratch,'fixture-fifo');assert.equal(spawnSync('/usr/bin/mkfifo',[path],{stdio:'ignore'}).status,0);
   const fifo=openSync(path,constants.O_RDWR|constants.O_NONBLOCK),ctl=new AbortController();ctl.abort();
   try{const a=options();a.keyFd=fifo;a.signal=ctl.signal;await assert.rejects(createSyntheticEncryptedBackup(a),code('aborted'));
    const b=options();b.keyFd=fifo;await assert.rejects(createSyntheticEncryptedBackup(b),code('input_fd_refused'));
   }finally{closeSync(fifo);unlinkSync(path);}
   assert.equal(readdirSync(scratch).length,0);
  });
  await t.test('child errors do not prove closure and failed setup wipes plaintext',async()=>{
   const fake=new EventEmitter();fake.pid=123;fake.exitCode=null;fake.signalCode=null;const signals=[];fake.kill=s=>{signals.push(s);return true;};
   const closed=syntheticTestHelpers.childOutcome(fake);let finished=false;closed.then(()=>{finished=true;});fake.emit('error',Error('synthetic'));
   await new Promise(r=>setTimeout(r,10));assert.equal(finished,false);
   assert.equal(await syntheticTestHelpers.stopAndWait(fake,closed),null);assert.deepEqual(signals,['SIGTERM','SIGKILL']);assert.equal(finished,false);
   fake.emit('close',null,'SIGKILL');assert.deepEqual(await closed,{code:null,signal:'SIGKILL',error:true});
   const plain=Buffer.from('sensitive-fixture');await assert.rejects(syntheticTestHelpers.withWipedBuffer(plain,()=>{throw Error('synthetic setup failure');}));assert(plain.every(b=>b===0));
  });
  await t.test('rejects unpinned CA and wrong host certificate',async()=>{
   const a=options();a.caSha256='0'.repeat(64);await assert.rejects(createSyntheticEncryptedBackup(a),code('ca_pin_mismatch'));
   const b=options();b.dumpExecutableSha256='0'.repeat(64);await assert.rejects(createSyntheticEncryptedBackup(b),code('tool_refused'));
   await assert.rejects(createSyntheticEncryptedBackup(options({material:bad,port:wrongProxy.port})),code('dump_failed_or_warning'));
   assert.equal(readdirSync(scratch).length,0);
  });
  await t.test('rejects wrong password and removes incomplete ciphertext',async()=>{
   await assert.rejects(createSyntheticEncryptedBackup(options({pass:Buffer.from('incorrect')})),code('dump_failed_or_warning'));
   assert.equal(readdirSync(scratch).length,0);
  });
  await t.test('aborted dump never promotes a partial artifact',async()=>{
   const ctl=new AbortController(),o=options();o.signal=ctl.signal;const p=createSyntheticEncryptedBackup(o);setTimeout(()=>ctl.abort(),10);
   await assert.rejects(p,code('aborted'));assert.equal(readdirSync(scratch).length,0);
  });
  await t.test('synchronous cipher setup failure clears timer and abort listener',async()=>{
   const ctl=new AbortController(),o=options();o.signal=ctl.signal;const set=globalThis.setTimeout,clear=globalThis.clearTimeout,create=crypto.createCipheriv,timers=new Set();
   let leakedTimers,leakedListeners;
   globalThis.setTimeout=(fn,ms,...args)=>{const id=set(fn,ms,...args);if(ms===30000)timers.add(id);return id;};
   globalThis.clearTimeout=id=>{timers.delete(id);return clear(id);};
   crypto.createCipheriv=()=>{throw Error('synthetic cipher setup failure');};syncBuiltinESMExports();
   try{await assert.rejects(createSyntheticEncryptedBackup(o),code('synthetic_backup_failed'));leakedTimers=timers.size;leakedListeners=getEventListeners(ctl.signal,'abort').length;}
   finally{for(const id of timers)clear(id);globalThis.setTimeout=set;globalThis.clearTimeout=clear;crypto.createCipheriv=create;syncBuiltinESMExports();}
   assert.deepEqual({timers:leakedTimers,listeners:leakedListeners},{timers:0,listeners:0});assert.equal(readdirSync(scratch).length,0);
  });
  await t.test('a missing required schema cannot be promoted',async()=>{
   const kill=ChildProcess.prototype.kill,signalsAfterExit=[];ChildProcess.prototype.kill=function(...args){if(this.exitCode!==null||this.signalCode!==null)signalsAfterExit.push(args[0]);return kill.apply(this,args);};
   await source.query('DROP SCHEMA storage CASCADE');
   try{await assert.rejects(createSyntheticEncryptedBackup(options()),code('required_schemas_missing'));assert.equal(readdirSync(scratch).length,0);}
   finally{ChildProcess.prototype.kill=kill;await source.query('SET ROLE fixture_backup;CREATE SCHEMA storage;CREATE TABLE storage.objects(id integer PRIMARY KEY);INSERT INTO storage.objects VALUES(4);RESET ROLE');}
   assert.deepEqual(signalsAfterExit,[]);
  });
  await t.test('exports encrypted archive, authenticates listing, rejects tampering and restores owned fixture',async()=>{
   const result=await createSyntheticEncryptedBackup(options());assert.equal(result.status,'synthetic_backup_inspected');assert.equal(result.requiredSchemas,4);
   assert.equal(proxy.hasReadOnlyStartup(),true);
   assert.equal(statSync(result.artifactPath).mode&0o777,0o600);const bytes=readFileSync(result.artifactPath);
   assert.equal(sha(bytes),result.ciphertextSha256);assert.equal(bytes.includes(Buffer.from('PGDMP')),false);assert.equal(bytes.includes(password),false);assert.equal(bytes.includes(Buffer.from('sensitive-fixture-never-log')),false);
   const keyFd=inputFd(scratch,key);fds.push(keyFd);assert.equal((await inspectSyntheticEncryptedBackup({mode:'synthetic',scratchPath:scratch,artifactPath:result.artifactPath,keyFd,restoreToolSha256,restoreExecutableSha256})).status,'synthetic_backup_inspected');
   const wrongKeyFd=inputFd(scratch,randomBytes(32));fds.push(wrongKeyFd);await assert.rejects(inspectSyntheticEncryptedBackup({mode:'synthetic',scratchPath:scratch,artifactPath:result.artifactPath,keyFd:wrongKeyFd,restoreToolSha256,restoreExecutableSha256}),code('archive_authentication_failed'));
   const tampered=join(scratch,'backup-'+randomUUID()+'.pgc.gcm');copyFileSync(result.artifactPath,tampered);const fd=openSync(tampered,'r+'),last=Buffer.from([bytes.at(-1)^1]);writeSync(fd,last,0,1,bytes.length-1);closeSync(fd);
   const badKeyFd=inputFd(scratch,key);fds.push(badKeyFd);await assert.rejects(inspectSyntheticEncryptedBackup({mode:'synthetic',scratchPath:scratch,artifactPath:tampered,keyFd:badKeyFd,restoreToolSha256,restoreExecutableSha256}),code('archive_authentication_failed'));
   const fakeBin=join(f.root,'fake-bin');mkdirSync(fakeBin,{mode:0o700});
   for(const n of ['initdb','pg_ctl','pg_isready','postgres']){const p=join(fakeBin,n);writeFileSync(p,"#!/bin/sh\nprintf 'postgres (PostgreSQL) 17.11\\n'\n",{mode:0o700});chmodSync(p,0o700);}
   const wrapper=join(fakeBin,'pg_restore'),fakeExec=join(fakeBin,'.pg_restore-wrapped');
   writeFileSync(wrapper,'#!/bin/sh\nexec "$(dirname "$0")/.pg_restore-wrapped" "$@"\n',{mode:0o700});
   writeFileSync(fakeExec,`#!/bin/sh\nexec '${process.execPath.replaceAll("'","'\\''")}' -e 'process.on("SIGTERM",()=>{});process.stdin.resume();setInterval(()=>{},1000)'\n`,{mode:0o700});
   const before=process.env.COLLECT_SYNTHETIC_PG_BIN,kill=ChildProcess.prototype.kill,signals=[];let inspectorPid;
   ChildProcess.prototype.kill=function(sig){if(this.spawnfile===wrapper){inspectorPid=this.pid;signals.push([sig,this.exitCode,this.signalCode]);}return kill.call(this,sig);};
   process.env.COLLECT_SYNTHETIC_PG_BIN=fakeBin;
   try{const fk=inputFd(scratch,key);fds.push(fk);await assert.rejects(inspectSyntheticEncryptedBackup({mode:'synthetic',scratchPath:scratch,artifactPath:result.artifactPath,keyFd:fk,restoreToolSha256:sha(readFileSync(wrapper)),restoreExecutableSha256:sha(readFileSync(fakeExec))}),code('inspection_timed_out'));
    assert.deepEqual(signals.map(x=>x[0]),['SIGTERM','SIGKILL']);assert(signals.every(x=>x[1]===null&&x[2]===null));assert.throws(()=>process.kill(inspectorPid,0),e=>e.code==='ESRCH');
   }finally{ChildProcess.prototype.kill=kill;if(before===undefined)delete process.env.COLLECT_SYNTHETIC_PG_BIN;else process.env.COLLECT_SYNTHETIC_PG_BIN=before;}
   await restoreIntoFixture(f,result.artifactPath,key);const restored=await connect('collect_restore_fixture');
   const counts=await restored.query('SELECT (SELECT count(*)::int FROM app.records) app,(SELECT count(*)::int FROM private.metadata) private,(SELECT count(*)::int FROM auth.users) auth,(SELECT count(*)::int FROM storage.objects) storage');
   assert.deepEqual(counts.rows[0],{app:1,private:1,auth:1,storage:1});unlinkSync(tampered);unlinkSync(result.artifactPath);
  });
 }finally{for(const fd of fds)try{closeSync(fd);}catch{};if(proxy)await proxy.close();if(wrongProxy)await wrongProxy.close();await Promise.allSettled(clients.map(c=>c.end()));const result=await f.close();assert.equal(result.removed,true);}
});
