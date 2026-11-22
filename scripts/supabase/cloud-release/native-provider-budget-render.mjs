// Renders a new forward migration; never edits or executes an applied one.
import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {resolve} from 'node:path';
const sha=x=>createHash('sha256').update(x).digest('hex');
const schedulerStatusPreimage='5dc44f65fb52562bc6a0391a7f7b7d050c333c2276f98097943d9c1e340d926d';
export async function renderNativeBudgetSchedulerStatus(){
 const source=await readFile(new URL('../../../supabase/migrations/20261022195747_collect_application_mutation_fence.sql',import.meta.url),'utf8');
 const original=source.match(/CREATE FUNCTION private\._collect_fence_scheduler_status\(\) RETURNS jsonb[\s\S]*?END;\$fn\$;/)?.[0];
 if(!original||sha(original.split('AS $fn$')[1].split('$fn$;')[0])!==schedulerStatusPreimage)throw Error('native_budget_scheduler_inventory_changed');
 if(original.split("('tick_jobs','')").length!==3||original.split('guard_count NOT IN(6,7)').length!==2)throw Error('native_budget_scheduler_inventory_shape_changed');
 const schedulerStatus=original.replace('CREATE FUNCTION ','CREATE OR REPLACE FUNCTION ')
  .replaceAll("('tick_jobs','')","('tick_jobs',''),('configure_native_provider_budget','25 25 25 1184')")
  .replace('guard_count NOT IN(6,7)','guard_count NOT IN(7,8)');
 const preflight=`DO $native_budget_scheduler_preimage$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure('private._collect_fence_scheduler_status()')
  AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')='${schedulerStatusPreimage}'
  AND p.prosecdef AND p.proowner='postgres'::regrole AND p.prokind='f' AND p.prorettype='jsonb'::regtype
  AND p.proconfig=ARRAY['search_path=pg_catalog, pg_temp'] AND p.proacl::text='{postgres=X/postgres}')
 THEN RAISE EXCEPTION 'native_budget_scheduler_inventory_preimage_changed';END IF;
END
$native_budget_scheduler_preimage$;`;
 return {original,schedulerStatus,preflight,schedulerStatusPreimage};
}
export async function renderNativeProviderBudget(){
 const original=await readFile(new URL('../../../supabase/migrations/20261117073850_collect_managed_jobs_hmac.sql',import.meta.url),'utf8');
 if(sha(original)!=='24429bfc2fc31cf44d44c4b3acbfc87cb946353edfac3cd2a4755c48c2d5aff7')throw Error('native_budget_applied_migration_changed');
 const start=original.indexOf('CREATE FUNCTION collect_ops.record_jobs_readiness('),end=original.indexOf('\nCREATE FUNCTION collect_ops.reconcile_jobs()',start);
 if(start<0||end<0)throw Error('native_budget_readiness_base_changed');
 let readiness=original.slice(start,end).replace('CREATE FUNCTION ','CREATE OR REPLACE FUNCTION ');
 const prior="OR (p_readiness->>'remaining_native_provider_requests')::bigint<10000";
 if(readiness.split(prior).length!==2)throw Error('native_budget_readiness_quota_changed');
 readiness=readiness.replace(prior,`OR (p_readiness->>'remaining_native_provider_requests')::bigint<2
   OR NOT EXISTS(SELECT 1 FROM collect_ops.jobs_config c WHERE c.singleton
    AND c.native_provider_source_sha256=admission->>'source_sha256' AND c.native_provider_model_id=admission->>'model_id'
    AND c.native_provider_approval_sha256=admission->>'approval_sha256' AND c.native_provider_expires_at>clock_timestamp()
    AND c.native_provider_limit-c.native_provider_used>=2
    AND (p_readiness->>'remaining_native_provider_requests')::bigint<=c.native_provider_limit-c.native_provider_used)`);
 const budget=await readFile(new URL('./native-provider-budget.sql',import.meta.url),'utf8');
 const inventory=await renderNativeBudgetSchedulerStatus();
 const sql='BEGIN;\n'+inventory.preflight+'\n'+budget+'\n'+readiness+'\n'+inventory.schedulerStatus+'\nCOMMIT;\n';
 return {sql,readiness,budget,...inventory,sqlSha256:sha(sql),baseSha256:sha(original)};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
 const result=await renderNativeProviderBudget();
 if(process.argv.length===4&&process.argv[2]==='--output')await writeFile(process.argv[3],result.sql,{flag:'wx',mode:0o600});
 else if(process.argv.length!==2)throw Error('usage_native_budget_render_output_new_file');
 console.log(JSON.stringify({sql_sha256:result.sqlSha256,base_sha256:result.baseSha256,mutatedCloud:false,providerLimit:400,latestExpiry:'2026-11-30T23:59:59Z'}));
}
