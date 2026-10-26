// Root-only synthetic/native definition. Importing does not launch PG or run tests.
import assert from 'node:assert/strict';
import {randomUUID,randomBytes} from 'node:crypto';
import REAL from './REFERENCE.json' with {type:'json'};
import {CAPS} from './counts.mjs';
import {fixtureMetadataSQL,makeFixtureReference,compileFixtureCaptureRequest,assembleCaptureResponse,encryptAuthSnapshot,decryptAuthSnapshot,restoreAuthInert,sealAuthTable,FORMAT,SCOPE} from './auth.mjs';
import {PROJECT,canonical,sha,identifier,columnType,ArchiveError,need} from '../current-archive/codec.mjs';
import {localAdminUrl} from '../current-archive/restore.mjs';
export const SYNTHETIC_PROJECT=Object.freeze({project_ref:PROJECT,organization_id:'ghnjnepwvwknswrwzepn',status:'ACTIVE_HEALTHY'});
export function syntheticValue(r,c,index=0){
 const t=r.types.find(t=>t.oid===c.type_oid);if(!c.not_null&&index%7===6)return null;
 if(t.kind==='e')return t.enum_labels[index%t.enum_labels.length].label;
 switch(t.oid){
 case '16':return index%2?'f':'t';
 case '17':return index%2?'\\x':'\\x00ff';
 case '20':return index%2?'-9223372036854775808':'9223372036854775807';
 case '21':return index%2?'-32768':'32767';
 case '23':return index%2?'-2147483648':'2147483647';
 case '25':return index%2?'NULL':'synthetic quote" slash\\ unicode-é';
 case '1043':return 'synthetic-'+index;
 case '114':return ' { "x" : 1, "x": 2 } ';
 case '3802':return '{"a":1,"b":2}';
 case '1114':return '2026-10-24 00:00:00.123456';
 case '1184':return '2026-10-24 00:00:00.123456+00';
 case '2950':return '00000000-0000-0000-0000-'+String(index+1).padStart(12,'0');
 case '869':return ['192.0.2.7/24','2001:db8::7/64','192.0.2.1','::1'][index%4];
 case '1009':return ['{}','[0:1]={a,b}','{{a,b},{c,d}}','{NULL,"NULL","a,b",""}'][index%4];
 default:throw new ArchiveError('SYNTHETIC_TYPE_NOT_DEFINED');
 }
}
function sourceType(r,c){const t=r.types.find(t=>t.oid===c.type_oid);if(t.kind==='e')return 'auth.'+identifier(t.name);if(t.oid==='869')return 'pg_catalog.inet';if(t.oid==='1009')return 'pg_catalog.text[]';return columnType({type_oid:c.type_oid,typmod:c.typmod,type_schema:t.schema,type_name:t.name,type_kind:t.kind,base_oid:t.base_oid,element_oid:t.element_oid,output_schema:t.output_function.schema,output_name:t.output_function.name}).sql;}
export function syntheticSnapshot(){
 const r={...REAL,fixture:true},requestId='36aa1b61-45eb-42e8-b946-e5a7b688c5ab';
 return {format:FORMAT,scope:SCOPE,project_ref:PROJECT,fixture:true,reference:r,reference_sha256:sha(canonical(r)),postgres:{database:'collect_auth_source_'+'1'.repeat(32)+'_test',server_version_num:'170000',read_only:'on',isolation:'repeatable read',row_security:'off',server_encoding:'UTF8',client_encoding:'UTF8',timezone:'UTC',date_style:'ISO, YMD',bytea_output:'hex',extra_float_digits:'3',interval_style:'postgres',standard_conforming_strings:'on',application_name:'collect.authmeta.'+requestId.replaceAll('-','')},sequence:{schema:'auth',name:'refresh_tokens_id_seq',oid:REAL.relations.find(t=>t.kind==='S').oid,last_value:'1',is_called:false,type_oid:'20',start:'1',increment:'1',min:'1',max:'9223372036854775807',cache:'1',cycle:false},sequence_endpoints_equal:true,auth_quiescence_proven:false,counts_preflight_sha256:'1'.repeat(64),tables:REAL.relations.filter(t=>t.kind==='r').map(t=>sealAuthTable(r,t.name,[])),caps:CAPS,production_restore_authority:false,full_recovery_acceptance:false};
}
function batchRows(result,field){need(Array.isArray(result)&&result.at(-1)?.command==='ROLLBACK','SYNTHETIC_NATIVE_ROLLBACK_REQUIRED');const expectedCommand=field==='QUERY PLAN'?'EXPLAIN':'SELECT';const selected=result.filter(x=>x.command===expectedCommand&&(x.fields?.some(f=>f.name===field)||x.rows?.some(r=>Object.hasOwn(r,field))));need(selected.length===1,'SYNTHETIC_NATIVE_RESULT_REQUIRED');return selected[0].rows;}
export async function runNativeDefinition({adminUrl,makeClient,onMetadata}={}){
 need(typeof makeClient==='function','SYNTHETIC_LOCAL_CLIENT_REQUIRED');const u=localAdminUrl(adminUrl),database='collect_auth_source_'+randomUUID().replaceAll('-','')+'_test',target=new URL(u);target.pathname='/'+database;
 const admin=makeClient(u.href);await admin.connect();
 try{const id=(await admin.query("SELECT current_database()::text AS database,pg_catalog.host(pg_catalog.inet_server_addr()) AS address,current_setting('server_version_num') AS version")).rows[0];need(id?.database==='postgres'&&['127.0.0.1','::1'].includes(id.address)&&/^17[0-9]{4}$/.test(id.version),'SYNTHETIC_OWNED_PG17_REQUIRED');await admin.query('CREATE DATABASE '+identifier(database)+" TEMPLATE template0 ENCODING 'UTF8'");}catch(e){if(e instanceof ArchiveError)throw e;throw new ArchiveError('SYNTHETIC_SOURCE_CREATE_UNCONFIRMED');}finally{try{await admin.end();}catch{throw new ArchiveError('SYNTHETIC_CLOSE_UNCONFIRMED');}}
 const db=makeClient(target.href);await db.connect();let raw;const cases=[];
 try{
  const id=(await db.query("SELECT current_database()::text AS database,pg_catalog.host(pg_catalog.inet_server_addr()) AS address,current_setting('server_version_num') AS version")).rows[0];need(id?.database===database&&['127.0.0.1','::1'].includes(id.address)&&/^17[0-9]{4}$/.test(id.version),'SYNTHETIC_OWNED_PG17_REQUIRED');
  await db.query('SET standard_conforming_strings=on');
  await db.query('CREATE SCHEMA auth');
  for(const t of REAL.types.filter(t=>t.kind==='e')){need(t.enum_labels.every(e=>/^[a-z0-9_]+$/.test(e.label)),'SYNTHETIC_ENUM_INVALID');await db.query('CREATE TYPE auth.'+identifier(t.name)+' AS ENUM ('+t.enum_labels.map(e=>"'"+e.label+"'").join(',')+')');}
  await db.query('CREATE SEQUENCE auth.refresh_tokens_id_seq AS bigint START 1');
  for(const table of REAL.relations.filter(t=>t.kind==='r')){
   const columns=REAL.columns.filter(c=>c.relation_oid===table.oid),byPosition=new Map(columns.map(c=>[+c.position,c])),defs=[],gaps=[];
   for(let position=1;position<=Math.max(...byPosition.keys());position++){
    const c=byPosition.get(position);if(!c){const gap='synthetic_gap_'+position;defs.push(identifier(gap)+' pg_catalog.int4');gaps.push(gap);continue;}
    let def=identifier(c.name)+' '+sourceType(REAL,c);
    if(c.generated==='s'){const type=REAL.types.find(t=>t.oid===c.type_oid);const expression=c.not_null?(type.oid==='16'?'true':"'synthetic'"):'NULL';def+=' GENERATED ALWAYS AS ('+expression+'::'+sourceType(REAL,c)+') STORED';}
    else if(c.has_default){const value=syntheticValue(REAL,c,0);need(typeof value==='string','SYNTHETIC_DEFAULT_VALUE_REQUIRED');def+=" DEFAULT '"+value.replaceAll("'","''")+"'::"+sourceType(REAL,c);}
    if(c.not_null)def+=' NOT NULL';defs.push(def);
   }
   await db.query('CREATE TABLE auth.'+identifier(table.name)+' ('+defs.join(',')+')');
   for(const gap of gaps)await db.query('ALTER TABLE auth.'+identifier(table.name)+' DROP COLUMN '+identifier(gap));
   const selected=columns.filter(c=>!c.generated),special=columns.some(c=>['869','1009'].includes(c.type_oid)||REAL.types.find(t=>t.oid===c.type_oid).kind==='e'),rowCount=special?8:2;
   const sql='INSERT INTO auth.'+identifier(table.name)+' ('+selected.map(c=>identifier(c.name)).join(',')+') VALUES('+selected.map((c,i)=>'$'+(i+1)+'::'+sourceType(REAL,c)).join(',')+')';
   for(let i=0;i<rowCount;i++)await db.query(sql,selected.map(c=>syntheticValue(REAL,c,i)));
  }
  const metadataResult=await db.query(fixtureMetadataSQL(randomUUID(),database)),metadata=batchRows(metadataResult,'value')[0].value;
  if(onMetadata!==undefined){need(typeof onMetadata==='function','SYNTHETIC_METADATA_CALLBACK_REQUIRED');await onMetadata(metadata);}
  const r=makeFixtureReference(metadata);
  cases.push('exact27table271column23type9enumfixture_catalogue');
  const countTables=[];for(const t of r.relations.filter(t=>t.kind==='r'))countTables.push({schema:'auth',name:t.name,rows:(await db.query('SELECT count(*)::text AS rows FROM ONLY auth.'+identifier(t.name))).rows[0].rows});
  const counts={format:'collect.managed-auth.synthetic-counts.v1',reference_sha256:sha(canonical(r)),within_capture_row_caps:true,exact_auth_row_counts_measured:true,auth_cell_values_returned:false,sequence_values_returned:false,capture_dispatched:false,tables:countTables};
  const request=compileFixtureCaptureRequest(r,counts,randomUUID(),database);assert.equal(request.method,'LOCAL_NATIVE_FIXTURE');assert.equal(request.url,null);
  await db.query("SET DateStyle='SQL, DMY'");await db.query("SET bytea_output='escape'");
  const captureResult=await db.query(request.body.query);raw=Buffer.from(JSON.stringify(batchRows(captureResult,'kind')));
  const snapshot=assembleCaptureResponse({status:201,body:raw},{reference:r,counts,request,project:SYNTHETIC_PROJECT,allowFixture:true});raw.fill(0);raw=null;
  assert.equal(snapshot.fixture,true);for(const [setting,value]of Object.entries({date_style:'ISO, YMD',bytea_output:'hex',extra_float_digits:'3',interval_style:'postgres',standard_conforming_strings:'on'}))assert.equal(snapshot.postgres[setting],value);cases.push('native_capture_output_settings_observed');assert.equal(snapshot.tables.reduce((n,t)=>n+t.row_count,0),countTables.reduce((n,t)=>n+Number(t.rows),0));cases.push('sameRR_native_capture_all27tables_and_separate_sequence');
  const key=randomBytes(32);let encrypted;
  try{encrypted=encryptAuthSnapshot(snapshot,key,{allowFixture:true});assert.equal(canonical(decryptAuthSnapshot(encrypted,key,{allowFixture:true}).snapshot),canonical(snapshot));assert.throws(()=>decryptAuthSnapshot(encrypted,key));const wrong=randomBytes(32);try{assert.throws(()=>decryptAuthSnapshot(encrypted,wrong,{allowFixture:true}));}finally{wrong.fill(0);}cases.push('authenticated_fixture_roundtrip_and_wrongkey_and_livefixture_refusal');}finally{key.fill(0);}
  const restored=await restoreAuthInert(snapshot,{adminUrl,makeClient,allowFixture:true});assert.equal(restored.tables.length,27);assert.equal(restored.enum_mapping.length,9);assert.equal(restored.operational_auth_restored,false);assert.equal(restored.generated_expressions_replayed,false);cases.push('native_inert27tables9enums_allcells_generated_materialized_values');
  const t=r.relations.find(t=>t.kind==='r'&&r.columns.some(c=>c.relation_oid===t.oid&&c.type_oid==='25'&&!c.generated)),c=r.columns.find(c=>c.relation_oid===t.oid&&c.type_oid==='25'&&!c.generated);
  const previous=(await db.query('SELECT '+identifier(c.name)+' AS value FROM auth.'+identifier(t.name)+' LIMIT 1')).rows[0].value;
  await db.query('UPDATE auth.'+identifier(t.name)+' SET '+identifier(c.name)+'=$1::pg_catalog.text',['x'.repeat(CAPS.cellBytes+1)]);
  const overRequest=compileFixtureCaptureRequest(r,counts,randomUUID(),database),overResult=await db.query(overRequest.body.query);const overRows=batchRows(overResult,'kind');assert.ok(overRows.length===0||overRows.every(x=>JSON.parse(x.payload).refused));cases.push('native_cell_budget_refuses_before_returning_cells');
  await db.query('UPDATE auth.'+identifier(t.name)+' SET '+identifier(c.name)+'=$1::pg_catalog.text',[previous]);
  const en=r.types.find(t=>t.kind==='e'),label=en.enum_labels[0].label,drift=label+'_synthetic_drift';
  await db.query('ALTER TYPE auth.'+identifier(en.name)+" RENAME VALUE '"+label+"' TO '"+drift+"'");
  const guarded=compileFixtureCaptureRequest(r,counts,randomUUID(),database),at=guarded.body.query.indexOf('WITH RECURSIVE'),explainSQL=guarded.body.query.slice(0,at)+'EXPLAIN (ANALYZE true, VERBOSE true, FORMAT JSON, TIMING false, SUMMARY false) '+guarded.body.query.slice(at),explanation=batchRows(await db.query(explainSQL),'QUERY PLAN')[0]['QUERY PLAN'];
  const nodes=[];const visit=x=>{if(!x||typeof x!=='object')return;if(x.Schema==='auth'&&x['Relation Name'])nodes.push({name:x['Relation Name'],loops:x['Actual Loops']});for(const value of Object.values(x)){if(Array.isArray(value))for(const y of value)visit(y);else if(value&&typeof value==='object')visit(value);}};visit(explanation);
  const covered=new Set(nodes.map(x=>x.name));assert.ok(r.relations.every(t=>covered.has(t.name)));assert.ok(nodes.every(x=>x.loops===0));cases.push('native_enum_drift_EXPLAIN_all28Auth_relation_and_sequence_scans_ActualLoops0');
  await db.query('ALTER TYPE auth.'+identifier(en.name)+" RENAME VALUE '"+drift+"' TO '"+label+"'");
  const extraName='synthetic_unexpected_relation';await db.query('CREATE TABLE auth.'+identifier(extraName)+' (id pg_catalog.int4)');const changed=compileFixtureCaptureRequest(r,counts,randomUUID(),database),changedResult=await db.query(changed.body.query),changedRows=batchRows(changedResult,'kind');assert.ok(changedRows.length===0||changedRows.every(x=>JSON.parse(x.payload).refused));cases.push('native_extra_relation_catalogue_guard_refusal');
  return {format:'collect.managed-auth.synthetic-native-result.v1',fixture:true,response_shape_simulated:true,source_database:database,inert_database:restored.database,cases,case_count:cases.length,source_reference_sha256:sha(canonical(r)),snapshot_sha256:sha(canonical(snapshot)),encrypted_fixture_sha256:sha(encrypted),native_inert_receipt:restored,real_auth_rows_read:false,provider_calls:0,actual_encrypted_auth_capture_accepted:false,operational_auth_restored:false,full_recovery_acceptance:false,fixture_databases_preserved:true};
 }catch(e){if(e instanceof ArchiveError)throw e;throw new ArchiveError('SYNTHETIC_NATIVE_DEFINITION_UNCONFIRMED');}finally{raw?.fill(0);try{await db.end();}catch{throw new ArchiveError('SYNTHETIC_CLOSE_UNCONFIRMED');}}
}
