// Pure source/storage-contract cases copied without changing their assertions.
// Mandatory PostgreSQL staging/promotion suites remain in their historical
// files; current native staging and compatibility have a separate receipt.
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,readFile,rm,writeFile,realpath} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {createHash} from 'node:crypto';
import {DatabaseSync} from 'node:sqlite';
import {createRequire} from 'node:module';
import {encodeCell,decodeCell,rowDigest,readSnapshot,validateTarget,databaseConnectionOptions} from './data_stage.mjs';

function fixtureDatabaseUrl(address,username='u',password='p'){
 const url=new URL(address);url.username=username;url.password=encodeURIComponent(password);return url.href;
}

test('typed snapshot cells preserve bigint null UTF8 blob and floating point',()=>{
 for(const value of [null,9223372036854775807n,-9007199254740993n,'RWF 😃\u0000\n',Buffer.from([0,255,1]),1.25])assert.deepEqual(decodeCell(encodeCell(value)),value);
 assert.throws(()=>decodeCell({type:'integer',value:'1.0'}));
 assert.throws(()=>decodeCell({type:'blob',value:'!'}));
 assert.throws(()=>encodeCell(Infinity));
 assert.notEqual(rowDigest([{name:'id',type:'integer',value:'1'}]),rowDigest([{name:'id',type:'text',value:'1'}]));
});
test('target refuses other projects and local test cannot point at hosted DB',()=>{
 assert.throws(()=>validateTarget(fixtureDatabaseUrl('postgresql://db.other.supabase.co/postgres'),'rrlduytparvsjfmegalh'));
 assert.throws(()=>validateTarget(fixtureDatabaseUrl('postgresql://db.rrlduytparvsjfmegalh.supabase.co/postgres'),'rrlduytparvsjfmegalh',{localTest:true}));
 assert.equal(validateTarget(fixtureDatabaseUrl('postgresql://127.0.0.1:55439/test'),'local',{localTest:true}).port,'55439');
});
test('effective pg connection cannot override nominated host database credentials or verified TLS',()=>{
 const {Client}=createRequire(import.meta.url)(process.env.COLLECT_PG_MODULE??'pg');
 const project='rrlduytparvsjfmegalh',base=fixtureDatabaseUrl('postgresql://db.'+project+'.supabase.co:5432/postgres','postgres','synthetic$password');
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
 const pool=databaseConnectionOptions(fixtureDatabaseUrl('postgresql://aws-0-eu-north-1.pooler.supabase.com:6543/postgres?sslmode=verify-full','postgres.'+project,'synthetic'),project);
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

import {disposition,makePromotionPlan,reviewedTables} from './data_promote.mjs';
const epoch=1792497600;
test('every source table is classified; device/native state requires a rebind plan',()=>{
 assert.equal(disposition('auth_sessions'),'historical_revoked');
 for(const n of ['auth_refresh_tokens','auth_google_flows','admin_sessions','mutation_guards'])assert.equal(disposition(n),'archive_only');
 assert.equal(disposition('ledger_entries'),'business_exact');
 const tables=reviewedTables.map(name=>({name,rows:[],row_count:name==='native_consents'?1:0,sha256:'a'.repeat(64)}));
 assert.throws(()=>makePromotionPlan({tables},reviewedTables,epoch),/rebind/);
 assert.throws(()=>disposition('unreviewed_new_table'),/Unknown table/);
 assert.throws(()=>makePromotionPlan({tables:[{name:'users'}]},['users'],epoch),/table set/);
 assert.throws(()=>makePromotionPlan({tables:[]},['extra'],epoch),/table set/);
 assert.throws(()=>makePromotionPlan({tables:[]},[],0),/epoch/);
});
