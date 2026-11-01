import test from 'node:test';
import assert from 'node:assert/strict';
import catalog from '../../../retention-inventory.json' with {type:'json'};
import {inventoryPrivateRetention,privateRetentionCatalogIdentity,privateRetentionGuards,assertPrivateRetentionPolicy,assertPrivateRetentionSource,privateCopyRetainable,sharedFenceRetentionClasses} from '../private-retention.js';
const HASH='a'.repeat(64),subject='synthetic-subject';
const smsFenceColumns='admission_id:uuid:true,profile_sha256:text:true,created_at:timestamp with time zone:true';
const currentProfile='archive_history_v4_guest_upgrade_deployment_manifests_v2_row_executor_v2_sms_fence';
const additivePrivateRelations=new Set(['collect_fence_working_admissions','collect_fence_admission_archive','collect_fence_admission_totals','member_history_versions','guest_upgrade_challenges','collect_deployment_identity','retention_inventory_manifests','retention_inventory_pages','retention_row_plans','retention_row_claims','retention_row_effects','retention_row_operations','collect_sms_fence_admissions']);
const originalFenceClasses=['private:collect_fence_admissions','private:collect_fence_control','private:collect_fence_operations','private:collect_fence_scheduler_lifecycle','private:collect_fence_source_upgrades','private:collect_fence_stopped_admissions'];
// SQL responses below are a strict selector/projection fixture only. Root must
// separately qualify real PG authority/DDL. No global fence rows are read here.
function fixture({profile='current25',missingFence=false,missingStopped=false,mapColumns=smsFenceColumns}={}){
 assert(['current25','stopped_admission14','admin_email11'].includes(profile));
 const calls=[];const schema=catalog.classes.filter(x=>x.relation.startsWith('private.')&&(!missingFence||x.scope!=='shared_fence')&&(!(missingStopped||profile==='admin_email11')||x.relation!=='private.collect_fence_stopped_admissions')&&(profile==='current25'||!additivePrivateRelations.has(x.relation.slice(8)))).map(x=>({name:x.relation.slice(8),kind:'r',columns:x.relation==='private.collect_sms_fence_admissions'?mapColumns:'fixture-only',constraints:'fixture-only',triggers:'fixture-only'})).sort((a,b)=>a.name.localeCompare(b.name));
 const realtime={contract_version:1,schema:{contract:'collect.member.realtime.inventory.v1',metadata_sha256:HASH,partitions_sha256:HASH},class:{status:'observed',count:0,rows:[],scope:'retained_member_topics_only',provider_logs_backups:'blocked',erasure_verified:false}};
 const managed={contract_version:1,schema:{fixture:'synthetic-managed-schema'},classes:{'managed:auth':{status:'observed',count:0,rows:[]},'managed:storage':{status:'observed',count:0,rows:[]}}};
 const DB={prepare(sql){const statement={sql,values:[],bind(...values){this.values=values;return this;},async first(key){const rows=(await this.all()).results;return key?rows[0]?.[key]:rows[0];},async all(){calls.push({sql,values:this.values});if(sql.includes("n.nspname='private'"))return{results:schema};if(sql.startsWith('SELECT private.retention_member_realtime_inventory'))return{results:[{inventory:realtime}]};if(sql.startsWith('SELECT private.retention_managed_inventory'))return{results:[{inventory:managed}]};if(sql.includes('pg_get_functiondef'))return{results:[{sha256:HASH}]};if(/FROM private\.collect_fence_/.test(sql))throw Error('Raw fence row access is forbidden');return{results:[]};}};return statement;}};
 DB.batch=async statements=>{const results=[];for(const statement of statements)results.push(await statement.all());return results;};
 return{env:{DB},calls};
}

test('original six fence classes and all current additive shared custody remain unmapped and blocked',async()=>{
 const f=fixture(),identity=await privateRetentionCatalogIdentity(f.env),inventory=await inventoryPrivateRetention(f.env,subject);const fence=sharedFenceRetentionClasses.filter(name=>catalog.classes.find(row=>row.name===name).scope==='shared_fence');assert.equal(identity.schema_profile,currentProfile);assert.equal(fence.length,19);assert.deepEqual(fence.slice().sort(),[...originalFenceClasses,...[...additivePrivateRelations].map(name=>'private:'+name)].sort());assert.equal(sharedFenceRetentionClasses.length,20);
 for(const name of sharedFenceRetentionClasses){assert.ok(identity.private_schema.some(row=>row.name===name.slice(8)));assert.deepEqual(inventory.classes[name],{status:'unmapped',count:0,sha256:inventory.classes[name].sha256,rows:[]});assert.match(inventory.classes[name].sha256,/^[a-f0-9]{64}$/);assert.equal(privateCopyRetainable(inventory,name),false);assert.ok(['shared_fence','shared_realtime'].includes(catalog.classes.find(row=>row.name===name).scope));}
 assert.equal(f.calls.some(call=>/FROM private\.collect_fence_/.test(call.sql)),false);assert.equal(inventory.external_copy_disposition,'blocked');
});

test('missing fence relations and predecessor catalog approvals fail closed; retain/erase cannot authorize shared fence disposition',async()=>{
 await assert.rejects(privateRetentionCatalogIdentity(fixture({missingFence:true}).env),{code:'privacy_retention_unknown_private_class'});const f=fixture(),identity=await privateRetentionCatalogIdentity(f.env);
 const rules=Object.fromEntries(identity.classes.map(name=>[name,{action:sharedFenceRetentionClasses.includes(name)||['managed:realtime_messages','private:admin_email_operations','private:admin_sensitive_email_proofs'].includes(name)?'blocked':'retain'}]));for(const name of catalog.unresolved_external_classes)rules[name]={action:'blocked'};const policy={copy_inventory:{contract_version:1,catalog_sha256:identity.catalog_sha256,unmapped_copies:'blocked',bff_access_revocation:'block'},rules};assertPrivateRetentionPolicy(policy,identity);
 assert.throws(()=>assertPrivateRetentionPolicy({...policy,copy_inventory:{...policy.copy_inventory,catalog_sha256:'b'.repeat(64)}},identity),{code:'privacy_retention_private_policy_unapproved'});
 for(const name of sharedFenceRetentionClasses)for(const action of ['retain','erase'])assert.throws(()=>assertPrivateRetentionPolicy({...policy,rules:{...rules,[name]:{action}}},identity),error=>['privacy_retention_shared_fence_unapproved','privacy_retention_private_disposition_unapproved'].includes(error.code));
});

test('explicit historical private profiles preserve SQL11/14 stopped-work attribution and refusal of crossed inventory',async()=>{
 const current=fixture({profile:'stopped_admission14'}),legacy=fixture({profile:'admin_email11'});
 const now=await privateRetentionCatalogIdentity(current.env),old=await privateRetentionCatalogIdentity(legacy.env);
 assert.equal(now.schema_profile,'stopped_admission14');assert.equal(old.schema_profile,'admin_email11');
 assert.notEqual(now.schema_sha256,old.schema_sha256);
 assert.equal(old.classes.includes('private:collect_fence_stopped_admissions'),true);
 const oldInventory=await inventoryPrivateRetention(legacy.env,subject),newInventory=await inventoryPrivateRetention(current.env,subject);
 for(const inventory of [oldInventory,newInventory]){
  assert.equal(inventory.classes['private:collect_fence_stopped_admissions'].status,'unmapped');
  assert.equal(privateCopyRetainable(inventory,'private:collect_fence_stopped_admissions'),false);
 }
 assert.throws(()=>assertPrivateRetentionSource(oldInventory,newInventory),{code:'privacy_retention_private_scope_changed'});
 assert.equal(legacy.calls.some(call=>/FROM private\.collect_fence_/.test(call.sql)),false);
});

test('current SMS custody requires its exact columns and the stopped-admission dependency',async()=>{
 await assert.rejects(privateRetentionCatalogIdentity(fixture({mapColumns:'fixture-only'}).env),{code:'privacy_retention_unknown_private_class'});
 await assert.rejects(privateRetentionCatalogIdentity(fixture({missingStopped:true}).env),{code:'privacy_retention_unknown_private_class'});
});

test('per-subject snapshots remain stable without inventing global row emptiness and never allow predecessor copy identity',async()=>{
 const f=fixture(),first=await inventoryPrivateRetention(f.env,subject),second=await inventoryPrivateRetention(f.env,subject);assert.deepEqual(first,second);assertPrivateRetentionSource(first,second);const old=structuredClone(first);delete old.classes[sharedFenceRetentionClasses[0]];assert.throws(()=>assertPrivateRetentionSource(old,second),{code:'privacy_retention_private_scope_changed'});assert.equal(first.unlinked_identifiers,'unverified');assert.equal(first.external_copy_disposition,'blocked');
});

test('private row guards retain exact schema and prior subject selectors without granting shared fence row reads/writes',async()=>{
 const f=fixture(),inventory=await inventoryPrivateRetention(f.env,subject),plan={id:'synthetic-plan',subject_id:subject},snapshot={summary:{private_inventory:inventory,objects:[]}};const statements=privateRetentionGuards(f.env,plan,snapshot,'synthetic-class');assert.ok(statements.some(statement=>statement.sql.includes("n.nspname='private'")));assert.ok(statements.some(statement=>statement.sql.includes('FROM private.auth_principal_links')));assert.equal(statements.some(statement=>/FROM private\.collect_fence_|(?:INSERT INTO|UPDATE|DELETE FROM) private\.collect_fence_/.test(statement.sql)),false);assert.ok(statements.some(statement=>statement.values.some(value=>Array.isArray(value)&&value.some(row=>row?.name==='collect_fence_admissions'))));
});


test('Realtime copies use the attributable managed helper and remain blocked; they are not shared unmapped absence',async()=>{const f=fixture(),identity=await privateRetentionCatalogIdentity(f.env),inventory=await inventoryPrivateRetention(f.env,subject);assert.equal(inventory.classes['managed:realtime_messages'].status,'observed');assert.equal(inventory.classes['managed:realtime_messages'].count,0);assert.ok(f.calls.some(c=>c.sql.startsWith('SELECT private.retention_member_realtime_inventory')&&c.values[0]===subject));const rules=Object.fromEntries(identity.classes.map(name=>[name,{action:sharedFenceRetentionClasses.includes(name)||['managed:realtime_messages','private:admin_email_operations','private:admin_sensitive_email_proofs'].includes(name)?'blocked':'retain'}]));for(const name of catalog.unresolved_external_classes)rules[name]={action:'blocked'};const policy={copy_inventory:{contract_version:1,catalog_sha256:identity.catalog_sha256,unmapped_copies:'blocked',bff_access_revocation:'block'},rules};assertPrivateRetentionPolicy(policy,identity);for(const action of ['retain','erase'])assert.throws(()=>assertPrivateRetentionPolicy({...policy,rules:{...rules,'managed:realtime_messages':{action}}},identity),{code:action==='retain'?'privacy_retention_realtime_unapproved':'privacy_retention_private_disposition_unapproved'});});
