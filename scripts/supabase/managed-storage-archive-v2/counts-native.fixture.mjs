// Isolated synthetic verification for the fixed v2 count SQL. No provider calls.
// The sole adaptations to the compiled production SQL are the synthetic
// reference bytes/digest and unique loopback fixture database name.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtemp,chmod,rm,lstat,realpath,access} from 'node:fs/promises';
import {constants} from 'node:fs';
import {createServer} from 'node:net';
import {join,resolve,isAbsolute,relative,sep,dirname} from 'node:path';
import {tmpdir} from 'node:os';
import {pathToFileURL,fileURLToPath} from 'node:url';
import {randomUUID} from 'node:crypto';
import pg from '../node_modules/pg/lib/index.js';
import REAL from './REFERENCE.json' with {type:'json'};
import {compileCountsRequest,parseCountsResponse,REFERENCE_SHA256} from './counts.mjs';
import {makeFixtureReference,compileFixtureCaptureRequest} from './storage.mjs';
import {runNativeDefinition,SYNTHETIC_PROJECT} from './native-definition.mjs';
import {canonical,sha,identifier} from '../current-archive/codec.mjs';

const TOOL_ENV={PATH:'/usr/bin:/bin:/usr/sbin:/sbin',LC_ALL:'C'};
const SOURCE_ROOT=resolve(dirname(fileURLToPath(import.meta.url)),'../../..');
const ORIGINAL_ROOT='/Volumes/T7/01 Projects/COLLECT';
const contains=(x,y)=>{const r=relative(x,y);return r===''||r!=='..'&&!r.startsWith('..'+sep)&&!isAbsolute(r);};
const separated=(a,b)=>!contains(a,b)&&!contains(b,a);
async function binaryDirectory(){
 const bin=process.env.COLLECT_STORAGE_TEST_PG_BIN_DIR;
 if(typeof bin!=='string'||!isAbsolute(bin)||resolve(bin)!==bin||await realpath(bin)!==bin)throw Error('SYNTHETIC_PG_BIN_DIR_REQUIRED');
 for(const name of ['postgres','initdb','pg_ctl']){
  const path=join(bin,name),s=await lstat(path);if(!s.isFile()||s.isSymbolicLink()||await realpath(path)!==path)throw Error('SYNTHETIC_PG_BINARY_REQUIRED');
  await access(path,constants.X_OK);
 }
 const r=spawnSync(join(bin,'postgres'),['--version'],{env:TOOL_ENV,encoding:'utf8',timeout:15000,maxBuffer:65536});
 if(r.error||r.status!==0||!/^postgres \(PostgreSQL\) 17\./.test(r.stdout??''))throw Error('SYNTHETIC_PG17_REQUIRED');
 return bin;
}
function command(bin,name,args){
 const r=spawnSync(join(bin,name),args,{env:TOOL_ENV,encoding:'utf8',timeout:120000,maxBuffer:1024*1024});
 if(r.error||r.status!==0)throw Error('SYNTHETIC_'+name.toUpperCase()+'_FAILED');
}
async function freePort(){
 const server=createServer();await new Promise((ok,bad)=>{server.once('error',bad);server.listen(0,'127.0.0.1',ok);});
 const port=server.address().port;await new Promise((ok,bad)=>server.close(e=>e?bad(e):ok()));return port;
}
function replaceOne(s,from,to){assert.equal(s.split(from).length,2);return s.replace(from,to);}
function fixtureSQL(reference,database,requestId){
 assert.match(database,/^collect_storage_source_[a-f0-9]{32}_test$/);
 const request=compileCountsRequest(REAL,requestId);
 let query=replaceOne(request.body.query,Buffer.from(canonical(REAL)).toString('hex'),Buffer.from(canonical(reference)).toString('hex'));
 query=replaceOne(query,REFERENCE_SHA256,sha(canonical(reference)));
 query=replaceOne(query,"->>'database' FROM payload)='postgres'","->>'database' FROM payload)='"+database+"'");
 return {request,query};
}
function batchRows(result,field){
 assert(Array.isArray(result));assert.equal(result.at(-1)?.command,'ROLLBACK');
 const kind=field==='QUERY PLAN'?'EXPLAIN':'SELECT';
 const selected=result.filter(x=>x.command===kind&&(x.fields?.some(f=>f.name===field)||x.rows?.some(r=>Object.hasOwn(r,field))));
 assert.equal(selected.length,1);return selected[0].rows;
}
function parsedFixture(rows,{request,reference,database}){
 assert.equal(rows.length,1);assert.equal(rows[0].kind,'collect.managed-storage.counts.v1');
 const payload=JSON.parse(rows[0].payload);assert.equal(payload.identity.database,database);assert.equal(payload.reference_sha256,sha(canonical(reference)));
 // The production parser is unchanged. Translate only fixture-only identity
 // values after asserting them; all measured fields are from native SQL.
 payload.identity.database='postgres';payload.reference_sha256=REFERENCE_SHA256;
 const body=Buffer.from(JSON.stringify([{kind:rows[0].kind,payload:JSON.stringify(payload)}]));
 try{return parseCountsResponse({status:201,body},{reference:REAL,request,project:SYNTHETIC_PROJECT});}finally{body.fill(0);}
}
function planScans(plan){
 const nodes=[];
 const visit=x=>{if(!x||typeof x!=='object')return;if(x.Schema==='storage'&&x['Relation Name'])nodes.push({name:x['Relation Name'],loops:x['Actual Loops'],rows:x['Actual Rows']});
  for(const v of Object.values(x)){if(Array.isArray(v))for(const y of v)visit(y);else if(v&&typeof v==='object')visit(v);}};
 visit(plan);return nodes;
}
function fields(reference,name){
 const table=reference.relations.find(t=>t.name===name);
 return reference.columns.filter(c=>c.relation_oid===table.oid&&!c.generated).map(c=>c.name);
}
const names=columns=>columns.map(identifier).join(',');
async function preserve(client,reference){
 for(const t of reference.relations)await client.query('CREATE TEMP TABLE '+identifier('count_fixture_'+t.name)+' AS SELECT * FROM ONLY storage.'+identifier(t.name));
}
async function restore(client,reference){
 for(const t of reference.relations){const cols=fields(reference,t.name);await client.query('DELETE FROM ONLY storage.'+identifier(t.name));await client.query('INSERT INTO storage.'+identifier(t.name)+' ('+names(cols)+') SELECT '+names(cols)+' FROM pg_temp.'+identifier('count_fixture_'+t.name));}
}
async function clear(client,name){await client.query('DELETE FROM ONLY storage.'+identifier(name));}
async function fill(client,reference,name,n){
 const cols=fields(reference,name),projection=cols.map(c=>name==='buckets'&&c==='id'?"('fixture-'||g.n::text)":'t.'+identifier(c)).join(',');
 await client.query('INSERT INTO storage.'+identifier(name)+' ('+names(cols)+') SELECT '+projection+' FROM (SELECT * FROM pg_temp.'+identifier('count_fixture_'+name)+' LIMIT 1) t CROSS JOIN pg_catalog.generate_series(1,$1::int) g(n)',[n]);
}
async function syntheticAggregates(client,reference){
 await clear(client,'objects');await clear(client,'buckets');
 const bc=fields(reference,'buckets'),bp=bc.map(c=>c==='id'?"'known'::text":'t.'+identifier(c)).join(',');
 await client.query('INSERT INTO storage.buckets ('+names(bc)+') SELECT '+bp+' FROM (SELECT * FROM pg_temp.count_fixture_buckets LIMIT 1) t');
 const oc=fields(reference,'objects'),op=oc.map(c=>{
  if(c==='bucket_id')return "CASE WHEN g.n=6 THEN 'ghost'::text ELSE 'known'::text END";
  if(c==='metadata')return "CASE g.n WHEN 1 THEN '{\"size\":10}'::jsonb WHEN 2 THEN '{\"size\":0}'::jsonb WHEN 3 THEN '{}'::jsonb WHEN 4 THEN '{\"size\":-1}'::jsonb WHEN 5 THEN '{\"size\":\"2\"}'::jsonb ELSE NULL::jsonb END";
  if(c==='version')return "CASE g.n WHEN 1 THEN NULL::text WHEN 2 THEN ''::text WHEN 3 THEN 'é'::text WHEN 4 THEN 'A'::text WHEN 5 THEN 'XYZ'::text ELSE NULL::text END";
  return 't.'+identifier(c);
 }).join(',');
 await client.query('INSERT INTO storage.objects ('+names(oc)+') SELECT '+op+' FROM (SELECT * FROM pg_temp.count_fixture_objects LIMIT 1) t CROSS JOIN pg_catalog.generate_series(1,6) g(n)');
}
async function exerciseCounts({metadata,adminUrl,makeClient,cases}){
 const database=metadata.identity.database,reference=makeFixtureReference(metadata),u=new URL(adminUrl);u.pathname='/'+database;
 const client=makeClient(u.href);await client.connect();let preserved=false;
 try{
  const info=(await client.query("SELECT current_database()::text AS database,pg_catalog.host(pg_catalog.inet_server_addr()) AS address,current_setting('server_version_num') AS version")).rows[0];
  assert.equal(info.database,database);assert.equal(info.address,'127.0.0.1');assert.match(info.version,/^17[0-9]{4}$/);
  await preserve(client,reference);preserved=true;
  // The existing synthetic fixture has no uniqueness constraints. Give its
  // bucket IDs distinct values so it satisfies the production key invariant.
  await client.query("WITH ranked AS (SELECT ctid,pg_catalog.row_number() OVER () n FROM storage.buckets) UPDATE storage.buckets b SET id='baseline-'||ranked.n::text FROM ranked WHERE b.ctid=ranked.ctid");
  async function count(){const compiled=fixtureSQL(reference,database,randomUUID()),rows=batchRows(await client.query(compiled.query),'kind');return parsedFixture(rows,{...compiled,reference,database});}
  const baseline=await count();assert.equal(baseline.within_row_caps,true);assert.equal(baseline.aggregates_measured,true);
  for(const t of reference.relations){const observed=(await client.query('SELECT count(*)::text AS n FROM ONLY storage.'+identifier(t.name))).rows[0].n;assert.equal(baseline.tables.find(x=>x.name===t.name).rows,observed);}
  cases.push('compiled_count_sql_native_all10tables_and_parser');

  await syntheticAggregates(client,reference);const aggregate=await count();
  assert.equal(aggregate.anonymous_bucket_count,'2');assert.equal(aggregate.aggregates_measured,true);
  const known=aggregate.buckets.find(b=>b.registered),ghost=aggregate.buckets.find(b=>!b.registered);
  assert.deepEqual([known.objects,known.valid_declared_sizes,known.missing_declared_sizes,known.invalid_declared_sizes,known.valid_declared_bytes],['5','2','1','2','10']);
  assert.deepEqual([known.version_nonnull,known.version_empty,known.version_text_bytes,known.maximum_version_text_bytes],['4','1','6','3']);
  assert.deepEqual([ghost.objects,ghost.missing_declared_sizes,ghost.valid_declared_bytes],['1','1','0']);
  assert.equal(aggregate.aggregate_totals.objects,'6');cases.push('native_size_version_registered_and_orphan_aggregates');

  await clear(client,'objects');await clear(client,'buckets');await fill(client,reference,'buckets',65);
  const bucketCap=await count();assert.equal(bucketCap.within_row_caps,true);assert.equal(bucketCap.anonymous_bucket_count,'65');assert.equal(bucketCap.aggregates_measured,false);assert.deepEqual(bucketCap.buckets,[]);assert.equal(bucketCap.state,'PREFLIGHT_BOUNDS_EXCEEDED');cases.push('native_bucket_cap_refuses_aggregate');

  await clear(client,'buckets');await fill(client,reference,'buckets',15037);
  const tableCap=await count(),table=tableCap.tables.find(t=>t.name==='buckets');
  assert.deepEqual([table.exact,table.rows,table.rows_at_least],[false,null,'10001']);assert.equal(tableCap.total_rows,null);assert.equal(tableCap.within_row_caps,false);assert.equal(tableCap.aggregates_measured,false);cases.push('native_per_table_cap_reports_lower_bound');

  // A valid earlier preflight is intentionally stale here: the live source
  // has 15,037 synthetic rows. Confirm actual executor rows stop at 10,001,
  // the full capture refuses, and its cell-producing branch never runs.
  const proof={format:'collect.managed-storage.metadata.synthetic-counts.v1',fixture:true,project_ref:SYNTHETIC_PROJECT.project_ref,
   reference_sha256:sha(canonical(reference)),within_row_caps:true,storage_identifiers_returned:false,metadata_bodies_returned:false,
   version_values_returned:false,object_bodies_read:false,capture_dispatched:false,total_rows:'0',
   tables:reference.relations.map(t=>({schema:'storage',name:t.name,rows:'0',rows_at_least:'0',exact:true}))};
  const capture=compileFixtureCaptureRequest(reference,proof,randomUUID(),database),captureAt=capture.body.query.indexOf('WITH RECURSIVE');assert(captureAt>0);
  const captureExplain=capture.body.query.slice(0,captureAt)+'EXPLAIN (ANALYZE true, VERBOSE true, FORMAT JSON, TIMING false, SUMMARY false) '+capture.body.query.slice(captureAt);
  const capturePlan=batchRows(await client.query(captureExplain),'QUERY PLAN')[0]['QUERY PLAN'],bucketScans=planScans(capturePlan).filter(n=>n.name==='buckets');
  assert(bucketScans.some(n=>n.loops===1&&n.rows===10001));assert(bucketScans.every(n=>n.loops===0||n.rows<=10001));
  assert(bucketScans.some(n=>n.loops===0));
  const refused=batchRows(await client.query(capture.body.query),'kind');assert.equal(refused.length,1);assert.equal(JSON.parse(refused[0].payload).refused,'METADATA_OR_BUDGET_CHANGED');
  cases.push('native_capture_overcap_scans_at_most_10001_rows_then_refuses');

  await restore(client,reference);
  for(const name of reference.relations.slice(0,6).map(t=>t.name)){await clear(client,name);await fill(client,reference,name,9000);}
  const totalCap=await count();assert.equal(totalCap.tables.every(t=>t.exact),true);assert(BigInt(totalCap.total_rows)>50000n);assert.equal(totalCap.within_row_caps,false);assert.equal(totalCap.anonymous_bucket_count,null);assert.equal(totalCap.aggregates_measured,false);cases.push('native_total_cap_refuses_aggregate');
  await restore(client,reference);

  const en=reference.types.find(t=>t.kind==='e'),label=en.enum_labels[0].label,drift=label+'_count_fixture';
  await client.query('ALTER TYPE storage.'+identifier(en.name)+" RENAME VALUE '"+label+"' TO '"+drift+"'");
  try{
   const compiled=fixtureSQL(reference,database,randomUUID()),at=compiled.query.indexOf('WITH RECURSIVE');assert(at>0);
   const explain=compiled.query.slice(0,at)+'EXPLAIN (ANALYZE true, VERBOSE true, FORMAT JSON, TIMING false, SUMMARY false) '+compiled.query.slice(at);
   const plan=batchRows(await client.query(explain),'QUERY PLAN')[0]['QUERY PLAN'],scans=planScans(plan),covered=new Set(scans.map(n=>n.name));
   assert(reference.relations.every(t=>covered.has(t.name)));assert(scans.every(n=>n.loops===0));
   const rows=batchRows(await client.query(compiled.query),'kind');assert.equal(rows.length,1);assert.equal(JSON.parse(rows[0].payload).refused,'STORAGE_CATALOGUE_CHANGED');
   cases.push('native_catalogue_drift_refuses_with_zero_storage_scans');
  }finally{await client.query('ALTER TYPE storage.'+identifier(en.name)+" RENAME VALUE '"+drift+"' TO '"+label+"'");}
 }finally{
  try{if(preserved)await restore(client,reference);}finally{await client.end();}
 }
}
async function runCountsNativeFixture({adminUrl,makeClient}={}){
 const cases=[];
 const native=await runNativeDefinition({adminUrl,makeClient,onMetadata:metadata=>exerciseCounts({metadata,adminUrl,makeClient,cases})});
 return {format:'collect.managed-storage.counts.synthetic-native-review.v1',cases,case_count:cases.length,
  existing_capture_fixture_cases:native.case_count,production_sql_compiler_used:true,adaptations:['fixture_reference_bytes_and_hash','fixture_database_name'],
  parser_fixture_normalizations:['database_name','reference_hash'],provider_calls:0,actual_storage_values_read:false,production_capture:false};
}
async function main(){
 if(typeof process.getuid!=='function')throw Error('SYNTHETIC_POSIX_REQUIRED');
 const bin=await binaryDirectory(),root=await realpath(tmpdir());
 if(!separated(root,SOURCE_ROOT)||!separated(root,ORIGINAL_ROOT))throw Error('SYNTHETIC_TEMP_ROOT_INVALID');
 const dir=await mkdtemp(join(root,'collect-storage-counts-native-'));await chmod(dir,0o700);
 const initial=await lstat(dir);if(!initial.isDirectory()||initial.isSymbolicLink()||initial.uid!==process.getuid()||(initial.mode&0o777)!==0o700||await realpath(dir)!==dir||dirname(dir)!==root)throw Error('SYNTHETIC_TEMP_DIRECTORY_INVALID');
 const data=join(dir,'data'),log=join(dir,'postgres.log'),port=await freePort();let initialized=false;
 try{
  command(bin,'initdb',['-D',data,'-U','postgres','--auth=trust','--no-locale','--encoding=UTF8']);initialized=true;
  // An empty socket directory keeps the temporary server TCP-loopback only.
  command(bin,'pg_ctl',['-D',data,'-l',log,'-o','-h 127.0.0.1 -p '+port+' -c unix_socket_directories=','-w','start']);
  const adminUrl='postgres://postgres:synthetic@127.0.0.1:'+port+'/postgres';
  const makeClient=raw=>{const u=new URL(raw);assert.equal(u.hostname,'127.0.0.1');assert.equal(Number(u.port),port);assert.equal(u.username,'postgres');assert.match(u.pathname,/^\/(?:postgres|collect_storage_(?:source|archive)_[a-f0-9]{32}_test)$/);return new pg.Client({connectionString:raw,connectionTimeoutMillis:5000});};
  return await runCountsNativeFixture({adminUrl,makeClient});
 }finally{
  if(initialized){
   spawnSync(join(bin,'pg_ctl'),['-D',data,'-m','fast','-w','stop'],{env:TOOL_ENV,encoding:'utf8',timeout:120000,maxBuffer:1024*1024});
   const status=spawnSync(join(bin,'pg_ctl'),['-D',data,'status'],{env:TOOL_ENV,encoding:'utf8',timeout:15000,maxBuffer:65536});
   if(status.error||status.status!==3)throw Error('SYNTHETIC_SERVER_STOP_UNCONFIRMED');
  }
  const s=await lstat(dir);
  if(!s.isDirectory()||s.isSymbolicLink()||s.uid!==process.getuid()||(s.mode&0o777)!==0o700||s.dev!==initial.dev||s.ino!==initial.ino||await realpath(dir)!==dir||dirname(dir)!==root)throw Error('SYNTHETIC_CLEANUP_UNCONFIRMED');
  await rm(dir,{recursive:true,force:true});
 }
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
 try{console.log(JSON.stringify(await main()));}catch{console.error(JSON.stringify({status:'synthetic_fixture_failed',production_request:false}));process.exitCode=1;}
}
