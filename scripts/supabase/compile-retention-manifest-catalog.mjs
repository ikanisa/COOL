// Offline, deterministic compilation of maintained, trusted retention selectors.
// This file does not connect to a database or accept SQL from an operator.
import {readFile,writeFile} from 'node:fs/promises';
import * as app from '../../supabase/functions/_shared/domain/privacy_retention_catalog.js';
import {privateRetentionSelection,privateRetentionExpressions} from '../../supabase/functions/_shared/private-retention.js';
const root=new URL('../../',import.meta.url);
const inventory=JSON.parse(await readFile(new URL('supabase/retention-inventory.json',root),'utf8'));
const columns={...app.retentionColumns,...app.momoPipelineRetentionColumns,...app.momoFinancialRetentionColumns,
 ...app.googleAuthRetentionColumns,...app.adminOtpRetentionColumns,...app.adminEmailRetentionColumns,
 ...app.diagnosticRetentionColumns,...app.notificationDeliveryRetentionColumns,...app.notificationChannelRetentionColumns};
const native=sql=>sql.replaceAll('?','$1');
const application=Object.fromEntries(Object.keys(columns).sort().map(name=>[name,{columns:columns[name],where:native(app.retentionSelection(name,'subject',columns).sql)}]));
const privateClasses=inventory.classes.filter(c=>c.relation.startsWith('private.')).map(entry=>{
 if(['shared_fence','shared_realtime'].includes(entry.scope))return {...entry,blocked:true};
 return {...entry,where:native(privateRetentionSelection(entry,'subject').where),...privateRetentionExpressions(entry)};
});
const gateway=await readFile(new URL('supabase/migrations/20261101012503_collect_sms_gateway.sql',root),'utf8');
const gatewayTables=[...gateway.matchAll(/CREATE TABLE (?:collect_sms\.)?([a-z0-9_]+)/g)].map(m=>m[1]).sort();
if(gatewayTables.length!==29)throw Error('Exact SMS gateway table catalog changed');
const catalog={contract:'collect.retention.descriptor-catalog.v2',application,engine_tables:app.engineTables,
 private_classes:privateClasses,copy_classes:app.copyClasses,gateway_tables:gatewayTables};
const catalogText=JSON.stringify(catalog,null,2)+'\n';
// SQL23 and SQL24 are retained qualification/release inputs. SQL25 adds an
// explicitly classified gateway ownership journal; refresh its catalog through
// an additive function replacement without rewriting either earlier migration.
const additivePrivate=new Set(['private:collect_sms_fence_admissions']);
const baseCatalog={...catalog,private_classes:privateClasses.filter(entry=>!additivePrivate.has(entry.name))};
const baseCatalogText=JSON.stringify(baseCatalog,null,2)+'\n';
const target=new URL('supabase/schema-src/retention-manifest-catalog.json',root);
const migration=new URL('supabase/migrations/20261101014231_collect_retention_inventory_manifests.sql',root);
// The migration was allocated by Supabase CLI. Never create a timestamp or an
// additional migration implicitly in this deterministic compilation step.
const oldMigration=await readFile(migration,'utf8');
const template=await readFile(new URL('supabase/schema-src/retention-inventory-manifests.sql',root),'utf8');
const functionSql='CREATE FUNCTION private._retention_manifest_catalog_v2() RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,pg_temp AS $function$\n SELECT $catalog$'+baseCatalogText+'$catalog$::jsonb\n$function$;';
const migrationText=template.replace('-- COMPILED_CATALOG_FUNCTION',()=>functionSql);
const additiveSql='-- Generated exact shared SMS admission classification; no erasure authority.\n'+functionSql.replace('CREATE FUNCTION','CREATE OR REPLACE FUNCTION').replace(baseCatalogText,catalogText)+'\n';
const additiveTarget=new URL('supabase/schema-src/sms-fence-retention-catalog.sql',root);
const additiveMigration=new URL('supabase/migrations/20261101030502_collect_sms_application_fence.sql',root);
const rowMigration=new URL('supabase/migrations/20261101020642_collect_retention_row_executor.sql',root);
const oldRowMigration=await readFile(rowMigration,'utf8');
const rowTemplate=await readFile(new URL('supabase/schema-src/retention-row-executor.sql',root),'utf8');
const rowExecution=await readFile(new URL('supabase/schema-src/retention-row-execution.sql',root),'utf8');
const rowMigrationText=rowTemplate.replace('-- EXECUTION_FUNCTIONS',()=>rowExecution);
if(oldMigration!==migrationText||oldRowMigration!==rowMigrationText)throw Error('Retained retention migrations differ from their reviewed compiled sources');
if(process.argv.slice(2).includes('--check')){
 if(await readFile(target,'utf8')!==catalogText||await readFile(additiveTarget,'utf8')!==additiveSql||!(await readFile(additiveMigration,'utf8')).includes(additiveSql))throw Error('Retention additive catalog is stale');
}else{await writeFile(target,catalogText);await writeFile(additiveTarget,additiveSql);}
console.log(JSON.stringify({application_tables:Object.keys(application).length,private_classes:privateClasses.length,gateway_tables:gatewayTables.length,compiled:true}));
