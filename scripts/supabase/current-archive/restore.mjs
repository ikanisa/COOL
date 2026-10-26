import {randomUUID} from 'node:crypto';
import {ArchiveError,need,canonical,sha,identifier,columnType,outputExpression,sealTable,validateSnapshot} from './codec.mjs';
import {SETTINGS} from './sql.mjs';
export function localAdminUrl(raw){let u;try{u=new URL(raw);}catch{throw Error('LOCAL_DATABASE_URL_REQUIRED');}need(['postgres:','postgresql:'].includes(u.protocol)&&['127.0.0.1','[::1]'].includes(u.hostname)&&u.pathname==='/postgres'&&u.username&&u.password&&!u.search&&!u.hash&&(!u.port||/^\d{1,5}$/.test(u.port)&&+u.port>0&&+u.port<=65535),'LOCAL_DATABASE_URL_REQUIRED');if(!u.port)u.port='5432';return u;}
export async function restoreInertArchive(snapshot,{adminUrl,makeClient}={}){
 validateSnapshot(snapshot);need(typeof makeClient==='function','LOCAL_CLIENT_FACTORY_REQUIRED');const u=localAdminUrl(adminUrl),name='collect_archive_'+randomUUID().replaceAll('-','')+'_test',admin=makeClient(u.href),targetUrl=new URL(u);targetUrl.pathname='/'+name;let created=false;
 await admin.connect();try{const id=(await admin.query('SELECT current_database()::text AS database,pg_catalog.host(pg_catalog.inet_server_addr()) AS address')).rows[0];need(id?.database==='postgres'&&['127.0.0.1','::1'].includes(id.address),'LOCAL_DATABASE_IDENTITY_REQUIRED');await admin.query('CREATE DATABASE '+identifier(name)+' TEMPLATE template0 ENCODING \'UTF8\'');created=true;}finally{await admin.end();}
 const db=makeClient(targetUrl.href);await db.connect();let begun=false;
 try{
  const id=(await db.query('SELECT current_database()::text AS database,pg_catalog.host(pg_catalog.inet_server_addr()) AS address,current_setting(\'server_version_num\') AS version')).rows[0];need(id?.database===name&&['127.0.0.1','::1'].includes(id.address)&&/^17[0-9]{4}$/.test(id.version),'LOCAL_DATABASE_IDENTITY_REQUIRED');
  const occupied=(await db.query("SELECT nspname FROM pg_catalog.pg_namespace WHERE nspname NOT LIKE 'pg_%' AND nspname NOT IN('information_schema','public') UNION ALL SELECT n.nspname FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' LIMIT 1")).rows;need(!occupied.length,'NEW_DATABASE_NOT_EMPTY');
  await db.query('BEGIN');begun=true;for(const q of SETTINGS.filter(q=>!q.startsWith('SET LOCAL row_security')))await db.query(q);
  await db.query('CREATE SCHEMA archive_data');await db.query('REVOKE ALL ON SCHEMA archive_data FROM PUBLIC');
  await db.query('CREATE TABLE archive_data.manifest (singleton pg_catalog.bool PRIMARY KEY CHECK(singleton),descriptor pg_catalog.text NOT NULL)');
  const {tables,...meta}=snapshot;await db.query('INSERT INTO archive_data.manifest VALUES(true,$1::pg_catalog.text)',[canonical({...meta,tables:tables.map(({rows,...t})=>t)})]);
  const result=[];
  for(const [index,t]of tables.entries()){
   const tableName='t'+String(index).padStart(4,'0');
   await db.query('CREATE TABLE archive_data.'+identifier(tableName)+' ('+t.columns.map(c=>identifier(c.name)+' '+columnType(c).sql+(c.not_null?' NOT NULL':'')).join(',')+')');
   await db.query('REVOKE ALL ON TABLE archive_data.'+identifier(tableName)+' FROM PUBLIC');
   const statement='INSERT INTO archive_data.'+identifier(tableName)+' ('+t.columns.map(c=>identifier(c.name)).join(',')+') VALUES('+t.columns.map((c,i)=>'$'+(i+1)+'::'+columnType(c).sql).join(',')+')';
   for(const r of t.rows)await db.query(statement,r.cells);
   const columns=(await db.query('/* archive:inert-columns */ SELECT attname::pg_catalog.text AS name,atttypid::pg_catalog.text AS type_oid,atttypmod::pg_catalog.text AS typmod,attnotnull AS not_null FROM pg_catalog.pg_attribute WHERE attrelid=$1::pg_catalog.regclass AND attnum>0 AND NOT attisdropped ORDER BY attnum',['archive_data.'+tableName])).rows;
   need(canonical(columns)===canonical(t.columns.map(c=>({name:c.name,type_oid:c.type_oid,typmod:c.typmod,not_null:c.not_null}))),'NATIVE_COLUMNS_CHANGED');
   const data=await db.query({text:'/* archive:inert-rows */ SELECT '+t.columns.map(c=>outputExpression(c)).join(',')+' FROM archive_data.'+identifier(tableName)+' t LIMIT $1',values:[t.row_count+1],rowMode:'array'});need(data.fields?.length===t.columns.length&&data.fields.every(f=>f.dataTypeID===25),'TEXT_WIRE_REQUIRED');
   const recovered=sealTable({schema:t.schema,name:t.name,kind:t.kind,columns:t.columns,rows:data.rows},snapshot.limits);need(canonical(recovered)===canonical(t),'NATIVE_ROUNDTRIP_MISMATCH');result.push({source:t.schema+'.'+t.name,inert_table:'archive_data.'+tableName,rows:t.row_count,sha256:t.sha256});
  }
  const descriptor=(await db.query('SELECT descriptor FROM archive_data.manifest')).rows;need(descriptor.length===1&&descriptor[0].descriptor===canonical({...meta,tables:tables.map(({rows,...t})=>t)}),'MANIFEST_ROUNDTRIP_MISMATCH');
  const active=(await db.query("SELECT n.nspname FROM pg_catalog.pg_namespace n WHERE n.nspname IN('app','private','auth','storage','api') UNION ALL SELECT n.nspname FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='archive_data' UNION ALL SELECT n.nspname FROM pg_catalog.pg_trigger x JOIN pg_catalog.pg_class c ON c.oid=x.tgrelid JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='archive_data' AND NOT x.tgisinternal")).rows;need(!active.length,'OPERATIONAL_OBJECT_FORBIDDEN');
  await db.query('COMMIT');begun=false;return {format:'collect.sql-archive.inert-restore-receipt.v1',database:name,created_new_database:created,snapshot_sha256:sha(canonical(snapshot)),tables:result,columns_and_native_cells_exact:true,inert_data_only:true,managed_auth_storage_ddl_dml:false,operational_functions_triggers:false,production_restore_authority:false,full_recovery_acceptance:false};
 }catch(error){const safe=error instanceof ArchiveError?error:new ArchiveError('INERT_RESTORE_FAILED');safe.database=name;throw safe;}finally{try{if(begun)await db.query('ROLLBACK');}catch{const e=new ArchiveError('LOCAL_ROLLBACK_UNCONFIRMED');e.database=name;throw e;}finally{await db.end();}}
 // Preserve failed/successful fixture databases for independent review. No drop.
}
