import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,readFile,rm,writeFile,realpath} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {createHash,randomUUID} from 'node:crypto';
import {DatabaseSync} from 'node:sqlite';
import {createRequire} from 'node:module';
import {encodeCell,decodeCell,rowDigest,readSnapshot,validateTarget,databaseConnectionOptions,stageSnapshot,verifyStage,reconcileStage} from './data_stage.mjs';

test('typed snapshot cells preserve bigint null UTF8 blob and floating point',()=>{
 for(const value of [null,9223372036854775807n,-9007199254740993n,'RWF 😃\u0000\n',Buffer.from([0,255,1]),1.25])assert.deepEqual(decodeCell(encodeCell(value)),value);
 assert.throws(()=>decodeCell({type:'integer',value:'1.0'}));
 assert.throws(()=>decodeCell({type:'blob',value:'!'}));
 assert.throws(()=>encodeCell(Infinity));
 assert.notEqual(rowDigest([{name:'id',type:'integer',value:'1'}]),rowDigest([{name:'id',type:'text',value:'1'}]));
});
test('target refuses other projects and local test cannot point at hosted DB',()=>{
 assert.throws(()=>validateTarget('postgresql://u:p@db.other.supabase.co/postgres','rrlduytparvsjfmegalh'));
 assert.throws(()=>validateTarget('postgresql://u:p@db.rrlduytparvsjfmegalh.supabase.co/postgres','rrlduytparvsjfmegalh',{localTest:true}));
 assert.equal(validateTarget('postgresql://u:p@127.0.0.1:55439/test','local',{localTest:true}).port,'55439');
});
test('effective pg connection cannot override nominated host database credentials or verified TLS',()=>{
 const {Client}=createRequire(import.meta.url)(process.env.COLLECT_PG_MODULE??'pg');
 const project='rrlduytparvsjfmegalh',base='postgresql://postgres:synthetic%24password@db.'+project+'.supabase.co:5432/postgres';
 for(const suffix of ['?sslmode=disable','?sslmode=no-verify','?sslmode=require','?sslmode=verify-full&sslmode=verify-full',
  '?host=other.example','?port=1234','?user=other','?password=other','?database=other','?ssl=false',
  '?sslcert=/private/file','?sslkey=/private/file','?sslrootcert=/private/file','?options=-csearch_path=other','#ignored']){
  assert.throws(()=>databaseConnectionOptions(base+suffix,project));
 }
 const wrongDatabase=new URL(base);wrongDatabase.pathname='/other';
 assert.throws(()=>databaseConnectionOptions(wrongDatabase.href,project));
 for(const value of [base,base+'?sslmode=verify-full']){
  const options=databaseConnectionOptions(value,project),effective=new Client(options).connectionParameters;
  assert.equal(new URL(options.connectionString).search,'');
  assert.equal(effective.host,'db.'+project+'.supabase.co');
  assert.equal(effective.port,5432);assert.equal(effective.database,'postgres');
  assert.equal(effective.user,'postgres');assert.equal(effective.password,'synthetic$password');
  assert.equal(effective.ssl.rejectUnauthorized,true);
 }
 const pool=databaseConnectionOptions('postgresql://postgres.'+project+':synthetic@aws-0-eu-north-1.pooler.supabase.com:6543/postgres?sslmode=verify-full',project);
 assert.equal(new Client(pool).connectionParameters.ssl.rejectUnauthorized,true);
});
test('sealed snapshot rejects tampering and preserves duplicate rows and exact cells',async()=>{
 const dir=await realpath(await mkdtemp(join(tmpdir(),'collect-stage-')));const path=join(dir,'source.sqlite');
 try{
  const db=new DatabaseSync(path);db.exec('CREATE TABLE sample (id INTEGER PRIMARY KEY, value BLOB, note TEXT); CREATE TABLE empty (id TEXT PRIMARY KEY);');
  db.prepare('INSERT INTO sample VALUES(?,?,?)').run(9223372036854775807n,Buffer.from([0,255]),'quoted\'\n');db.close();
  const digest=createHash('sha256').update(await readFile(path)).digest('hex');const snap=await readSnapshot(path,digest);
  assert.equal(snap.tables.length,2);assert.equal(snap.tables.find(t=>t.name==='sample').rows[0].cells[0].value,'9223372036854775807');
  await assert.rejects(readSnapshot(path,'0'.repeat(64)),/digest mismatch/);
  await writeFile(path+'-wal','active');await assert.rejects(readSnapshot(path,digest),/Live journal/);
 }finally{await rm(dir,{recursive:true,force:true});}
});
test('PostgreSQL staging exact readback denial tamper and unknown-commit reconciliation',{timeout:30000},async()=>{
 const url=process.env.COLLECT_TEST_PG_URL;
 assert.ok(url,'COLLECT_TEST_PG_URL is required: this integration case must not silently skip');validateTarget(url,'local',{localTest:true});
 const require=createRequire(import.meta.url);const {Client}=require(process.env.COLLECT_PG_MODULE??'pg');const client=new Client({connectionString:url,connectionTimeoutMillis:5000,statement_timeout:10000});
 const dir=await realpath(await mkdtemp(join(tmpdir(),'collect-stage-pg-')));const path=join(dir,'fixture.sqlite');const runId=randomUUID();const schema='collect_stage_'+runId.replaceAll('-','');let connected=false;
 try{
  const db=new DatabaseSync(path);db.exec('CREATE TABLE evidence(id TEXT PRIMARY KEY, amount INTEGER NOT NULL, body BLOB, note TEXT); CREATE TABLE empty(id TEXT);');
  db.prepare('INSERT INTO evidence VALUES(?,?,?,?)').run('fixture',9007199254740993n,Buffer.from([0,1,255]),'French / Kinyarwanda');db.close();
  const snapshot=await readSnapshot(path,createHash('sha256').update(await readFile(path)).digest('hex'));
  await client.connect();connected=true;assert.deepEqual(await reconcileStage(client,snapshot,runId),{exists:false,promoted:false});
  const result=await stageSnapshot(client,snapshot,{runId});assert.equal(result.verified,true);assert.equal(result.promoted,false);
  assert.equal((await reconcileStage(client,snapshot,runId)).verified,true);
  await assert.rejects(stageSnapshot(client,snapshot,{runId}));
  assert.equal(await verifyStage(client,schema,snapshot),true);
  await client.query('UPDATE "'+schema+'".rows SET cells=$1 WHERE ordinal=0',[JSON.stringify([{name:'id',type:'text',value:'tampered'}])]);
  await assert.rejects(verifyStage(client,schema,snapshot),/identity mismatch/);
  await client.query('SET ROLE anon');
  await assert.rejects(client.query('SELECT * FROM "'+schema+'".rows'),/permission denied/);
  await client.query('RESET ROLE');
 }finally{try{if(connected){await client.query('RESET ROLE');await client.query('DROP SCHEMA IF EXISTS "'+schema+'" CASCADE');}}finally{await client.end();await rm(dir,{recursive:true,force:true});}}
});
