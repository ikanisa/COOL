import test from 'node:test';
import fs from 'node:fs';
import {syncBuiltinESMExports} from 'node:module';
import assert from 'node:assert/strict';
import {createHash,randomBytes} from 'node:crypto';
import {spawn,spawnSync} from 'node:child_process';
import {constants,closeSync,copyFileSync,mkdirSync,openSync,readFileSync,readdirSync,statSync,unlinkSync,writeFileSync,writeSync} from 'node:fs';
import net from 'node:net';
import tls from 'node:tls';
import {join} from 'node:path';
import pg from '../node_modules/pg/lib/index.js';
import {resolvePg17Bin,startOwnedPg17} from '../current-pg-transfer/test-support/owned-pg17.mjs';
import {authenticateSyntheticArchive,pipeSyntheticArchiveTo,PROJECT_BINDING,StreamArchiveError} from '../managed-cloud-backup-preparation/stream-archive.mjs';
import {BoundBackupError,checkPinnedProviderRoot,createSyntheticBoundBackup,dispatchManagedBackup} from './synthetic-bound-with-block-map.mjs';
import {runSyntheticGovernedAttempt,readSyntheticGovernedAttempt} from './synthetic-governor.mjs';
const {Client}=pg;
const sha=b=>createHash('sha256').update(b).digest('hex'),code=x=>e=>e instanceof BoundBackupError&&e.code===x;
function certificate(root,name,host){const key=join(root,name+'.key'),cert=join(root,name+'.crt');
 const p=spawnSync('/usr/bin/openssl',['req','-new','-x509','-newkey','rsa:2048','-nodes','-days','1','-keyout',key,'-out',cert,'-subj','/CN='+host,'-addext','subjectAltName=DNS:'+host],{stdio:'ignore',timeout:15000});assert.equal(p.status,0);return {key:readFileSync(key),cert:readFileSync(cert)};}
async function proxyFor(f,material){const sockets=new Set();let startup=false;const secure=tls.createServer(material,s=>{s.on('error',()=>{});s.on('data',b=>{if(b.includes(Buffer.from('default_transaction_read_only=on')))startup=true;});
 const backend=net.connect(join(f.socket,`.s.PGSQL.${f.port}`));sockets.add(s);sockets.add(backend);s.on('close',()=>sockets.delete(s));backend.on('close',()=>sockets.delete(backend));backend.on('error',()=>s.destroy());s.pipe(backend).pipe(s);});secure.on('tlsClientError',()=>{});
 const server=net.createServer(s=>{sockets.add(s);s.on('close',()=>sockets.delete(s));s.on('error',()=>{});let req=Buffer.alloc(0);const start=b=>{req=Buffer.concat([req,b]);if(req.length<8)return;s.removeListener('data',start);
  if(req.length!==8||req.readInt32BE(0)!==8||req.readInt32BE(4)!==80877103){s.destroy();return;}s.pause();s.write('S',()=>{secure.emit('connection',s);s.resume();});};s.on('data',start);});
 await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});return {port:server.address().port,readOnly:()=>startup,close:async()=>{for(const s of sockets)s.destroy();await new Promise(r=>server.close(r));secure.close();}};}
async function stalled(){const sockets=new Set(),server=net.createServer(s=>{sockets.add(s);s.on('close',()=>sockets.delete(s));s.on('error',()=>{});});await new Promise(r=>server.listen(0,'127.0.0.1',r));return {port:server.address().port,close:async()=>{for(const s of sockets)s.destroy();await new Promise(r=>server.close(r));}};}

test('production-bound preparation only connects to owned loopback TLS fixture',{timeout:180000},async t=>{
 const f=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_bound_backup_fixture'}),clients=[];let proxy,wrong,stall;
 const scratch=join(f.root,'scratch');mkdirSync(scratch,{mode:0o700});const passwordPath=join(scratch,'password'),keyPath=join(scratch,'key'),password=Buffer.from('synthetic:password\\private-fixture'),key=randomBytes(32);
 writeFileSync(passwordPath,password,{mode:0o600});writeFileSync(keyPath,key,{mode:0o600});
 async function connect(db='postgres'){const c=new Client({host:f.socket,port:f.port,database:db,user:'fixture_bootstrap'});await c.connect();clients.push(c);return c;}
 try{
  const admin=await connect();await admin.query("CREATE ROLE postgres LOGIN PASSWORD 'synthetic:password\\private-fixture'");await admin.query('ALTER DATABASE postgres OWNER TO postgres');await admin.query('CREATE DATABASE collect_restore_fixture OWNER fixture_bootstrap');
  await admin.query(`SET ROLE postgres;CREATE SCHEMA app;CREATE SCHEMA private;CREATE SCHEMA auth;CREATE SCHEMA storage;
   CREATE TABLE app.records(id integer PRIMARY KEY,value text);INSERT INTO app.records SELECT i,md5(i::text)||md5((i*17)::text)||md5((i*19)::text) FROM generate_series(1,250000) i;
   CREATE TABLE private.metadata(id integer PRIMARY KEY);INSERT INTO private.metadata VALUES(2);CREATE TABLE auth.users(id integer PRIMARY KEY);INSERT INTO auth.users VALUES(3);
   CREATE TABLE storage.objects(id integer PRIMARY KEY);INSERT INTO storage.objects VALUES(4);RESET ROLE`);
  writeFileSync(join(f.data,'pg_hba.conf'),'local postgres postgres scram-sha-256\nlocal all all trust\nhost all all 127.0.0.1/32 reject\n',{mode:0o600});await admin.query('SELECT pg_reload_conf()');
  const good=certificate(f.root,'good',PROJECT_BINDING.host),bad=certificate(f.root,'bad','wronghost');proxy=await proxyFor(f,good);wrong=await proxyFor(f,bad);stall=await stalled();
  const bin=resolvePg17Bin(),dumpToolSha256=sha(readFileSync(join(bin,'pg_dump'))),restoreToolSha256=sha(readFileSync(join(bin,'pg_restore'))),dumpExecutableSha256=sha(readFileSync(join(bin,'.pg_dump-wrapped'))),restoreExecutableSha256=sha(readFileSync(join(bin,'.pg_restore-wrapped')));
  const options=(changes={})=>({mode:'synthetic',scratchPath:scratch,fixturePort:proxy.port,fixtureCa:good.cert,fixtureCaSha256:sha(good.cert),signal:null,timeoutMs:30000,passwordPath,keyPath,dumpToolSha256,restoreToolSha256,dumpExecutableSha256,restoreExecutableSha256,...changes});
  const remaining=()=>readdirSync(scratch).sort();
  await t.test('exact project binding is checked but managed dispatch is unconditionally closed',async()=>{assert.deepEqual(checkPinnedProviderRoot().binding,PROJECT_BINDING);let reads=0;const x={mode:'managed'};Object.defineProperty(x,'passwordPath',{get(){reads++;throw Error();}});
   await assert.rejects(createSyntheticBoundBackup(x),code('managed_execution_closed'));await assert.rejects(dispatchManagedBackup(x),code('managed_execution_closed'));assert.equal(reads,0);});
  await t.test('bad CA, wrong host and bad password do not promote artifacts',async()=>{
   await assert.rejects(createSyntheticBoundBackup(options({fixtureCaSha256:'0'.repeat(64)})),code('invalid_input'));
   await assert.rejects(createSyntheticBoundBackup(options({fixturePort:wrong.port,fixtureCa:bad.cert,fixtureCaSha256:sha(bad.cert)})),code('dump_failed_or_warning'));
   writeFileSync(passwordPath,'incorrect',{mode:0o600});try{await assert.rejects(createSyntheticBoundBackup(options()),code('dump_failed_or_warning'));}finally{writeFileSync(passwordPath,password,{mode:0o600});}
   assert.deepEqual(remaining(),['key','password']);
  });
  await t.test('unresponsive TLS endpoint is stopped with no promoted artifact',async()=>{await assert.rejects(createSyntheticBoundBackup(options({fixturePort:stall.port,timeoutMs:1000})),code('dump_timed_out'));assert.deepEqual(remaining(),['key','password']);});
  await t.test('link-time ciphertext mutation is detected and retained unconfirmed',async()=>{
   const original=fs.linkSync;let changed=false;fs.linkSync=(src,dst)=>{
    if(typeof src==='string'&&src.endsWith('.partial')){const fd=fs.openSync(src,'r+');try{const b=Buffer.alloc(1);assert.equal(fs.readSync(fd,b,0,1,64),1);b[0]^=1;assert.equal(fs.writeSync(fd,b,0,1,64),1);changed=true;}finally{fs.closeSync(fd);}}
    return original(src,dst);
   };syncBuiltinESMExports();
   try{await assert.rejects(createSyntheticBoundBackup(options()),code('promotion_integrity_unconfirmed'));assert.equal(changed,true);
    const artifacts=readdirSync(scratch).filter(x=>x.endsWith('.partial')||x.endsWith('.pgc.gcm'));assert.equal(artifacts.length,2);
    const fd=openSync(join(scratch,artifacts.find(x=>x.endsWith('.pgc.gcm'))),'r');try{await assert.rejects(authenticateSyntheticArchive({mode:'synthetic',fd,key,signal:null}),e=>e instanceof StreamArchiveError&&e.code==='archive_authentication_failed');}finally{closeSync(fd);}
   }finally{fs.linkSync=original;syncBuiltinESMExports();for(const name of readdirSync(scratch).filter(x=>x.endsWith('.partial')||x.endsWith('.pgc.gcm')))unlinkSync(join(scratch,name));}
  });
  await t.test('large encrypted archive authenticates and restores in an owned database',async()=>{const root=join(f.root,'journal');mkdirSync(root,{mode:0o700});const config=options();config.fixtureCaBase64=config.fixtureCa.toString('base64');delete config.fixtureCa;const request={mode:'synthetic',root,operationId:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',deadlineMs:60000,action:'synthetic_backup',config};
   const r=await runSyntheticGovernedAttempt(request);assert.equal(r.status,'completed');assert.equal(proxy.readOnly(),true);
   assert.deepEqual(await readSyntheticGovernedAttempt({...request,action:'read'}),{status:'completed',dispatchAllowed:false,artifactSha256:r.artifactSha256});
   const artifactPath=join(scratch,readdirSync(scratch).find(x=>x.endsWith('.pgc.gcm')));assert(statSync(artifactPath).size>8*1024*1024);
   const encrypted=readFileSync(artifactPath);assert.equal(sha(encrypted),r.artifactSha256);assert(!encrypted.includes(password));assert(!encrypted.includes(Buffer.from('PGDMP')));assert.equal(statSync(artifactPath).mode&0o777,0o600);
   const corrupt=join(scratch,'corrupt.enc');copyFileSync(artifactPath,corrupt);const cfd=openSync(corrupt,'r+'),last=Buffer.from([encrypted.at(-1)^1]);writeSync(cfd,last,0,1,encrypted.length-1);closeSync(cfd);
   let fd=openSync(corrupt,'r');try{await assert.rejects(authenticateSyntheticArchive({mode:'synthetic',fd,key,signal:null}),e=>e instanceof StreamArchiveError&&e.code==='archive_authentication_failed');}finally{closeSync(fd);}
   fd=openSync(artifactPath,'r');const restore=spawn(join(bin,'pg_restore'),['--exit-on-error','--no-owner','--no-acl','-h',f.socket,'-p',String(f.port),'-U','fixture_bootstrap','-d','collect_restore_fixture'],{stdio:['pipe','ignore','pipe'],env:{PATH:'/usr/bin:/bin',LC_ALL:'C'}});
   let error='';restore.stderr.on('data',b=>error+=b);const closed=new Promise(resolve=>restore.on('close',(status,signal)=>resolve({status,signal})));
   try{await pipeSyntheticArchiveTo({mode:'synthetic',fd,key,writable:restore.stdin,signal:null});assert.deepEqual(await closed,{status:0,signal:null},error);}finally{closeSync(fd);}
   const target=await connect('collect_restore_fixture');const counts=await target.query('SELECT (SELECT count(*)::int FROM app.records) app,(SELECT count(*)::int FROM private.metadata) private,(SELECT count(*)::int FROM auth.users) auth,(SELECT count(*)::int FROM storage.objects) storage');
   assert.deepEqual(counts.rows[0],{app:250000,private:1,auth:1,storage:1});
   const root2=join(f.root,'journal-missing-ack');mkdirSync(root2,{mode:0o700});const second={...request,root:root2,operationId:'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',action:'synthetic_backup_missing_ack'};
   assert.deepEqual(await runSyntheticGovernedAttempt(second),{status:'acknowledgement_missing_do_not_retry',dispatchAllowed:false});
   const reconciled=await readSyntheticGovernedAttempt({...second,action:'read'});assert.equal(reconciled.status,'completed');assert.equal(reconciled.dispatchAllowed,false);
   const secondArtifact=join(scratch,readdirSync(scratch).find(x=>x.endsWith('.pgc.gcm')&&join(scratch,x)!==artifactPath));assert.equal(sha(readFileSync(secondArtifact)),reconciled.artifactSha256);
   assert.equal((await runSyntheticGovernedAttempt(second)).status,'worker_outcome_unconfirmed');
   unlinkSync(corrupt);unlinkSync(artifactPath);unlinkSync(secondArtifact);
  });
 }finally{if(proxy)await proxy.close();if(wrong)await wrong.close();if(stall)await stall.close();await Promise.allSettled(clients.map(c=>c.end()));password.fill(0);key.fill(0);const result=await f.close();assert.equal(result.removed,true);}
});
