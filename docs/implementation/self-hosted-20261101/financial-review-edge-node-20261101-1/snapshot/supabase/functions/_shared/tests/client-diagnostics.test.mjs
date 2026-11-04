import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {randomUUID} from 'node:crypto';
import {test} from './helpers/fenced-node-test.js';
import {clientDiagnosticsRoute,ingestClientDiagnostics,readClientDiagnostics,validateDiagnosticBatch,diagnosticFingerprint,clientDiagnosticGroups,cleanupClientDiagnostics} from '../domain/client_diagnostics.js';

// Actual handler validation, quota/replay/cleanup SQL and mutation-admission
// builder. SQLite executes the data SQL; live managed Auth/account guards and
// PostgreSQL RLS/fence constraints are separate native component acceptance.
function fixture(){
 const sql=new DatabaseSync(':memory:');
 sql.exec(`CREATE TABLE client_diagnostic_reports(report_id TEXT PRIMARY KEY,payload_sha256 TEXT,surface TEXT,environment TEXT,build_version TEXT,source_revision TEXT,code TEXT,fingerprint TEXT,occurrences INTEGER,attempt INTEGER,elapsed_ms INTEGER,received_hour INTEGER,expires_at INTEGER);
 CREATE TABLE admin_rate_limits(key_hash TEXT,bucket INTEGER,count INTEGER,expires_at INTEGER,PRIMARY KEY(key_hash,bucket));
 CREATE TABLE admin_bridge_guards(id TEXT PRIMARY KEY,passed INTEGER CONSTRAINT admin_bridge_state CHECK(passed=1));`);
 const state={active:true,batches:0,beforeBatch:null,lostReply:false};
 const prepare=query=>({sql:query,values:[],bind(...values){return {...this,values};},async all(){return {results:sql.prepare(query.replaceAll('::bigint','')).all(...this.values)};}});
 const env={DB:{prepare,async batch(statements){
  state.batches++;state.beforeBatch?.();sql.exec('BEGIN');
  try{
   const results=[];
   for(const s of statements){
    if(s.sql.startsWith('INSERT INTO mutation_guards')){if(!state.active)throw Error('session_changed');results.push({results:[]});continue;}
    if(s.sql.startsWith('DELETE FROM mutation_guards')){results.push({results:[]});continue;}
    const result=sql.prepare(s.sql).run(...s.values);results.push({results:[],meta:{changes:result.changes}});
   }
   sql.exec('COMMIT');if(state.lostReply)throw Error('synthetic lost commit acknowledgement');return results;
  }catch(error){if(sql.isTransaction)sql.exec('ROLLBACK');throw error;}
 }}};
 const actor={userId:'99910000-0000-4000-8000-000000000001',sessionId:'99910000-0000-4000-8000-000000000002',surface:'member',permissions:new Set(),assuranceLevel:1};
 return {sql,state,env,actor,close:()=>sql.close()};
}
async function report(changes={}){
 const r={collect_diagnostic:1,code:'frameworkFailure',severity:'error',surface:'member',environment:'production',build_version:'1.2.4+23',attempt:1,elapsed_ms:1000,report_id:randomUUID(),source_revision:'a'.repeat(40),occurrences:1,...changes};
 r.fingerprint=await diagnosticFingerprint(r);return r;
}
const batch=r=>({contract_version:1,reports:Array.isArray(r)?r:[r]});
const request=body=>new Request('https://synthetic.invalid/v1/diagnostics',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
const rejected=code=>error=>error.code===code;

test('diagnostic schema accepts fixed safe codes and rejects free text, identities and surface claims',async()=>{
 const r=await report();assert.equal((await validateDiagnosticBatch(batch(r),'member')).length,1);
 for(const change of [{error:'SYNTHETIC SMS token phone content'},{stack:'private/file.dart:1'},{session_id:randomUUID()},{url:'https://private.invalid'},
  {code:'callerText'},{severity:'info'},{surface:'admin'},{build_version:'private-user'},{source_revision:'private-source'},{fingerprint:'f'.repeat(64)},{attempt:0},{elapsed_ms:86400001},{occurrences:65}]){
  await assert.rejects(validateDiagnosticBatch(batch({...r,...change}),'member'));
 }
 for(const payload of [{...batch(r),user_id:randomUUID()},batch([]),batch(Array.from({length:9},()=>r)),batch([r,r]),{reports:[r]}])await assert.rejects(validateDiagnosticBatch(payload,'member'));
});

test('fingerprint depends only on safe code/release mapping, never event identity or timing',async()=>{
 const one=await report(),two=await report({elapsed_ms:2222,attempt:9});
 assert.equal(one.fingerprint,two.fingerprint);
 for(const changes of [{source_revision:'b'.repeat(40)},{build_version:'1.2.5+24'},{code:'startupFailed'}])assert.notEqual((await report(changes)).fingerprint,one.fingerprint);
});

test('authenticated ingest commits exact replay once and aggregates safe fields only',async()=>{
 const f=fixture();try{
  const r=await report({occurrences:4});
  assert.equal((await ingestClientDiagnostics(request(batch(r)),f.env,f.actor)).status,202);
  assert.equal((await ingestClientDiagnostics(request(batch(r)),f.env,f.actor)).status,202);
  assert.equal(f.sql.prepare('SELECT count(*) AS n FROM client_diagnostic_reports').get().n,1);
  const groups=await clientDiagnosticGroups(f.env);assert.equal(groups.length,1);assert.equal(groups[0].occurrences,4);assert.equal(groups[0].reports,1);
  assert.equal(Object.hasOwn(groups[0],'report_id'),false);assert.equal(Object.hasOwn(groups[0],'user_id'),false);
  const values=JSON.stringify(f.sql.prepare('SELECT * FROM client_diagnostic_reports').all());
  assert(!values.includes(f.actor.userId));assert(!values.includes(f.actor.sessionId));
 }finally{f.close();}
});

test('lost commit acknowledgement replay does not double-count and conflicting content is rejected',async()=>{
 const f=fixture();try{
  const r=await report();f.state.lostReply=true;
  await assert.rejects(ingestClientDiagnostics(request(batch(r)),f.env,f.actor));f.state.lostReply=false;
  await ingestClientDiagnostics(request(batch(r)),f.env,f.actor);
  await assert.rejects(ingestClientDiagnostics(request(batch({...r,occurrences:2})),f.env,f.actor),rejected('diagnostic_capacity_limited'));
  assert.equal((await clientDiagnosticGroups(f.env))[0].occurrences,1);
 }finally{f.close();}
});

test('per-principal quota survives session changes and the rejected transaction adds no report',async()=>{
 const f=fixture();try{
  for(let n=0;n<16;n++)await ingestClientDiagnostics(request(batch(await report())),f.env,{...f.actor,sessionId:randomUUID()});
  await assert.rejects(ingestClientDiagnostics(request(batch(await report())),f.env,f.actor),rejected('diagnostic_capacity_limited'));
  assert.equal(f.sql.prepare('SELECT count(*) AS n FROM client_diagnostic_reports').get().n,16);
  const quotas=f.sql.prepare('SELECT * FROM admin_rate_limits').all();assert.equal(quotas.length,2);assert(quotas.every(r=>r.count===16));
  assert(!JSON.stringify(quotas).includes(f.actor.userId));
 }finally{f.close();}
});

test('global quota bounds storage across many authenticated principals',async()=>{
 const f=fixture();try{
  const hour=Math.floor(Date.now()/3600000);f.sql.prepare('INSERT INTO admin_rate_limits VALUES(?,?,?,?)').run('client_diag:v1:global',hour,256,(hour+2)*3600);
  await assert.rejects(ingestClientDiagnostics(request(batch(await report())),f.env,{...f.actor,userId:randomUUID()}),rejected('diagnostic_capacity_limited'));
  assert.equal(f.sql.prepare('SELECT count(*) AS n FROM client_diagnostic_reports').get().n,0);
 }finally{f.close();}
});

test('revocation at final admission, anonymous callers and direct Admin claims write nothing',async()=>{
 const f=fixture();try{
  const body=batch(await report());
  await assert.rejects(ingestClientDiagnostics(request(body),f.env,null),rejected('unauthenticated'));
  await assert.rejects(ingestClientDiagnostics(request(body),f.env,{...f.actor,surface:'admin'}),rejected('admin_session_required'));
  f.state.beforeBatch=()=>f.state.active=false;
  await assert.rejects(ingestClientDiagnostics(request(body),f.env,f.actor),rejected('session_changed'));
  assert.equal(f.sql.prepare('SELECT count(*) AS n FROM client_diagnostic_reports').get().n,0);
 }finally{f.close();}
});

test('read requires existing health permission and routes reject unsupported methods/filters',async()=>{
 const f=fixture();try{
  await assert.rejects(readClientDiagnostics(new Request('https://synthetic.invalid/api/admin/diagnostics'),f.env,f.actor,{permissions:[]}),rejected('42501'));
  await assert.rejects(clientDiagnosticsRoute(new Request('https://synthetic.invalid/v1/diagnostics'),f.env,f.actor),rejected('method_not_allowed'));
  await assert.rejects(clientDiagnosticsRoute(new Request('https://synthetic.invalid/v1/diagnostics?user_id=private'),f.env,f.actor),rejected('invalid_request'));
  assert.equal(await clientDiagnosticsRoute(new Request('https://synthetic.invalid/other'),f.env,f.actor),null);
  assert.equal(f.state.batches,0);
 }finally{f.close();}
});

test('bounded cleanup removes expired safe reports and only diagnostic quota keys',async()=>{
 const f=fixture();try{
  for(let n=0;n<3;n++)await ingestClientDiagnostics(request(batch(await report({build_version:`1.2.${n}`}))),f.env,f.actor);
  const timestamp=Math.floor(Date.now()/1000);f.sql.prepare('UPDATE client_diagnostic_reports SET expires_at=?').run(timestamp-1);
  f.sql.prepare('INSERT INTO admin_rate_limits VALUES(?,?,?,?)').run('unrelated-auth-quota',0,1,timestamp-1);
  f.sql.prepare("UPDATE admin_rate_limits SET expires_at=? WHERE key_hash LIKE 'client_diag:%'").run(timestamp-1);
  const result=await cleanupClientDiagnostics(f.env,{limit:2});assert.equal(result.removed,2);
  assert.equal(f.sql.prepare('SELECT count(*) AS n FROM client_diagnostic_reports').get().n,1);
  assert.deepEqual(f.sql.prepare('SELECT key_hash FROM admin_rate_limits').all().map(r=>r.key_hash),['unrelated-auth-quota']);
  assert.deepEqual(await clientDiagnosticGroups(f.env),[]);
 }finally{f.close();}
});
