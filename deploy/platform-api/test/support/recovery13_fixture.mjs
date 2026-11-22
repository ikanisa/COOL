// Generated SYNTHETIC current13 recovery cohort: start with actual populated12
// test state, apply the exact0013 in one real D1 batch, then capture. No hosted
// source identity, real credentials, provider sends or policy approval is claimed.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {current12Fixture,captureD1,sha} from './recovery12_fixture.mjs';
import {quarantineSchemaProfiles} from '../../../../scripts/cloudflare/recovery_quarantine.mjs';
const projectRequire=createRequire(new URL('../../package.json',import.meta.url));
const rows=async(db,name)=>(await db.prepare('SELECT * FROM "'+name+'"').all()).results.map(v=>JSON.stringify(v)).sort();
export async function current13Fixture(t){
 const c=await current12Fixture(t),profile=quarantineSchemaProfiles.candidate13,name='migrations/0013_sms_receipt_metadata_read.sql',raw=await readFile(new URL('../../'+name,import.meta.url));
 assert.equal(sha(raw),profile.digests[name]);assert.equal((await c.f.db.prepare('SELECT count(*) AS n FROM admin_account_role_capabilities').first()).n,60);
 const preserved={};for(const r of(await c.f.db.prepare("SELECT name FROM sqlite_schema WHERE type='table' AND name NOT GLOB 'sqlite_*' AND name NOT IN('_cf_METADATA','_cf_KV','admin_account_role_capabilities','admin_grants') ORDER BY name").all()).results)preserved[r.name]=await rows(c.f.db,r.name);
 const schemaQuery="SELECT type,name,tbl_name,sql FROM sqlite_schema WHERE sql IS NOT NULL AND name NOT GLOB 'sqlite_*' AND name NOT IN('_cf_METADATA','_cf_KV') ORDER BY type,name",beforeSchema=(await c.f.db.prepare(schemaQuery).all()).results,beforeSequence=await rows(c.f.db,'sqlite_sequence');
 const beforeGrants=(await c.f.db.prepare('SELECT * FROM admin_grants ORDER BY user_id,permission').all()).results,{unstable_splitSqlQuery}=projectRequire(process.env.COLLECT_WRANGLER_MODULE??'wrangler');
 await c.f.db.batch(unstable_splitSqlQuery(raw.toString()).map(sql=>c.f.db.prepare(sql)));
 for(const [table,before]of Object.entries(preserved))assert.deepEqual(await rows(c.f.db,table),before,table);
 assert.equal((await c.f.db.prepare('SELECT count(*) AS n FROM admin_account_role_capabilities').first()).n,63);
 const afterGrants=(await c.f.db.prepare('SELECT * FROM admin_grants ORDER BY user_id,permission').all()).results,added=afterGrants.filter(g=>!beforeGrants.some(old=>JSON.stringify(old)===JSON.stringify(g)));
 assert.equal(afterGrants.length,beforeGrants.length+1);assert.deepEqual(added.map(g=>({user_id:g.user_id,permission:g.permission,granted_by:g.granted_by})),[{user_id:c.account.userId,permission:'sms.read',granted_by:'admin-account:'+c.account.adminId}]);
 assert.deepEqual(await rows(c.f.db,'sqlite_sequence'),beforeSequence);const afterSchema=(await c.f.db.prepare(schemaQuery).all()).results,addedSchema=afterSchema.filter(row=>!beforeSchema.some(old=>JSON.stringify(old)===JSON.stringify(row)));assert.ok(beforeSchema.every(row=>afterSchema.some(next=>JSON.stringify(row)===JSON.stringify(next))));assert.deepEqual(addedSchema,[{type:'index',name:'sms_receipts_metadata_order',tbl_name:'sms_receipts',sql:'CREATE INDEX sms_receipts_metadata_order ON sms_receipts(created_at DESC,id ASC)'}]);
 assert.deepEqual(afterGrants.filter(g=>g.permission!=='sms.read'),beforeGrants);const index=await c.f.db.prepare("SELECT sql FROM sqlite_schema WHERE type='index' AND name='sms_receipts_metadata_order'").first();assert.equal(index.sql,'CREATE INDEX sms_receipts_metadata_order ON sms_receipts(created_at DESC,id ASC)');
 const sql=await captureD1(c.f.db),payload=structuredClone(c.payload),config=JSON.parse(Buffer.from(payload.files['wrangler.json'].base64,'base64'));
 config.synthetic_fixture_provenance.kind='GENERATED synthetic current13 local Miniflare state after exact12-to13 D1 upgrade';const capturedAt=new Date().toISOString(),recoveryAt=new Date(Math.ceil(Date.now()/1000)*1000).toISOString();payload.captured_at=capturedAt;
 for(const [key,value]of Object.entries({'database.sql':sql,'wrangler.json':JSON.stringify(config),[name]:raw})){const bytes=Buffer.from(value);payload.files[key]={sha256:sha(bytes),bytes:bytes.length,base64:bytes.toString('base64')};}
 return {...c,sql,payload,capturedAt,recoveryAt,upgrade13:{migration_sha256:sha(raw),before_capability_definitions:60,after_capability_definitions:63,added_grants:added,preserved_application_tables:Object.keys(preserved).length,index_sql:index.sql,added_schema_objects:addedSchema,sqlite_sequence_unchanged:true,retention_task_count:c.counts.privacy_retention_tasks,actual_provider_source_database_id:null}};
}
