import {ApiError,digest,stableJson} from './core.js';
import {erasableTables,ownRowInventory,rowPages,SQL_OWN_ROW_LIMIT} from './privacy_retention_chunks.js';
import {privateRetentionCatalogIdentity,inventoryPrivateRetention,privateRetentionGuards} from '../private-retention.js';
import {retentionColumns,engineTables,copyClasses,retentionSchemaProfiles} from './privacy_retention/columns.js';
import {retentionSelection} from './privacy_retention/selectors.js';

export {erasableTables} from './privacy_retention_chunks.js';
export {
 retentionColumns,momoPipelineRetentionColumns,momoFinancialRetentionColumns,googleAuthRetentionColumns,
 adminOtpRetentionColumns,adminEmailRetentionColumns,diagnosticRetentionColumns,notificationDeliveryRetentionColumns,
 notificationChannelRetentionColumns,engineTables,copyClasses,retentionClasses,
} from './privacy_retention/columns.js';
export {retentionSelection} from './privacy_retention/selectors.js';

const fail=code=>{throw new ApiError(409,code,'Retention source coverage could not be verified.');};
const all=async(env,sql,...args)=>(await env.DB.prepare(sql).bind(...args).all()).results;
export async function retentionSchema(env){
 const provider={_cf_METADATA:"CREATE TABLE _cf_METADATA (\n        key INTEGER PRIMARY KEY,\n        value BLOB\n      )",_cf_KV:'CREATE TABLE _cf_KV (\n        key TEXT PRIMARY KEY,\n        value BLOB\n      ) WITHOUT ROWID',d1_migrations:'CREATE TABLE "d1_migrations"(\n\t\tid         INTEGER PRIMARY KEY AUTOINCREMENT,\n\t\tname       TEXT UNIQUE,\n\t\tapplied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL\n)'};
 const observed=await all(env,"SELECT type,name,tbl_name,sql FROM sqlite_schema WHERE sql IS NOT NULL AND name NOT GLOB 'sqlite_*' ORDER BY type,name"),schema=[];
 for(const row of observed){
  if(Object.hasOwn(provider,row.name)||Object.hasOwn(provider,row.tbl_name)||/^_cf_/i.test(row.name)||/^_cf_/i.test(row.tbl_name)){
   if(row.type!=='table'||row.name!==row.tbl_name||row.sql!==provider[row.name])fail('privacy_retention_unknown_class');
  }else schema.push(row);
 }
 for(const row of await all(env,'SELECT name FROM sqlite_sequence'))if(/^_cf_/i.test(row.name))fail('privacy_retention_unknown_class');
 const names=schema.filter(r=>r.type==='table').map(r=>r.name).sort();
 const candidates=retentionSchemaProfiles().filter(([,columns])=>stableJson(names)===stableJson([...Object.keys(columns),...engineTables].sort()));
 if(!candidates.length)fail('privacy_retention_unknown_class');
 // auth17 and SQL11 have identical table names. Select only after comparing
 // every ordered column against a complete explicit catalog, never a subset.
 const actualColumns={};
 for(const table of Object.keys(candidates[0][1]))actualColumns[table]=(await all(env,'PRAGMA table_info("'+table+'")')).map(r=>r.name);
 const exactProfiles=candidates.filter(([,columns])=>Object.entries(columns).every(([table,expected])=>stableJson(actualColumns[table])===stableJson(expected)));
 if(exactProfiles.length!==1)fail('privacy_retention_schema_changed');
 const profile=exactProfiles[0];
 const privateInventory=await privateRetentionCatalogIdentity(env);
 const currentPrivate=['private:admin_email_operations','private:admin_sensitive_email_proofs','private:collect_fence_source_upgrades'];
 if(['admin_email11','diagnostics15','notifications16','notification_channels17','payment_display_reference'].includes(profile[0])?!currentPrivate.every(name=>privateInventory.classes.includes(name)):currentPrivate.some(name=>privateInventory.classes.includes(name)))fail('privacy_retention_schema_changed');
 return {sha256:await digest(stableJson({application:schema,private_inventory:privateInventory})),privateInventory,tables:names,catalog:observed,profile:profile[0],columns:profile[1],classes:['access',...Object.keys(profile[1]),...engineTables,...copyClasses,...privateInventory.classes]};
}
export async function retentionSnapshot(env,subject,{limit=500}={}){
 const schema=await retentionSchema(env),tables={},rows={};let contextRows=0,ownRowsCount=0,totalBytes=0;
 if((await env.DB.prepare('SELECT count(*) AS n FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p.id=g.plan_id WHERE p.subject_id=?').bind(subject).first()).n)fail('privacy_retention_orphan_guard_unresolved');
 for(const table of Object.keys(schema.columns)){
  const where=retentionSelection(table,subject,schema.columns),chunked=erasableTables.includes(table),found=chunked?await ownRowInventory(env,table,where):await all(env,'SELECT * FROM "'+table+'" WHERE '+where.sql+' LIMIT ?',...where.args,limit+1);
  const own=chunked?found.filter(row=>row.user_id===subject).length:0;ownRowsCount+=own;contextRows+=found.length-own;if(!chunked&&found.length>limit||contextRows>500||ownRowsCount>SQL_OWN_ROW_LIMIT)fail('privacy_retention_inventory_limit');
  for(const row of found)for(const value of Object.values(row))if(typeof value==='number'&&!Number.isSafeInteger(value))fail('privacy_retention_precision_unavailable');
  const ordered=found.map(row=>({row,json:stableJson(row)})).sort((a,b)=>a.json.localeCompare(b.json));
  rows[table]=ordered.map(({row})=>row);
  const json='['+ordered.map(({json})=>json).join(',')+']';
  totalBytes+=new TextEncoder().encode(json).byteLength;
  if(totalBytes>1024*1024)fail('privacy_retention_inventory_limit');
  tables[table]={count:found.length,sha256:await digest(json)};
 }
 const objects=[];let objectBytes=0;
 for(const table of ['payment_evidence','sms_receipts','roster_imports','upload_objects'])for(const row of rows[table]){
  const key=row.source_object_key??row.object_key;
  if(typeof key!=='string'||!key||key.length>1024)fail('privacy_retention_object_unknown');
  if(objects.some(o=>o.key===key))fail('privacy_retention_shared_object');
  if(!env.PRIVATE_MEDIA?.get||!env.PRIVATE_MEDIA?.head)fail('privacy_retention_storage_unavailable');
  if(objects.length>=20)fail('privacy_retention_object_limit');
  const observation=typeof env.PRIVATE_MEDIA.observeRetention==='function'?await env.PRIVATE_MEDIA.observeRetention(key):{kind:'legacy_observation',object:await env.PRIVATE_MEDIA.get(key)};
  if(!observation||!['present','absence_verified','pending_erasure_absence','legacy_observation'].includes(observation.kind)||observation.kind==='present'&&!observation.object||['absence_verified','pending_erasure_absence'].includes(observation.kind)&&observation.object!==null)fail('privacy_retention_object_unknown');
  if(observation.kind==='pending_erasure_absence'&&(typeof observation.operationId!=='string'||!/^[a-f0-9]{64}$/.test(observation.sourceSha256??'')))fail('privacy_retention_object_unknown');
  const object=observation.object;objectBytes+=object?.size??0;
  if(objectBytes>8*1024*1024)fail('privacy_retention_object_limit');
  const body=object?new Uint8Array(await object.arrayBuffer()):null;
  objects.push({class_name:'r2:'+table,record_id:row.id,key,catalog_sha256:row.object_sha256??row.sha256,catalog_size:row.size_bytes??row.source_size,owner_user_id:row.owner_user_id??row.user_id,
   present:!!object,version:object?.version??null,etag:object?.etag??null,size:body?.byteLength??null,body_sha256:body?await digest(body):null,...(observation.kind==='pending_erasure_absence'?{pending_erasure:{operation_id:observation.operationId,source_sha256:observation.sourceSha256,absence_verified:true}}:{})});
 }
 objects.sort((a,b)=>a.key.localeCompare(b.key));
 const balances={};for(const row of rows.ledger_entries){const key=row.collection_id+':'+(row.member_id??'unassigned');balances[key]=((BigInt(balances[key]??'0'))+BigInt(row.amount_minor)).toString();}
 const holds=[...rows.privacy_holds.filter(r=>r.active===1).map(r=>({id:r.id,category:r.category})),...rows.payment_evidence.filter(r=>r.legal_hold===1).map(r=>({id:r.id,category:'financial_evidence'}))];
 const inFlight=(rows.admin_email_otp_challenges??[]).some(r=>r.used_at===null&&['pending','accepted','unknown'].includes(r.delivery_status)&&r.expires_at>Math.floor(Date.now()/1000))||(rows.auth_google_flows??[]).some(r=>['pending','exchanging','ready'].includes(r.status)&&r.expires_at>Math.floor(Date.now()/1000))||rows.native_reservations.some(r=>!['completed','rejected'].includes(r.state))||rows.roster_imports.some(r=>['processing','ambiguous'].includes(r.state))||rows.auth_otp_challenges.some(r=>['dispatching','delivery_unknown'].includes(r.status))||rows.assisted_sms_jobs.some(r=>!['observed_sent','failed_no_send'].includes(r.state))||(rows.momo_processing_jobs??[]).some(r=>r.state!=='completed')||(rows.momo_processing_guards??[]).length>0||(rows.notification_deliveries??[]).some(r=>['pending','claimed','sending','retry','unknown'].includes(r.state))||(rows.notification_email_deliveries??[]).some(r=>['pending','sending','unknown'].includes(r.state))||(rows.notification_email_job_dispatches??[]).some(r=>['claimed','unknown'].includes(r.state))||(rows.assisted_sms_dispatches??[]).some(r=>['ready','sending','unknown'].includes(r.state));
 const privateInventory=await inventoryPrivateRetention(env,subject);
 const summary={subject_id:subject,schema_sha256:schema.sha256,tables,objects,holds,in_flight_unresolved:inFlight||privateInventory.in_flight_unresolved,balances,ledger_sha256:tables.ledger_entries.sha256,private_inventory:privateInventory};
 return {summary,rows,schemaCatalog:schema.catalog,columns:schema.columns,classes:schema.classes,sha256:await digest(stableJson(summary))};
}
export async function retentionApprovalScope(snapshot){
 // The approved decision cannot contain its own hash recursively. Its exact
 // raw bytes are pinned separately at activation and in every transaction;
 // every other configuration row remains part of the approved inventory.
 const config=snapshot.rows.runtime_config.filter(r=>r.key!=='privacy:retention:approved:v1');
 const tables={...snapshot.summary.tables,runtime_config:{count:config.length,sha256:await digest(stableJson(config))}};
 return digest(stableJson({...snapshot.summary,tables,approved_policy_copy:'separately_bound_by_raw_sha256'}));
}
export const ownRows=(table,rows,subject)=>rows.filter(row=>row.user_id===subject);
export const rowKey=(table,row)=>table==='notification_preferences'?row.user_id:row.id;
function preimageGuard(env,planId,className,table,where,found,totalCount=found.length){
 // Full-column JSON comparisons preserve exact coverage with a whole-scope
 // count in every guard. Only the four own-row adapters page these preimages;
 // transient row contents never enter retained task metadata.
 const columns=Object.keys(found[0]??{});
 // PostgreSQL row JSON preserves BIGINT/TEXT/NULL storage classes. Comparing
 // each BIGINT to the text json_extract return type is not equivalent SQL.
 const predicate=columns.length?' AND NOT EXISTS(SELECT 1 FROM json_each(?) j WHERE NOT EXISTS(SELECT 1 FROM "'+table+'" r WHERE to_jsonb(r)=j.value::jsonb))':'';
 return env.DB.prepare('INSERT INTO privacy_retention_guards(id,plan_id,class_name,passed) SELECT ?,?,?,(CASE WHEN (SELECT count(*) FROM "'+table+'" WHERE '+where.sql+')=?'+predicate+' THEN 1 ELSE 0 END)')
  .bind(crypto.randomUUID(),planId,className,...where.args,totalCount,...(columns.length?[stableJson(found)]:[]));
}
export const sourceRowsGuard=(env,table,rows,subject,guard)=>{
 if(!erasableTables.includes(table))fail('privacy_retention_adapter_unavailable');
 const targets=ownRows(table,rows,subject);return rowPages(targets).map(page=>preimageGuard(env,guard.planId,table,table,{sql:'user_id=?',args:[subject]},page,targets.length));
};
export function snapshotCompareGuards(env,plan,snapshot,className,options={}){
 const statements=Object.entries(snapshot.rows).flatMap(([table,found])=>(erasableTables.includes(table)?rowPages(found):[found]).map(page=>preimageGuard(env,plan.id,className,table,retentionSelection(table,plan.subject_id,snapshot.columns??retentionColumns),page,found.length)));
 const catalog=snapshot.schemaCatalog;
 // Compare the entire exact raw source catalog, including reviewed metadata.
 // SQL LIKE underscores are wildcards; no provider-prefix or name is omitted
 // from this in-batch source fence after its initial strict admission.
 const filter="sql IS NOT NULL AND name NOT GLOB 'sqlite_*'";
 const match=['type','name','tbl_name','sql'].map(c=>`s."${c}" IS json_extract(j.value,'$."${c}"')`).join(' AND ');
 statements.push(env.DB.prepare('INSERT INTO privacy_retention_guards(id,plan_id,class_name,passed) SELECT ?,?,?,(CASE WHEN (SELECT count(*) FROM sqlite_schema WHERE '+filter+')=? AND NOT EXISTS(SELECT 1 FROM json_each(?) j WHERE NOT EXISTS(SELECT 1 FROM sqlite_schema s WHERE '+match+')) THEN 1 ELSE 0 END)').bind(crypto.randomUUID(),plan.id,className,catalog.length,stableJson(catalog)));
 statements.push(...privateRetentionGuards(env,plan,snapshot,className,options));
 return statements;
}

export async function retentionEngineRows(env,planId,table){
 if(!engineTables.includes(table))fail('privacy_retention_unknown_class');
 const where=table==='privacy_retention_plans'?'id=?':table==='privacy_retention_claims'||table==='privacy_retention_outcomes'||table==='privacy_retention_effects'?'task_id IN(SELECT id FROM privacy_retention_tasks WHERE plan_id=?)':'plan_id=?';
 const found=await all(env,'SELECT * FROM "'+table+'" WHERE '+where+' LIMIT 501',planId);
 if(found.length>500||new TextEncoder().encode(stableJson(found)).byteLength>1024*1024)fail('privacy_retention_inventory_limit');
 return {rows:found,where:{sql:where,args:[planId]}};
}
export const engineRowsGuard=(env,planId,table,observed)=>preimageGuard(env,planId,table,table,observed.where,observed.rows);
