// Render a forward-only provider-policy migration. Applied history is immutable.
import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {resolve} from 'node:path';
import {renderNativeProviderBudget} from './native-provider-budget-render.mjs';

const sha=value=>createHash('sha256').update(value).digest('hex');
function once(text,before,after){
 const i=text.indexOf(before);if(i<0||text.indexOf(before,i+before.length)>=0)throw Error('native_provider_policy_source_changed');
 return text.slice(0,i)+after+text.slice(i+before.length);
}
export async function renderNativeProviderPolicy(){
 const prior=await renderNativeProviderBudget();
 const functionBlock=(name,delimiter)=>{
  const prefix='CREATE FUNCTION '+name+'(',start=prior.budget.indexOf(prefix),end=prior.budget.indexOf(delimiter+';',start);
  if(start<0||end<0)throw Error('native_provider_policy_source_changed');
  return prior.budget.slice(start,end+delimiter.length+1).replace('CREATE FUNCTION ','CREATE OR REPLACE FUNCTION ');
 };
 let setup=functionBlock('collect_ops.configure_native_provider_budget','$budget_setup$');
 let reserve=functionBlock('private.collect_native_provider_reserve','$budget_reserve$');
 let readiness=prior.readiness;
 setup=once(setup,"OR p_model IS DISTINCT FROM 'gpt-5.4-mini-2026-03-17' OR NOT coalesce(p_approval ~ '^[a-f0-9]{64}$',false)\n  OR p_expires IS NULL OR p_expires<=clock_timestamp() OR p_expires>'2026-11-30 23:59:59+00'::timestamptz",
  "OR NOT coalesce(p_model ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$',false) OR NOT coalesce(p_approval ~ '^[a-f0-9]{64}$',false)\n  OR (p_expires IS NOT NULL AND p_expires<=clock_timestamp())");
 reserve=once(reserve,"OR c.native_provider_approval_sha256 IS DISTINCT FROM p_approval OR c.native_provider_expires_at IS NULL\n  OR c.native_provider_expires_at<=clock_timestamp() OR c.native_provider_used>=c.native_provider_limit THEN RETURN false;END IF;",
  "OR c.native_provider_approval_sha256 IS DISTINCT FROM p_approval\n  OR (c.native_provider_expires_at IS NOT NULL AND c.native_provider_expires_at<=clock_timestamp())\n  OR (c.native_provider_limit IS NOT NULL AND c.native_provider_used>=c.native_provider_limit) THEN RETURN false;END IF;");
 reserve=once(reserve,"WHERE singleton AND native_provider_expires_at>clock_timestamp() AND native_provider_used<native_provider_limit;",
  "WHERE singleton AND native_provider_used<9007199254740991\n   AND (native_provider_expires_at IS NULL OR native_provider_expires_at>clock_timestamp())\n   AND (native_provider_limit IS NULL OR native_provider_used<native_provider_limit);");
 readiness=once(readiness,"OR (p_readiness->>'remaining_invocations')::bigint<10000", "OR (p_readiness->>'remaining_invocations')::bigint<50000");
 readiness=once(readiness,`OR jsonb_typeof(p_readiness->'remaining_native_provider_requests') IS DISTINCT FROM 'number'
   OR NOT coalesce(p_readiness->>'remaining_native_provider_requests' ~ '^[0-9]{1,9}$',false) OR (p_readiness->>'remaining_native_provider_requests')::bigint<2
   OR NOT EXISTS(SELECT 1 FROM collect_ops.jobs_config c WHERE c.singleton
    AND c.native_provider_source_sha256=admission->>'source_sha256' AND c.native_provider_model_id=admission->>'model_id'
    AND c.native_provider_approval_sha256=admission->>'approval_sha256' AND c.native_provider_expires_at>clock_timestamp()
    AND c.native_provider_limit-c.native_provider_used>=2
    AND (p_readiness->>'remaining_native_provider_requests')::bigint<=c.native_provider_limit-c.native_provider_used)`,
  `OR NOT EXISTS(SELECT 1 FROM collect_ops.jobs_config c WHERE c.singleton
    AND c.native_provider_source_sha256=admission->>'source_sha256' AND c.native_provider_model_id=admission->>'model_id'
    AND c.native_provider_approval_sha256=admission->>'approval_sha256'
    AND (c.native_provider_expires_at IS NULL OR c.native_provider_expires_at>clock_timestamp())
    AND CASE WHEN c.native_provider_limit IS NULL THEN p_readiness->'remaining_native_provider_requests'='null'::jsonb
     WHEN jsonb_typeof(p_readiness->'remaining_native_provider_requests')='number'
      AND coalesce(p_readiness->>'remaining_native_provider_requests' ~ '^[0-9]{1,16}$',false)
     THEN (p_readiness->>'remaining_native_provider_requests')::bigint BETWEEN 2 AND c.native_provider_limit-c.native_provider_used
     ELSE false END)`);
 const preflight=`DO $provider_policy_preflight$
DECLARE item record;p pg_proc%ROWTYPE;
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced')
  OR NOT EXISTS(SELECT 1 FROM collect_ops.jobs_config c JOIN cron.job j ON j.jobid=c.cron_job_id WHERE c.singleton AND NOT c.enabled AND NOT j.active)
  OR EXISTS(SELECT 1 FROM collect_ops.jobs_dispatches WHERE state IN('awaiting','unconfirmed'))
  OR NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='collect_ops.jobs_config'::regclass AND conname='native_provider_budget_binding')
 THEN RAISE EXCEPTION 'native_provider_policy_precondition';END IF;
 FOR item IN SELECT * FROM (VALUES
  ('collect_ops.record_jobs_readiness(jsonb)','64fd5a1cc2c3a96a86f8819f100c0d828238b3098389ee7cfee898753f02b8fd',false,'{postgres=X/postgres}'),
  ('collect_ops.configure_native_provider_budget(text,text,text,timestamp with time zone)','5cb722b0d11c52d626fe1462dbec4bbd17c9288640357ed5ccb201287b71f7b2',false,'{postgres=X/postgres}'),
  ('private.collect_native_provider_reserve(uuid,text,text,text)','7bf0e8e2412617ff3887f0998aeadc5657946a9807a1c5a93835838822889e59',true,'{postgres=X/postgres,collect_runtime=X/postgres}')
 ) AS x(signature,digest,security_definer,acl) LOOP
  SELECT * INTO p FROM pg_proc WHERE oid=to_regprocedure(item.signature);
  IF NOT FOUND OR pg_get_userbyid(p.proowner)<>'postgres' OR p.prosecdef IS DISTINCT FROM item.security_definer OR p.proacl::text IS DISTINCT FROM item.acl
   OR encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') IS DISTINCT FROM item.digest THEN
   RAISE EXCEPTION 'native_provider_policy_preimage_changed: %',item.signature;END IF;
 END LOOP;
END
$provider_policy_preflight$;`;
 const changes=`ALTER TABLE collect_ops.jobs_config
 DROP CONSTRAINT jobs_config_native_provider_limit_check,
 DROP CONSTRAINT jobs_config_native_provider_used_check,
 DROP CONSTRAINT native_provider_budget_binding,
 ALTER COLUMN native_provider_limit DROP NOT NULL,
 ALTER COLUMN native_provider_limit DROP DEFAULT,
 ALTER COLUMN native_provider_limit TYPE bigint,
 ALTER COLUMN native_provider_used TYPE bigint;
 UPDATE collect_ops.jobs_config SET native_provider_limit=NULL,native_provider_expires_at=NULL WHERE singleton;
 ALTER TABLE collect_ops.jobs_config
 ADD CONSTRAINT native_provider_budget_bounds CHECK(native_provider_used BETWEEN 0 AND 9007199254740991
  AND (native_provider_limit IS NULL OR (native_provider_limit>=native_provider_used AND native_provider_limit<=9007199254740991))),
 ADD CONSTRAINT native_provider_budget_binding CHECK(
  (native_provider_source_sha256 IS NULL AND native_provider_model_id IS NULL AND native_provider_approval_sha256 IS NULL AND native_provider_expires_at IS NULL AND native_provider_used=0)
  OR (native_provider_source_sha256 IS NOT NULL AND native_provider_source_sha256 ~ '^[a-f0-9]{64}$'
   AND native_provider_model_id IS NOT NULL AND native_provider_model_id ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$'
   AND native_provider_approval_sha256 IS NOT NULL AND native_provider_approval_sha256 ~ '^[a-f0-9]{64}$'));`;
 const sql='BEGIN;\n'+preflight+'\n'+changes+'\n'+setup+'\n'+reserve+'\n'+readiness+'\nCOMMIT;\n';
 return {sql,setup,reserve,readiness,sqlSha256:sha(sql),priorMigrationSha256:prior.sqlSha256};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
 const r=await renderNativeProviderPolicy();
 if(process.argv.length===4&&process.argv[2]==='--output')await writeFile(process.argv[3],r.sql,{flag:'wx',mode:0o600});
 else if(process.argv.length!==2)throw Error('usage_native_provider_policy_render_output_new_file');
 console.log(JSON.stringify({sqlSha256:r.sqlSha256,priorMigrationSha256:r.priorMigrationSha256,remoteMutated:false}));
}
