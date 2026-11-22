import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import catalog from '../../../retention-inventory.json' with {type:'json'};
import {localStoppedColumns} from './helpers/local-stopped-shape.mjs';
import {burimunsiBaseRelations,burimunsiObservationRelations,burimunsiDetectionRelations,burimunsiNativeAutoRelations,burimunsiNativeFinancialRelations,burimunsiNativeFinancialKnownLinks,burimunsiNativeLeaseHistoryRelations,burimunsiNativeLeaseHistoryKnownLinks,burimunsiUnmappedStorageClasses,burimunsiBlockedJournals} from '../burimunsi-retention-inspection.js';
import {privateRetentionCatalogIdentity,inventoryPrivateRetention,assertPrivateRetentionPolicy,assertPrivateRetentionSource,privateRetentionGuards,sharedFenceRetentionClasses} from '../private-retention.js';
import {retentionObjectCount} from '../domain/privacy_retention.js';
import {adminEmailRetentionColumns,adminOtpRetentionColumns,diagnosticRetentionColumns,engineTables,erasableTables,googleAuthRetentionColumns,
 momoFinancialRetentionColumns,momoPipelineRetentionColumns,notificationChannelRetentionColumns,notificationDeliveryRetentionColumns,
 retentionColumns,retentionSchema} from '../domain/privacy_retention_catalog.js';
const sha='a'.repeat(64);
const baseSchema=catalog.classes.filter(x=>x.relation.startsWith('private.')).map(x=>({
 name:x.relation.slice(8),kind:x.relation==='private.object_metadata'?'v':'r',
 columns:x.relation==='private.collect_fence_local_stopped_admissions'?localStoppedColumns:
 x.relation==='private.collect_sms_fence_admissions'?'admission_id:uuid:true,profile_sha256:text:true,created_at:timestamp with time zone:true':'synthetic',constraints:'synthetic',triggers:'synthetic'}));
function fixture({enabled=false,extra=[],schema=baseSchema}={}){
 const calls=[], rows=[...schema,...extra.map(name=>({name,kind:'r',columns:'synthetic',constraints:'synthetic',triggers:'synthetic'}))].sort((a,b)=>a.name.localeCompare(b.name));
 const managed={contract_version:1,schema:{synthetic:true},classes:{'managed:auth':{status:'observed',count:0,rows:[]},'managed:storage':{status:'observed',count:0,rows:[]}}};
 const realtime={contract_version:1,schema:{contract:'collect.member.realtime.inventory.v1',metadata_sha256:sha,partitions_sha256:sha},class:{status:'observed',count:0,rows:[],erasure_verified:false}};
 const DB={prepare(sql){return{sql,args:[],bind(...args){this.args=args;return this;}};},async batch(statements){return statements.map(s=>{
  calls.push(s);if(s.sql.includes("n.nspname='private'"))return{results:rows};
  if(s.sql.startsWith('SELECT private.retention_managed_inventory'))return{results:[{inventory:managed}]};
  if(s.sql.startsWith('SELECT private.retention_member_realtime_inventory'))return{results:[{inventory:realtime}]};
  if(s.sql.includes('pg_get_functiondef'))return{results:[{sha256:sha}]};return{results:[]};
 });}};
 return {env:{DB,...(enabled?{BURIMUNSI_RETENTION_INSPECTION_ENABLED:'true'}:{})},calls,rows};
}
const all=[...burimunsiBaseRelations,...burimunsiObservationRelations];
test('payment references enter the exact payment retention profile and preserve the established financial disposition',async()=>{
 const earlier={...retentionColumns,...momoPipelineRetentionColumns,...momoFinancialRetentionColumns,...googleAuthRetentionColumns,
  ...adminOtpRetentionColumns,...adminEmailRetentionColumns,...diagnosticRetentionColumns,...notificationDeliveryRetentionColumns,...notificationChannelRetentionColumns};
 const columns={...earlier,payments:[...earlier.payments]},legacy=fixture().env;
 const names=[...Object.keys(columns),...engineTables].sort();
 const local=results=>({bind:()=>({all:async()=>({results})})});
 const env={...legacy,DB:{...legacy.DB,prepare(sql){
  if(sql.startsWith('SELECT type,name,tbl_name,sql FROM sqlite_schema'))return local(names.map(name=>({type:'table',name,tbl_name:name,sql:'CREATE TABLE '+name+'('+String(columns[name]??'')+')'})));
  if(sql==='SELECT name FROM sqlite_sequence')return local([]);
  const table=/^PRAGMA table_info\("([^"]+)"\)$/.exec(sql)?.[1];
  if(table)return local(columns[table].map(name=>({name})));
  return legacy.DB.prepare(sql);
 }}};
 const before=await retentionSchema(env);assert.equal(before.profile,'notification_channels17');
 columns.payments.push('payment_reference');
 const after=await retentionSchema(env);assert.equal(after.profile,'payment_display_reference');assert.notEqual(after.sha256,before.sha256);
 assert.deepEqual(after.classes,before.classes);assert.equal(erasableTables.includes('payments'),false);
 columns.payments.push('unreviewed_reference');
 await assert.rejects(retentionSchema(env),{code:'privacy_retention_schema_changed'});
});
test('default-off preserves predecessor identity and rejects BuriMunsi relations',async()=>{
 const ordinary=fixture(),on=fixture({enabled:true});
 assert.equal((await privateRetentionCatalogIdentity(ordinary.env)).catalog_sha256,(await privateRetentionCatalogIdentity(on.env)).catalog_sha256);
 await assert.rejects(privateRetentionCatalogIdentity(fixture({extra:all}).env),{code:'privacy_retention_unknown_private_class'});
});
test('only exact complete cohorts of tables are recognized; unknown, partial or wrong-kind schemas fail closed',async()=>{
 for(const extra of [burimunsiBaseRelations.slice(1),[...burimunsiBaseRelations,...burimunsiObservationRelations.slice(1)],burimunsiObservationRelations,[...all,'burimunsi_unknown']])
  await assert.rejects(privateRetentionCatalogIdentity(fixture({enabled:true,extra}).env),{code:'privacy_retention_unknown_private_class'});
 const f=fixture({enabled:true,extra:all});f.rows.find(x=>x.name===all[0]).kind='v';
 await assert.rejects(privateRetentionCatalogIdentity(f.env),{code:'privacy_retention_unknown_private_class'});
 const full=await privateRetentionCatalogIdentity(fixture({enabled:true,extra:all}).env);
 const predecessor=await privateRetentionCatalogIdentity(fixture({enabled:true,extra:burimunsiBaseRelations}).env);
 assert.equal(full.classes.filter(x=>x.startsWith('private:burimunsi_')).length,32);
 assert.equal(predecessor.classes.filter(x=>x.startsWith('private:burimunsi_')).length,29);
});
test('detection-only profile joins a complete observation cohort and stays unmapped',async()=>{
 const added=[...all,...burimunsiDetectionRelations];
 await assert.rejects(privateRetentionCatalogIdentity(fixture({extra:added}).env),{code:'privacy_retention_unknown_private_class'});
 for(const extra of [burimunsiDetectionRelations,[...burimunsiBaseRelations,...burimunsiDetectionRelations]])
  await assert.rejects(privateRetentionCatalogIdentity(fixture({enabled:true,extra}).env),{code:'privacy_retention_unknown_private_class'});
 const f=fixture({enabled:true,extra:added});const identity=await privateRetentionCatalogIdentity(f.env);
 assert.equal(identity.classes.filter(x=>x.startsWith('private:burimunsi_')).length,33);
 const result=await inventoryPrivateRetention(f.env,'synthetic-subject');
 assert.deepEqual(result.classes['private:burimunsi_detection_profiles'],{status:'unmapped',count:null,sha256:null,rows:null,erasure:'blocked'});
 assert.equal(result.in_flight_unresolved,true);
 const bad=fixture({enabled:true,extra:added});bad.rows.find(x=>x.name===burimunsiDetectionRelations[0]).kind='v';
 await assert.rejects(privateRetentionCatalogIdentity(bad.env),{code:'privacy_retention_unknown_private_class'});
});
test('two subjects receive unknown counts and blocked object custody without subject table reads',async()=>{
 const f=fixture({enabled:true,extra:all});
 for(const subject of ['synthetic-subject-a','synthetic-subject-b']){
  const result=await inventoryPrivateRetention(f.env,subject);
  assert.equal(result.in_flight_unresolved,true);assert.equal(result.object_custody,'unverified');
  for(const name of [...all.map(x=>'private:'+x),...burimunsiUnmappedStorageClasses])
   assert.deepEqual(result.classes[name],{status:'unmapped',count:null,sha256:null,rows:null,erasure:'blocked'});
  assert.equal(retentionObjectCount({summary:{private_inventory:result,objects:[]}}),null);
  assert.throws(()=>privateRetentionGuards(f.env,{id:'p',subject_id:subject},{summary:{private_inventory:result,objects:[]}},'x'),{code:'privacy_retention_burimunsi_unmapped'});
  const changed=structuredClone(result);changed.classes['private:burimunsi_unresolved_observations'].count=0;
  assert.throws(()=>assertPrivateRetentionSource(result,changed),{code:'privacy_retention_private_scope_changed'});
 }
 assert.equal(retentionObjectCount({summary:{private_inventory:{},objects:[]}}),0);
 assert.equal(f.calls.some(x=>/FROM private\.burimunsi_/.test(x.sql)),false);
});
test('unreviewed BuriMunsi and storage classes can only have blocked disposition',async()=>{
 const f=fixture({enabled:true,extra:all}), identity=await privateRetentionCatalogIdentity(f.env);
 const blocked=new Set([...sharedFenceRetentionClasses,...all.map(x=>'private:'+x),...burimunsiUnmappedStorageClasses,'managed:realtime_messages','private:admin_email_operations','private:admin_sensitive_email_proofs',...catalog.unresolved_external_classes]);
 const rules=Object.fromEntries([...identity.classes,...catalog.unresolved_external_classes].map(name=>[name,{action:blocked.has(name)?'blocked':'retain'}]));
 const policy={copy_inventory:{contract_version:1,catalog_sha256:identity.catalog_sha256,unmapped_copies:'blocked',bff_access_revocation:'block'},rules};
 assertPrivateRetentionPolicy(policy,identity);
 for(const name of ['private:burimunsi_accounts','private:burimunsi_unresolved_observations','private:storage_objects','managed:storage'])
  assert.throws(()=>assertPrivateRetentionPolicy({...policy,rules:{...rules,[name]:{action:'retain'}}},identity),{code:'privacy_retention_burimunsi_unmapped'});
});
test('native auto and financial inspection require each complete predecessor cohort',async()=>{
 const prior=[...all,...burimunsiDetectionRelations],auto=[...prior,...burimunsiNativeAutoRelations],full=[...auto,...burimunsiNativeFinancialRelations];
 for(const extra of [[...prior,burimunsiNativeAutoRelations[0]],[...prior,...burimunsiNativeFinancialRelations],
  [...auto,...burimunsiNativeFinancialRelations.slice(1)]])
  await assert.rejects(privateRetentionCatalogIdentity(fixture({enabled:true,extra}).env),{code:'privacy_retention_unknown_private_class'});
 await assert.rejects(privateRetentionCatalogIdentity(fixture({extra:full}).env),{code:'privacy_retention_unknown_private_class'});
 const autoIdentity=await privateRetentionCatalogIdentity(fixture({enabled:true,extra:auto}).env);
 const fullIdentity=await privateRetentionCatalogIdentity(fixture({enabled:true,extra:full}).env);
 assert.equal(autoIdentity.classes.filter(x=>x.startsWith('private:burimunsi_')).length,35);
 assert.equal(fullIdentity.classes.filter(x=>x.startsWith('private:burimunsi_')).length,38);
 assert.match(burimunsiNativeFinancialKnownLinks.burimunsi_native_financial_work,/origin and its principal/);
 assert.match(burimunsiNativeFinancialKnownLinks.burimunsi_native_grant_commands,/command actor/);
 assert.match(burimunsiNativeFinancialKnownLinks.burimunsi_native_work_grants,/approver/);
});
test('native financial classes remain unknown and cannot be erased for either subject',async()=>{
 const extra=[...all,...burimunsiDetectionRelations,...burimunsiNativeAutoRelations,...burimunsiNativeFinancialRelations];
 const f=fixture({enabled:true,extra}),identity=await privateRetentionCatalogIdentity(f.env);
 for(const subject of ['synthetic-source-owner','synthetic-other-subject']){
  const inventory=await inventoryPrivateRetention(f.env,subject);
  for(const relation of [...burimunsiNativeAutoRelations,...burimunsiNativeFinancialRelations])
   assert.deepEqual(inventory.classes['private:'+relation],{status:'unmapped',count:null,sha256:null,rows:null,erasure:'blocked'});
  assert.throws(()=>privateRetentionGuards(f.env,{id:'p',subject_id:subject},{summary:{private_inventory:inventory,objects:[]}},'x'),{code:'privacy_retention_burimunsi_unmapped'});
 }
 const blocked=new Set([...sharedFenceRetentionClasses,...extra.map(x=>'private:'+x),...burimunsiUnmappedStorageClasses,'managed:realtime_messages','private:admin_email_operations','private:admin_sensitive_email_proofs',...catalog.unresolved_external_classes]);
 const rules=Object.fromEntries([...identity.classes,...catalog.unresolved_external_classes].map(name=>[name,{action:blocked.has(name)?'blocked':'retain'}]));
 const policy={copy_inventory:{contract_version:1,catalog_sha256:identity.catalog_sha256,unmapped_copies:'blocked',bff_access_revocation:'block'},rules};
 assertPrivateRetentionPolicy(policy,identity);
 for(const relation of burimunsiNativeFinancialRelations)
  assert.throws(()=>assertPrivateRetentionPolicy({...policy,rules:{...rules,['private:'+relation]:{action:'retain'}}},identity),{code:'privacy_retention_burimunsi_unmapped'});
 assert.equal(f.calls.some(x=>/FROM private\.burimunsi_/.test(x.sql)),false);
});
test('lease history is admitted only with its exact predecessor cohort and stays blocked',async()=>{
 const prior=[...all,...burimunsiDetectionRelations,...burimunsiNativeAutoRelations,...burimunsiNativeFinancialRelations];
 const full=[...prior,...burimunsiNativeLeaseHistoryRelations];
 for(const extra of [burimunsiNativeLeaseHistoryRelations,[...prior.slice(0,-1),...burimunsiNativeLeaseHistoryRelations]])
  await assert.rejects(privateRetentionCatalogIdentity(fixture({enabled:true,extra}).env),{code:'privacy_retention_unknown_private_class'});
 await assert.rejects(privateRetentionCatalogIdentity(fixture({extra:full}).env),{code:'privacy_retention_unknown_private_class'});
 const wrong=fixture({enabled:true,extra:full});wrong.rows.find(x=>x.name===burimunsiNativeLeaseHistoryRelations[0]).kind='v';
 await assert.rejects(privateRetentionCatalogIdentity(wrong.env),{code:'privacy_retention_unknown_private_class'});
 const f=fixture({enabled:true,extra:full}),identity=await privateRetentionCatalogIdentity(f.env);
 assert.equal(identity.classes.filter(x=>x.startsWith('private:burimunsi_')).length,39);
 assert.match(burimunsiNativeLeaseHistoryKnownLinks.burimunsi_native_lease_history,/pre-install lease versions remain unresolved/);
 for(const subject of ['synthetic-source-owner','synthetic-other-subject']){
  const inventory=await inventoryPrivateRetention(f.env,subject);
  assert.deepEqual(inventory.classes['private:burimunsi_native_lease_history'],{status:'unmapped',count:null,sha256:null,rows:null,erasure:'blocked'});
  assert.throws(()=>privateRetentionGuards(f.env,{id:'p',subject_id:subject},{summary:{private_inventory:inventory,objects:[]}},'x'),{code:'privacy_retention_burimunsi_unmapped'});
 }
 const blocked=new Set([...sharedFenceRetentionClasses,...full.map(x=>'private:'+x),...burimunsiUnmappedStorageClasses,'managed:realtime_messages','private:admin_email_operations','private:admin_sensitive_email_proofs',...catalog.unresolved_external_classes]);
 const rules=Object.fromEntries([...identity.classes,...catalog.unresolved_external_classes].map(name=>[name,{action:blocked.has(name)?'blocked':'retain'}]));
 const policy={copy_inventory:{contract_version:1,catalog_sha256:identity.catalog_sha256,unmapped_copies:'blocked',bff_access_revocation:'block'},rules};
 assertPrivateRetentionPolicy(policy,identity);
 assert.throws(()=>assertPrivateRetentionPolicy({...policy,rules:{...rules,'private:burimunsi_native_lease_history':{action:'retain'}}},identity),{code:'privacy_retention_burimunsi_unmapped'});
});

test('known retry and payer receipt journals remain blocked in V1 inspection',async()=>{
 const prior=[...all,...burimunsiDetectionRelations,...burimunsiNativeAutoRelations,...burimunsiNativeFinancialRelations,...burimunsiNativeLeaseHistoryRelations];
 const retry='burimunsi_observation_retry_commands',payments='burimunsi_payment_sms_deliveries';
 for(const extra of [[...prior,payments],[...prior,retry,payments,'burimunsi_unknown']])
  await assert.rejects(privateRetentionCatalogIdentity(fixture({enabled:true,extra}).env),{code:'privacy_retention_unknown_private_class'});
 const f=fixture({enabled:true,extra:[...prior,retry,payments]});
 const result=await inventoryPrivateRetention(f.env,'synthetic-subject');
 for(const name of [retry,payments]){
  assert.deepEqual(result.classes['private:'+name],{status:'unmapped',count:null,sha256:null,rows:null,erasure:'blocked'});
  assert.equal(f.calls.some(call=>call.sql.includes('FROM private.'+name)),false);
 }
});


test('current V1 inspection and the additive V2 catalog agree on blocked BuriMunsi journals', async () => {
 const definitions=[
  [burimunsiBlockedJournals.observation_retry,'20261117134954_burimunsi_observation_processing_status.sql'],
  [burimunsiBlockedJournals.payment_sms,'20261118090305_burimunsi_automatic_payment_sms.sql'],
 ];
 for(const [journal,migration] of definitions){
  assert.equal(journal.disposition,'blocked');
  const sql=await readFile(new URL('../../../migrations/'+migration,import.meta.url),'utf8');
  const descriptor=sql.split('entry:=jsonb_build_object(')[1]?.split(');')[0];
  assert.ok(descriptor,'Expected a single additive journal descriptor');
  assert.ok(descriptor.includes("'name','private:"+journal.relation+"'"));
  assert.ok(descriptor.includes("'relation','private."+journal.relation+"'"));
  assert.ok(descriptor.includes("'scope','unmapped_private'"));
  assert.ok(descriptor.includes("'blocked',true"));
 }
});
