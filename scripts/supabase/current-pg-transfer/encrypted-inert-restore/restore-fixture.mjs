// Synthetic fixture only. No archive, key or SQL is accepted from the caller.
import {fstatSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
import pg from '../../node_modules/pg/lib/index.js';
import {snapshot} from '../../current-archive/fixtures.mjs';
import {canonical,sha} from '../../current-archive/codec.mjs';
import {preparePlanCandidate,compileCaptureRequest,assembleManagementSnapshot} from '../../current-archive/capture.mjs';
import {restoreInertArchive} from '../../current-archive/restore.mjs';

const FIXTURE_SHA='3575b6a1ef612c9f0e6fde1794cfe1fb39911bf7d98b5b796acf0da0bf693ab9';
const exact=(o,keys)=>o&&typeof o==='object'&&!Array.isArray(o)&&Object.keys(o).sort().join('\0')===[...keys].sort().join('\0');
const need=(v)=>{if(!v)throw Error('synthetic_restore_refused');};
function syntheticSnapshot(){
 const old=snapshot();need(old.fixture===true&&sha(canonical(old))===FIXTURE_SHA);
 const requestId='00000000-0000-4000-8000-000000000001',fixtureDatabase='collect_archive_source_'+('1'.repeat(32))+'_test';
 const postgres={...old.postgres,database:fixtureDatabase,backend_pid:'1',row_security:'off',application_name:'collect.archive.'+requestId.replaceAll('-','')};
 delete postgres.rolled_back;
 const metadata={format:'collect.mgmt.metadata.v1',postgres,relations:old.tables.map((t,i)=>({schema:t.schema,name:t.name,kind:t.kind,oid:String(i+1),columns_record:canonical(t.columns)})),
  migrations:old.migrations.map(({sha256,...m})=>m),catalog_record:canonical(old.catalog),sequences_record:'[]'};
 const sourceMigrations=old.migrations.map(({observed_record,observed_record_sha256,...m})=>m);
 const plan=preparePlanCandidate(metadata,{runtimeSourceSha256:old.runtime_source_sha256,sourceMigrations,expectedMigrationCount:8,fixtureDatabase});
 const compiled=compileCaptureRequest(plan,{requestId});
 const tables=old.tables.map((t,i)=>{const cells=t.rows.map(r=>r.cells),lengths=cells.flat().filter(v=>v!==null).map(v=>Buffer.byteLength(v));
  return {schema:t.schema,name:t.name,kind:t.kind,oid:String(i+1),columns_record:canonical(t.columns),
   measure:{index:i,rows:String(cells.length),bytes:String(lengths.reduce((a,b)=>a+b,0)),max_cell:String(Math.max(0,...lengths))},cells};});
 const payload={format:'collect.mgmt.data.v1',postgres,tables,migrations:metadata.migrations,catalog_record:metadata.catalog_record,sequences:[]};
 const assembled=assembleManagementSnapshot({status:201,body:Buffer.from(JSON.stringify([{kind:'capture',payload:JSON.stringify(payload)}]))},plan,compiled);
 need(assembled.fixture===true&&assembled.restore_authority===false);return assembled;
}
let raw;
try{
 const source=fstatSync(0);need(process.argv.length===2&&!process.stdin.isTTY&&(source.isFIFO()||source.isSocket()));
 const chunks=[];let size=0;
 for await(const chunk of process.stdin){size+=chunk.length;if(size>4096){chunk.fill(0);for(const c of chunks)c.fill(0);throw Error('input_limit');}chunks.push(chunk);}
 raw=Buffer.concat(chunks,size);for(const c of chunks)c.fill(0);need(raw.length>0);
 const v=JSON.parse(raw.toString('utf8'));
 need(exact(v,['port','password','data','cluster'])&&Number.isSafeInteger(v.port)&&v.port>=1024&&v.port<=65535&&
  /^[a-f0-9]{64}$/.test(v.password??'')&&/^collect_inert_[a-f0-9]{24}$/.test(v.cluster??'')&&
  typeof v.data==='string'&&v.data.startsWith('/private/tmp/collect-encrypted-inert-')&&v.data.endsWith('/mount/data'));
 const fixture=syntheticSnapshot();
 const target='collect_archive_'+randomUUID().replaceAll('-','')+'_test';
 const adminUrl=`postgres://collect_inert_fixture:${v.password}@127.0.0.1:${v.port}/postgres`;
 let systemId=null;
 const makeClient=connectionString=>{
  const u=new URL(connectionString);need(u.protocol==='postgres:'&&u.hostname==='127.0.0.1'&&Number(u.port)===v.port&&
   u.username==='collect_inert_fixture'&&u.password===v.password&&['/postgres','/'+target].includes(u.pathname)&&!u.search&&!u.hash);
  const c=new pg.Client({connectionString,ssl:false,connectionTimeoutMillis:5000,statement_timeout:30000,application_name:'collect_synthetic_inert_restore'});
  c.on('error',()=>{});const connect=c.connect.bind(c);
  c.connect=async()=>{await connect();try{
   const {rows}=await c.query("SELECT current_database()::text AS db,current_user::text AS usr,pg_catalog.host(pg_catalog.inet_server_addr()) AS address,pg_catalog.inet_server_port() AS port,current_setting('data_directory') AS data,current_setting('cluster_name') AS cluster,(SELECT system_identifier::text FROM pg_catalog.pg_control_system()) AS system_id");
   need(rows.length===1&&rows[0].db===u.pathname.slice(1)&&rows[0].usr==='collect_inert_fixture'&&rows[0].address==='127.0.0.1'&&
    rows[0].port===v.port&&rows[0].data===v.data&&rows[0].cluster===v.cluster&&/^\d{1,20}$/.test(rows[0].system_id??''));
   if(systemId===null)systemId=rows[0].system_id;else need(systemId===rows[0].system_id);
  }catch(e){await c.end().catch(()=>{});throw e;}};
  return c;
 };
 const probe=makeClient(adminUrl);await probe.connect();
 await probe.end();
 const receipt=await restoreInertArchive(fixture,{adminUrl,makeClient,databaseName:target});
 need(receipt.created_new_database===true&&receipt.inert_data_only===true&&receipt.columns_and_native_cells_exact===true&&
  receipt.production_restore_authority===false&&receipt.full_recovery_acceptance===false&&receipt.tables.length===1&&receipt.tables[0].rows===1);
 process.stdout.write(JSON.stringify({format:'collect.encrypted-inert.synthetic.v1',synthetic:true,real_archive_read:false,
  tables:1,rows:1,native_cells_verified:true,production_restore_authority:false})+'\n');
}catch{process.stderr.write('SYNTHETIC_INERT_RESTORE_REFUSED\n');process.exitCode=1;}
finally{raw?.fill(0);}
