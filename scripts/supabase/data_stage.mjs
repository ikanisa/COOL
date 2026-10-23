// Exact typed SQLite snapshot staging. Never promotes rows into application tables.
import {DatabaseSync} from 'node:sqlite';
import {createHash,randomUUID} from 'node:crypto';
import {lstat,realpath,readFile,open,stat} from 'node:fs/promises';
import {resolve,dirname} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createRequire} from 'node:module';

const sha=value=>createHash('sha256').update(value).digest('hex');
const tableName=/^[a-z][a-z0-9_]*$/;
const quote=name=>{if(!tableName.test(name))throw new Error('Invalid table name');return '"'+name+'"';};
export function encodeCell(value){
 if(value===null)return {type:'null',value:null};
 if(typeof value==='bigint')return {type:'integer',value:value.toString()};
 if(typeof value==='number'){if(!Number.isFinite(value))throw new Error('Non-finite source number');return {type:Number.isInteger(value)?'integer':'real',value:String(value)};}
 if(typeof value==='string')return {type:'text',value};
 if(value instanceof Uint8Array)return {type:'blob',value:Buffer.from(value).toString('base64')};
 throw new Error('Unsupported source cell');
}
export function decodeCell(cell){
 if(!cell||!['null','integer','real','text','blob'].includes(cell.type))throw new Error('Invalid staged cell');
 if(cell.type==='null'){if(cell.value!==null)throw new Error('Invalid null');return null;}
 if(cell.type==='integer'){if(typeof cell.value!=='string'||! /^-?(?:0|[1-9]\d*)$/.test(cell.value))throw new Error('Invalid integer');return BigInt(cell.value);}
 if(cell.type==='real'){const n=Number(cell.value);if(typeof cell.value!=='string'||!Number.isFinite(n))throw new Error('Invalid real');return n;}
 if(cell.type==='text'){if(typeof cell.value!=='string')throw new Error('Invalid text');return cell.value;}
 if(typeof cell.value!=='string'||Buffer.from(cell.value,'base64').toString('base64')!==cell.value)throw new Error('Invalid blob');return Buffer.from(cell.value,'base64');
}
export function typedRow(columns,row){return columns.map(name=>({name,...encodeCell(row[name])}));}
export function rowDigest(cells){return sha(JSON.stringify(cells.map(cell=>({name:cell.name,...encodeCell(decodeCell(cell))}))));}
export async function readSnapshot(path,expectedSha256){
 const physical=await realpath(path),before=await lstat(path);
 if(physical!==resolve(path)||before.isSymbolicLink()||!before.isFile()||before.nlink!==1||before.size>256*1024*1024||!/^[a-f0-9]{64}$/.test(expectedSha256))throw new Error('Independent bounded regular snapshot and expected digest required');
 const noJournal=async()=>{for(const suffix of ['-wal','-journal'])try{if((await stat(physical+suffix)).size>0)throw new Error('Live journal is not a sealed snapshot');}catch(error){if(error.code!=='ENOENT')throw error;}};
 await noJournal();
 if(sha(await readFile(physical))!==expectedSha256)throw new Error('Source snapshot digest mismatch');
 const db=new DatabaseSync(physical,{readOnly:true});const tables=[];
 try{
  if(db.prepare('PRAGMA integrity_check').get().integrity_check!=='ok'||db.prepare('PRAGMA foreign_key_check').all().length)throw new Error('Source integrity failure');
  const names=db.prepare("select name from sqlite_schema where type='table' and name not like 'sqlite_%' and name not like '_cf_%' and name!='d1_migrations' order by name").all().map(x=>x.name);
  for(const name of names){
   const info=db.prepare('PRAGMA table_info('+quote(name)+')').all(),columns=info.map(x=>x.name),pk=info.filter(x=>x.pk).sort((a,b)=>a.pk-b.pk).map(x=>x.name);
   columns.forEach(quote);const statement=db.prepare('SELECT * FROM '+quote(name));statement.setReadBigInts(true);
   const rows=[];for(const row of statement.iterate()){const cells=typedRow(columns,row);rows.push({cells,sha256:rowDigest(cells),primary_key:typedRow(pk,row)});}
   rows.sort((a,b)=>a.sha256.localeCompare(b.sha256));
   tables.push({name,columns:info,rows,row_count:rows.length,sha256:sha(rows.map(x=>x.sha256).join('\n'))});
  }
 }finally{db.close();}
 await noJournal();
 const after=await lstat(physical);
 if(before.dev!==after.dev||before.ino!==after.ino||before.size!==after.size||before.mtimeMs!==after.mtimeMs||sha(await readFile(physical))!==expectedSha256)throw new Error('Source changed during capture');
 return {source_sha256:expectedSha256,tables};
}
export function validateTarget(connectionString,projectRef,{localTest=false}={}){
 const url=new URL(connectionString);
 if(!['postgres:','postgresql:'].includes(url.protocol)||!url.username||!url.password)throw new Error('Expected PostgreSQL credentials in environment');
 const query=[...url.searchParams];
 if(url.hash||query.length>1||query.some(([key,value])=>key!=='sslmode'||value!=='verify-full')||localTest&&query.length)throw new Error('Only optional verified TLS mode is permitted; connection overrides are refused');
 if(localTest){if(!['localhost','127.0.0.1','[::1]'].includes(url.hostname))throw new Error('Local-test target must be loopback');}
 else if(projectRef!=='rrlduytparvsjfmegalh'||url.pathname!=='/postgres'||!['','5432','6543'].includes(url.port)||!(url.hostname===`db.${projectRef}.supabase.co`||url.hostname.endsWith('.pooler.supabase.com')&&decodeURIComponent(url.username).endsWith('.'+projectRef)))throw new Error('Unexpected target project');
 // pg merges connection-string parameters over explicit Client options.
 // Strip even the reviewed sslmode so it cannot replace verified TLS config.
 url.search='';
 return url;
}
export function databaseConnectionOptions(connectionString,projectRef,{localTest=false}={}){
 const target=validateTarget(connectionString,projectRef,{localTest});
 return {connectionString:target.href,ssl:localTest?false:{rejectUnauthorized:true},connectionTimeoutMillis:10000,statement_timeout:60000};
}
export async function stageSnapshot(client,snapshot,{runId=randomUUID()}={}){
 if(!/^[a-f0-9-]{36}$/.test(runId))throw new Error('Invalid run identity');
 const schema='collect_stage_'+runId.replaceAll('-','');const q='"'+schema+'"';
 await client.query('BEGIN ISOLATION LEVEL SERIALIZABLE');
 try{
  await client.query('CREATE SCHEMA '+q);
  await client.query('REVOKE ALL ON SCHEMA '+q+' FROM PUBLIC');
  const roles=await client.query("select rolname from pg_roles where rolname in ('anon','authenticated','service_role','collect_runtime')");
  for(const {rolname} of roles.rows)await client.query('REVOKE ALL ON SCHEMA '+q+' FROM '+quote(rolname));
  await client.query('CREATE TABLE '+q+'.manifest (source_sha256 text not null, format text not null, disposition text not null CHECK (disposition=\'quarantine_only\'))');
  await client.query('INSERT INTO '+q+'.manifest VALUES ($1,$2,$3)',[snapshot.source_sha256,'collect.snapshot.stage.v1','quarantine_only']);
  await client.query('CREATE TABLE '+q+'.table_manifest (table_name text primary key, columns_json jsonb not null, row_count bigint not null, sha256 text not null)');
  await client.query('CREATE TABLE '+q+'.rows (table_name text not null references '+q+'.table_manifest(table_name), ordinal bigint not null, primary_key_json jsonb not null, cells jsonb not null, sha256 text not null, primary key(table_name,ordinal))');
  for(const table of snapshot.tables){
   await client.query('INSERT INTO '+q+'.table_manifest VALUES ($1,$2,$3,$4)',[table.name,JSON.stringify(table.columns),table.row_count,table.sha256]);
   for(let i=0;i<table.rows.length;i++){const row=table.rows[i];await client.query('INSERT INTO '+q+'.rows VALUES ($1,$2,$3,$4,$5)',[table.name,i,JSON.stringify(row.primary_key),JSON.stringify(row.cells),row.sha256]);}
  }
  const verification=await verifyStage(client,schema,snapshot);
  await client.query('COMMIT');return {format:'collect.snapshot.stage-receipt.v1',run_id:runId,schema,source_sha256:snapshot.source_sha256,table_count:snapshot.tables.length,row_count:snapshot.tables.reduce((n,t)=>n+t.row_count,0),verified:verification,promoted:false};
 }catch(error){await client.query('ROLLBACK');throw error;}
}
export async function reconcileStage(client,snapshot,runId){
 if(!/^[a-f0-9-]{36}$/.test(runId))throw new Error('Invalid run identity');
 const schema='collect_stage_'+runId.replaceAll('-','');
 const exists=await client.query('SELECT to_regnamespace($1) as present',[schema]);
 if(!exists.rows[0].present)return {exists:false,promoted:false};
 return {exists:true,verified:await verifyStage(client,schema,snapshot),promoted:false};
}
export async function verifyStage(client,schema,snapshot){
 if(!/^collect_stage_[a-f0-9]{32}$/.test(schema))throw new Error('Invalid quarantine schema');const q='"'+schema+'"';
 const meta=await client.query('SELECT * FROM '+q+'.manifest');
 if(meta.rows.length!==1||meta.rows[0].source_sha256!==snapshot.source_sha256||meta.rows[0].disposition!=='quarantine_only')throw new Error('Staging identity mismatch');
 const manifests=await client.query('SELECT * FROM '+q+'.table_manifest ORDER BY table_name');
 if(manifests.rows.length!==snapshot.tables.length)throw new Error('Staging table-set mismatch');
 for(const table of snapshot.tables){
  const metadata=manifests.rows.find(x=>x.table_name===table.name);
  if(!metadata||Number(metadata.row_count)!==table.row_count||metadata.sha256!==table.sha256||JSON.stringify(metadata.columns_json)!==JSON.stringify(table.columns)){
   // JSONB may reorder object keys; compare each named column property instead.
   if(!metadata||Number(metadata.row_count)!==table.row_count||metadata.sha256!==table.sha256||JSON.stringify(metadata.columns_json.map(c=>Object.keys(c).sort().map(k=>[k,c[k]])))!==JSON.stringify(table.columns.map(c=>Object.keys(c).sort().map(k=>[k,c[k]]))))throw new Error('Staging metadata mismatch');
  }
  const data=await client.query('SELECT cells,sha256,primary_key_json FROM '+q+'.rows WHERE table_name=$1 ORDER BY ordinal',[table.name]);
  if(data.rows.length!==table.row_count)throw new Error('Staging row count mismatch');
  const hashes=data.rows.map((row,i)=>{const digest=rowDigest(row.cells);if(digest!==row.sha256||digest!==table.rows[i].sha256||rowDigest(row.primary_key_json)!==rowDigest(table.rows[i].primary_key))throw new Error('Staging byte identity mismatch');return digest;});
  if(sha(hashes.join('\n'))!==table.sha256)throw new Error('Staging table hash mismatch');
 }
 return true;
}
async function main(args){
 const options={};for(let i=0;i<args.length;i+=2){if(!['--source','--sha256','--receipt','--apply'].includes(args[i])||options[args[i]]!==undefined||args[i+1]===undefined)throw new Error('Use unique named source sha256 receipt apply arguments');options[args[i]]=args[i+1];}
 if(!options['--source']||!options['--sha256']||!options['--receipt']||!['true','false'].includes(options['--apply']))throw new Error('Explicit source sha256 receipt and apply mode are required');
 const receiptPath=resolve(options['--receipt']);const parent=await realpath(dirname(receiptPath));
 const repo=await realpath(resolve(import.meta.dirname,'../..'));
 if(parent===repo||parent.startsWith(repo+'/'))throw new Error('Private migration receipts must remain outside the checkout');
 const snapshot=await readSnapshot(resolve(options['--source']),options['--sha256']);
 const runId=randomUUID();let receipt={format:'collect.snapshot.stage-journal.v1',run_id:runId,schema:'collect_stage_'+runId.replaceAll('-',''),source_sha256:snapshot.source_sha256,table_count:snapshot.tables.length,row_count:snapshot.tables.reduce((n,t)=>n+t.row_count,0),promoted:false,applied:false,status:'prepared'};
 const file=await open(receiptPath,'wx',0o600);
 const persist=async()=>{await file.truncate(0);await file.write(JSON.stringify(receipt,null,2)+'\n',0,'utf8');await file.sync();};
 try{await persist();
 if(options['--apply']==='true'){
  const options=databaseConnectionOptions(process.env.COLLECT_SUPABASE_DB_URL,'rrlduytparvsjfmegalh');
  const require=createRequire(import.meta.url);const {Client}=require(process.env.COLLECT_PG_MODULE??'pg');
  const client=new Client(options);
  try{await client.connect();receipt={...await stageSnapshot(client,snapshot,{runId}),applied:true,status:'verified_staged'};await persist();}catch(error){receipt={...receipt,status:'unknown_or_failed_reconcile_before_retry'};await persist();throw error;}finally{await client.end();}
 }
 else{receipt.status='preview_only';await persist();}
 }finally{await file.close();}
 console.log(JSON.stringify({applied:receipt.applied,promoted:false,verified:receipt.verified??null,table_count:receipt.table_count,row_count:receipt.row_count}));
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href)main(process.argv.slice(2)).catch(()=>{console.error('Snapshot stage refused or failed; no application rows were promoted. Reconcile any staging schema before retry.');process.exitCode=1;});
