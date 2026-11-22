import test from 'node:test';
import assert from 'node:assert/strict';
import {chmod,mkdtemp,readFile,readdir,rm,symlink,writeFile,open} from 'node:fs/promises';
import {spawn} from 'node:child_process';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {AtomicMigrationError,pinnedMigrationIdentities} from '../atomic_cloud_migration.mjs';
import {FORMAT,parseCanonicalInput,runRequest,validateRequest,assertCleanEnvironment} from './operator-core.mjs';
import {loadProviderRoot} from './provider-ca.mjs';
const source=pinnedMigrationIdentities()[14],PROJECT='rrlduytparvsjfmegalh';
const request=(action='apply')=>({format:FORMAT,action,connection:{host:`db.${PROJECT}.supabase.co`,user:'postgres',password:'synthetic-secret'},migration:{version:source.version,sourceSha256:source.sha256,preimageSha256:action==='capture'?null:'b'.repeat(64)}});
async function temp(){const d=await mkdtemp(join(await import('node:fs/promises').then(x=>x.realpath(tmpdir())),'collect-op-test-'));await chmod(d,0o700);return d;}
function fake({pid=101,gone=true}={}){
 const record={calls:[],ended:false,opts:null};
 const factory=opts=>{record.opts=opts;return {on(){},async connect(){record.calls.push('connect');},connectionParameters:opts,
  async query(sql){record.calls.push(sql);return {rows:[sql.includes('pg_stat_activity')?{gone}:{pid}]};},
  connection:{stream:{encrypted:true,authorized:true,servername:opts.host,destroy(){record.calls.push('destroy');}}},async end(){record.ended=true;}};};
 return {record,factory};
}
const fakeApi=(extra={})=>({capturePinnedPreimage:async()=>({sha256:'b'.repeat(64),preimage:{synthetic:true}}),
 executePinnedMigration:async(_c,a)=>({status:'committed',projectRef:PROJECT,version:a.version,sourceSha256:a.expectedSha}),
 reconcilePinnedMigration:async(_c,a)=>({status:'recorded',projectRef:PROJECT,version:a.version,sourceSha256:a.expectedSha}),...extra});
const code=c=>e=>e?.code===c&&!String(e).includes('synthetic-secret');

test('canonical input, exact project and clean environment are required before connecting',()=>{
 const r=request();assert.deepEqual(parseCanonicalInput(JSON.stringify(r)),r);
 assert.throws(()=>parseCanonicalInput(JSON.stringify(r)+'\n'),code('invalid_request'));
 assert.throws(()=>parseCanonicalInput('{"format":"a","format":"b"}'),code('invalid_request'));
 for(const changed of [
  {...r,connection:{...r.connection,host:'attacker.example'}},
  {...r,connection:{...r.connection,host:'aws-1-eu-north-1.pooler.supabase.com',user:`postgres.${PROJECT}`}},
  {...r,connection:{...r.connection,user:'cli_login_postgres'}},
  {...r,connection:{...r.connection,host:'aws-0-eu-north-1.pooler.supabase.com',user:'other.'+PROJECT}},
  {...r,migration:{...r.migration,sourceSha256:'0'.repeat(64)}},
  {...r,migration:{...r.migration,preimageSha256:null}},
 ])assert.throws(()=>validateRequest(changed),code('invalid_request'));
 for(const key of ['PGOPTIONS','PGSSLMODE','NODE_OPTIONS','NODE_EXTRA_CA_CERTS','NODE_TLS_REJECT_UNAUTHORIZED','SSL_CERT_FILE','LD_AUDIT','LD_LIBRARY_PATH','DYLD_INSERT_LIBRARIES'])
  assert.throws(()=>assertCleanEnvironment({[key]:'synthetic'}),code('unclean_environment'));
});

test('capture uses verified TLS options and does not create a mutation journal',async()=>{
 const root=await temp(),f=fake(),r=request('capture');
 try{const result=await runRequest(r,{journalRoot:root,makeClient:f.factory,api:fakeApi(),environment:{}});
  assert.equal(result.status,'captured');assert.equal(result.result.sha256,'b'.repeat(64));
  assert.deepEqual(await readdir(root),[]);assert.equal(f.record.opts.ssl.rejectUnauthorized,true);
  assert.equal(f.record.opts.ssl.ca,loadProviderRoot());
  assert.equal(f.record.opts.database,'postgres');assert.equal(f.record.opts.port,5432);assert.equal(r.connection.password,'');
 }finally{await rm(root,{recursive:true,force:true});}
});

test('invalid provider CA is refused before connection or one-use apply intent',async()=>{
 const root=await temp();let connected=false;
 try{
  for(const rootLoader of [()=>{throw Error('missing');},()=> 'invalid']){
   const r=request();
   await assert.rejects(runRequest(r,{journalRoot:root,rootLoader,makeClient:()=>{connected=true;},environment:{}}),code('connection_unavailable'));
   assert.equal(r.connection.password,'');assert.equal(connected,false);assert.deepEqual(await readdir(root),[]);
  }
 }finally{await rm(root,{recursive:true,force:true});}
});

test('operator refuses altered CA or hostname verification before database work',async()=>{
 const root=await temp();
 try{
  for(const change of [ssl=>{ssl.ca='synthetic-untrusted-ca';},ssl=>{ssl.secureContext={};},ssl=>{ssl.checkServerIdentity=()=>undefined;},ssl=>{delete ssl.ca; }]){
   const f=fake();let invoked=false;
   const factory=opts=>{const client=f.factory(opts);client.connectionParameters.ssl={...opts.ssl};change(client.connectionParameters.ssl);return client;};
   await assert.rejects(runRequest(request('capture'),{journalRoot:root,makeClient:factory,
    api:fakeApi({capturePinnedPreimage:async()=>{invoked=true;}}),environment:{}}),code('connection_unavailable'));
   assert.equal(invoked,false);
  }
 }finally{await rm(root,{recursive:true,force:true});}
});

test('unverified TLS is refused before any database query',async()=>{
 const root=await temp(),f=fake();let invoked=false;
 try{const factory=opts=>{const c=f.factory(opts);c.connection.stream.authorized=false;return c;};
  await assert.rejects(runRequest(request('capture'),{journalRoot:root,makeClient:factory,api:fakeApi({capturePinnedPreimage:async()=>{invoked=true;}}),environment:{}}),code('connection_unavailable'));
  assert.equal(invoked,false);assert.equal(f.record.calls.some(x=>x.includes('SELECT')),false);
 }finally{await rm(root,{recursive:true,force:true});}
});

test('one-use durable intent and backend pin precede execution; duplicates never reach the database',async()=>{
 const root=await temp(),f=fake(),r=request();let called=0;
 try{const api=fakeApi({executePinnedMigration:async(_client,args)=>{called++;
   assert.equal(args.expectedBackendPid,101);const dir=join(root,source.version);
   assert.equal(JSON.parse(await readFile(join(dir,'intent.json'),'utf8')).preimageSha256,'b'.repeat(64));
   assert.equal(JSON.parse(await readFile(join(dir,'backend.json'),'utf8')).backendPid,101);
   return {status:'committed',projectRef:PROJECT,version:args.version,sourceSha256:args.expectedSha};}});
  const outcome=await runRequest(r,{journalRoot:root,makeClient:f.factory,api,environment:{}});
  assert.equal(outcome.status,'committed');assert.equal(called,1);assert.equal(r.connection.password,'');
  const names=await readdir(join(root,source.version));assert.deepEqual(names.sort(),['backend.json','intent.json','outcome.json']);
  for(const name of names)assert.doesNotMatch(await readFile(join(root,source.version,name),'utf8'),/synthetic-secret/);
  await assert.rejects(runRequest(request(),{journalRoot:root,makeClient:()=>{throw Error('must not connect');},api,environment:{}}),code('apply_already_attempted'));
 }finally{await rm(root,{recursive:true,force:true});}
});

test('lost commit is retained as unconfirmed and reconciliation refuses a still-present prior backend',async()=>{
 const root=await temp(),f=fake(),r=request();let reconciliations=0;
 try{const api=fakeApi({executePinnedMigration:async()=>{throw new AtomicMigrationError('commit_unconfirmed');},
   reconcilePinnedMigration:async(_c,a)=>{reconciliations++;assert.equal(a.priorBackendPid,101);return {status:'recorded',projectRef:PROJECT,version:a.version,sourceSha256:a.expectedSha};}});
  const result=await runRequest(r,{journalRoot:root,makeClient:f.factory,api,environment:{}});
  assert.equal(result.status,'unconfirmed');assert.equal(result.code,'commit_unconfirmed');
  await assert.rejects(runRequest(request('reconcile'),{journalRoot:root,makeClient:fake({pid:102,gone:false}).factory,api,environment:{}}),code('prior_backend_still_present'));
  assert.equal(reconciliations,0);
  const recovered=await runRequest(request('reconcile'),{journalRoot:root,makeClient:fake({pid:102,gone:true}).factory,api,environment:{}});
  assert.equal(recovered.status,'recorded');assert.equal(reconciliations,1);
  const files=await readdir(join(root,source.version));assert.equal(files.filter(x=>x.endsWith('.intent.json')).length,2);assert.equal(files.filter(x=>x.endsWith('.outcome.json')).length,1);
 }finally{await rm(root,{recursive:true,force:true});}
});

test('unknown errors and output-record failure cannot be reported as success',async()=>{
 const root=await temp(),f=fake();
 try{const api=fakeApi({executePinnedMigration:async()=>{throw Error('synthetic-secret server text');}});
  const result=await runRequest(request(),{journalRoot:root,makeClient:f.factory,api,environment:{}});
  assert.equal(result.status,'unconfirmed');assert.equal(result.code,'operator_unconfirmed');assert.doesNotMatch(JSON.stringify(result),/synthetic-secret/);
 }finally{await rm(root,{recursive:true,force:true});}
 const root2=await temp();
 try{const api=fakeApi({executePinnedMigration:async(_c,a)=>{await chmod(join(root2,source.version),0o500);return {status:'committed',projectRef:PROJECT,version:a.version,sourceSha256:a.expectedSha};}});
  await assert.rejects(runRequest(request(),{journalRoot:root2,makeClient:fake().factory,api,environment:{}}),code('journal_outcome_unconfirmed'));
  await chmod(join(root2,source.version),0o700);assert.deepEqual((await readdir(join(root2,source.version))).sort(),['backend.json','intent.json']);
 }finally{await chmod(join(root2,source.version),0o700).catch(()=>{});await rm(root2,{recursive:true,force:true});}
});

test('reconciliation result persistence failure stays unconfirmed and remains retryable as a read',async()=>{
 const root=await temp();
 try{
  await runRequest(request(),{journalRoot:root,makeClient:fake().factory,api:fakeApi(),environment:{}});
  const api=fakeApi({reconcilePinnedMigration:async(_client,args)=>{
   await chmod(join(root,source.version),0o500);
   return {status:'recorded',projectRef:PROJECT,version:args.version,sourceSha256:args.expectedSha};
  }});
  await assert.rejects(runRequest(request('reconcile'),{journalRoot:root,makeClient:fake({pid:102,gone:true}).factory,api,environment:{}}),
   e=>e.code==='journal_outcome_unconfirmed'&&e.version===source.version&&e.backendPid===101);
  await chmod(join(root,source.version),0o700);
  const later=await runRequest(request('reconcile'),{journalRoot:root,makeClient:fake({pid:103,gone:true}).factory,api:fakeApi(),environment:{}});
  assert.equal(later.status,'recorded');
 }finally{await chmod(join(root,source.version),0o700).catch(()=>{});await rm(root,{recursive:true,force:true});}
});

test('journal roots and records cannot be shared, symlinked or rebound to another endpoint',async()=>{
 const root=await temp(),link=root+'-link';
 try{await chmod(root,0o755);await assert.rejects(runRequest(request(),{journalRoot:root,makeClient:fake().factory,api:fakeApi(),environment:{}}),code('journal_unavailable'));
  await chmod(root,0o700);await symlink(root,link);await assert.rejects(runRequest(request(),{journalRoot:link,makeClient:fake().factory,api:fakeApi(),environment:{}}),code('journal_unavailable'));
  await runRequest(request(),{journalRoot:root,makeClient:fake().factory,api:fakeApi(),environment:{}});
  const changed=request('reconcile');changed.connection.host='aws-0-eu-north-1.pooler.supabase.com';changed.connection.user='postgres.'+PROJECT;
  await assert.rejects(runRequest(changed,{journalRoot:root,makeClient:()=>{throw Error('must not connect');},api:fakeApi(),environment:{}}),code('journal_mismatch'));
 }finally{await rm(link,{force:true});await rm(root,{recursive:true,force:true});}
});

test('CLI refuses regular-file stdin and suppresses credential contents',async()=>{
 const root=await temp(),path=join(root,'input');const childPath=new URL('./operator.mjs',import.meta.url);
 try{await writeFile(path,JSON.stringify(request()),{mode:0o600});const fd=await open(path,'r');
  const result=await new Promise(resolve=>{const p=spawn(process.execPath,[childPath.pathname,root],{stdio:[fd.fd,'pipe','pipe'],env:{PATH:'/usr/bin:/bin'}});let out='',err='';p.stdout.on('data',x=>out+=x);p.stderr.on('data',x=>err+=x);p.on('close',exit=>resolve({exit,out,err}));});await fd.close();
  assert.equal(result.exit,1);assert.equal(JSON.parse(result.out).code,'invalid_request');assert.doesNotMatch(result.out+result.err,/synthetic-secret/);
 }finally{await rm(root,{recursive:true,force:true});}
});
