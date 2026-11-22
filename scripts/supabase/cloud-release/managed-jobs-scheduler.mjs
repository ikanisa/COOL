// Renders an INACTIVE, cloud-only scheduler from the exact qualified original.
// This module does not connect, rotate keys, install, probe, or activate it.
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {resolve} from 'node:path';
import {loadConfig,stable} from '../jobs_config.mjs';

const BASE='85c9128bf7f4f4d91eafe24710e8ae91f9a621fc817eb8443561b06c83d1f2f0';
const PROJECT='rrlduytparvsjfmegalh';
const sha=x=>createHash('sha256').update(x).digest('hex');
function replaceOnce(text,from,to){
 const i=text.indexOf(from);if(i<0||text.indexOf(from,i+from.length)>=0)throw Error('scheduler_candidate_source_drift');
 return text.slice(0,i)+to+text.slice(i+from.length);
}
export async function renderManagedScheduler(){
 let sql=await readFile(new URL('../../../supabase/jobs/bootstrap.sql',import.meta.url),'utf8');
 if(sha(sql)!==BASE)throw Error('scheduler_candidate_base_changed');
 const claim=await readFile(new URL('./managed-jobs-dispatch-claim.sql',import.meta.url),'utf8');
 const retention=await readFile(new URL('./managed-jobs-retention.sql',import.meta.url),'utf8');
 const c=await loadConfig();
 c.format='collect.jobs.scheduler.cloud-hmac.v1';
 c.authorization={header:'Authorization',scheme:'Bearer',vault_secret_name:'collect_job_signing_key_v1',mode:'supabase_dispatch_hmac_v1'};
 c.qualification='Inactive installation; native SMS requires the separate source/model/approval admission.';
 sql=replaceOnce(sql,'CREATE SCHEMA collect_ops;',`DO $existing$ BEGIN
  IF to_regnamespace('collect_ops') IS NULL OR (SELECT nspowner::regrole::text FROM pg_namespace WHERE nspname='collect_ops')<>'postgres'
   OR (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='collect_ops')<>0
   OR (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='collect_ops')<>1
   OR NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure('collect_ops.cleanup_google_expired()') AND p.proowner::regrole::text='postgres'
    AND encode(sha256(convert_to(pg_get_functiondef(p.oid),'UTF8')),'hex')='f70925051147096cfb72869b401fdb69c976b68034c87e8c3e98ee8b5f350ed0'
    AND p.proacl::text='{postgres=X/postgres}') THEN RAISE EXCEPTION 'unexpected_existing_collect_ops';END IF;
 END $existing$;`);
 sql=replaceOnce(sql," notification_contract jsonb CHECK(notification_contract IS NULL OR jsonb_typeof(notification_contract)='object'),",
  " notification_contract jsonb CHECK(notification_contract IS NULL OR jsonb_typeof(notification_contract)='object'),\n native_contract jsonb CHECK(native_contract IS NULL OR jsonb_typeof(native_contract)='object'),");
 sql=replaceOnce(sql,'CREATE INDEX jobs_dispatches_pending',claim+'\nCREATE INDEX jobs_dispatches_pending');
 sql=replaceOnce(sql,'DECLARE k text;processing boolean;notifications boolean;expected_keys text[];admission jsonb;',
  'DECLARE k text;processing boolean;notifications boolean;native_sms boolean;expected_keys text[];admission jsonb;');
 sql=replaceOnce(sql," notifications:=p_readiness->>'format'='collect.jobs.readiness.v3';",
  " native_sms:=p_readiness?'native_sms_admission';\n notifications:=p_readiness->>'format'='collect.jobs.readiness.v3';");
 sql=replaceOnce(sql," IF processing OR notifications THEN expected_keys:=expected_keys||ARRAY['mode'];END IF;",
  " IF native_sms THEN expected_keys:=expected_keys||ARRAY['native_sms_admission','native_provider_evidence_sha256','native_guard_evidence_sha256','remaining_native_provider_requests'];END IF;\n IF processing OR notifications THEN expected_keys:=expected_keys||ARRAY['mode'];END IF;");
 sql=replaceOnce(sql,"||CASE WHEN notifications THEN ARRAY['notification_provider_evidence_sha256'] ELSE ARRAY[]::text[] END) LOOP",
  "||CASE WHEN notifications THEN ARRAY['notification_provider_evidence_sha256'] ELSE ARRAY[]::text[] END||CASE WHEN native_sms THEN ARRAY['native_provider_evidence_sha256','native_guard_evidence_sha256'] ELSE ARRAY[]::text[] END) LOOP");
 sql=replaceOnce(sql,' IF processing THEN\n  admission:=p_readiness->\'processing_admission\';',` IF native_sms THEN
  admission:=p_readiness->'native_sms_admission';
  IF jsonb_typeof(admission) IS DISTINCT FROM 'object'
   OR (SELECT count(*) FROM jsonb_object_keys(admission))<>5 OR EXISTS(SELECT 1 FROM jsonb_object_keys(admission) key WHERE key NOT IN('contract','source_sha256','approval_sha256','model_id','batch_limit'))
   OR admission->>'contract' IS DISTINCT FROM 'collect.native-sms-automation.v1' OR admission->'batch_limit' IS DISTINCT FROM '1'::jsonb
   OR NOT coalesce(admission->>'source_sha256' ~ '^[a-f0-9]{64}$',false) OR admission->>'source_sha256' IS DISTINCT FROM private.collect_fence_owner_status()->>'sourceSha256'
   OR NOT coalesce(admission->>'approval_sha256' ~ '^[a-f0-9]{64}$',false) OR NOT coalesce(admission->>'model_id' ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$',false)
   OR jsonb_typeof(p_readiness->'remaining_native_provider_requests') IS DISTINCT FROM 'number'
   OR NOT coalesce(p_readiness->>'remaining_native_provider_requests' ~ '^[0-9]{1,9}$',false) OR (p_readiness->>'remaining_native_provider_requests')::bigint<10000
  THEN RAISE EXCEPTION 'reviewed_native_source_model_guard_and_quota_required';END IF;
 END IF;
 IF processing THEN
  admission:=p_readiness->'processing_admission';`);
 sql=replaceOnce(sql,'processing_ok boolean;notifications_ok boolean;native_epoch_now text;',
  'processing_ok boolean;notifications_ok boolean;native_ok boolean;native_epoch_now text;');
 sql=replaceOnce(sql,"   IF r.status_code=200 AND NOT coalesce(r.timed_out,true)",`   native_ok:=false;
   IF d.native_contract IS NULL THEN
    native_ok:=NOT coalesce(payload?'native_sms_admission',false) AND NOT coalesce(payload?'native_auto_processing',false) AND NOT coalesce(payload?'native_sms_ledger',false);
   ELSIF payload->'native_sms_admission'=d.native_contract AND payload->'native_auto_processing'->>'status'='complete'
    AND payload->'native_sms_ledger'->>'status'='complete' AND payload->'native_auto_processing'->'processed' IN('0'::jsonb,'1'::jsonb)
    AND payload->'native_sms_ledger'->'processed' IN('0'::jsonb,'1'::jsonb)
    AND jsonb_typeof(payload->'native_auto_processing'->'results')='array' AND jsonb_typeof(payload->'native_sms_ledger'->'results')='array' THEN
    native_ok:=to_jsonb(jsonb_array_length(payload->'native_auto_processing'->'results'))=payload->'native_auto_processing'->'processed'
     AND to_jsonb(jsonb_array_length(payload->'native_sms_ledger'->'results'))=payload->'native_sms_ledger'->'processed'
     AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(payload->'native_auto_processing'->'results') item WHERE
      ((item->>'state'='completed' AND item->>'relation' IN('accepted','duplicate','conflict') AND item=jsonb_build_object('state',item->>'state','relation',item->>'relation'))
       OR (item->>'state' IN('security_message','not_claimed','retry') AND item=jsonb_build_object('state',item->>'state'))) IS NOT TRUE)
     AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(payload->'native_sms_ledger'->'results') item WHERE
      (item->>'state' IN('posted','unmatched','already_posted','not_financial') AND item=jsonb_build_object('state',item->>'state')) IS NOT TRUE);
   END IF;
   IF r.status_code=200 AND NOT coalesce(r.timed_out,true)`);
 sql=replaceOnce(sql,'AND purged BETWEEN 0 AND 100 AND coalesce(processing_ok,false) AND coalesce(notifications_ok,false) THEN',
  `AND purged BETWEEN 0 AND 100 AND coalesce(processing_ok,false) AND coalesce(notifications_ok,false) AND coalesce(native_ok,false)
    AND EXISTS(SELECT 1 FROM private.collect_managed_job_tickets t WHERE t.dispatch_id=d.id AND t.source_sha256=private.collect_fence_owner_status()->>'sourceSha256'
     AND t.completed_at IS NOT NULL AND t.response_sha256=encode(sha256(convert_to(r.content,'UTF8')),'hex')) THEN`);
 sql=replaceOnce(sql,'NOT coalesce(processing_ok,false) OR NOT coalesce(notifications_ok,false)) THEN',
  'NOT coalesce(processing_ok,false) OR NOT coalesce(notifications_ok,false) OR NOT coalesce(native_ok,false)) THEN');
 sql=replaceOnce(sql,'selected_notification jsonb;request_body jsonb;',
  'selected_notification jsonb;selected_native jsonb;request_body jsonb;');
 sql=replaceOnce(sql," selected_notification:=c.readiness->'notification_admission';",
  " selected_notification:=c.readiness->'notification_admission';\n selected_native:=c.readiness->'native_sms_admission';\n IF selected_native IS NOT NULL AND selected_native->>'source_sha256' IS DISTINCT FROM private.collect_fence_owner_status()->>'sourceSha256' THEN PERFORM collect_ops.pause_jobs();RETURN jsonb_build_object('state','native_source_requires_review');END IF;");
 const oldAcl=" IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname IN('anon','authenticated','service_role','collect_runtime','collect_importer') AND (has_schema_privilege(rolname,'vault','USAGE') OR has_schema_privilege(rolname,'net','USAGE') OR has_table_privilege(rolname,'net.http_request_queue','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') OR has_table_privilege(rolname,'net._http_response','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'))) THEN PERFORM collect_ops.pause_jobs();RETURN jsonb_build_object('state','credential_dependency_acl_changed');END IF;";
 sql=replaceOnce(sql,oldAcl," IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname IN('anon','authenticated','collect_runtime','collect_importer') AND has_schema_privilege(rolname,'vault','USAGE') AND has_table_privilege(rolname,'vault.decrypted_secrets','SELECT')) THEN PERFORM collect_ops.pause_jobs();RETURN jsonb_build_object('state','signing_key_acl_changed');END IF;");
 sql=replaceOnce(sql," IF credential IS NULL OR length(credential)<32 OR length(credential)>4096 OR credential ~ '[[:space:]]' THEN",
  " IF (SELECT count(*) FROM vault.decrypted_secrets WHERE name=c.vault_name)<>1 OR credential IS NULL OR credential !~ '^[a-f0-9]{64}$' THEN");
 sql=replaceOnce(sql,"p.runtime_contract IS NOT DISTINCT FROM selected_contract AND p.notification_contract IS NOT DISTINCT FROM selected_notification)",
  "p.runtime_contract IS NOT DISTINCT FROM selected_contract AND p.notification_contract IS NOT DISTINCT FROM selected_notification AND p.native_contract IS NOT DISTINCT FROM selected_native)");
 sql=replaceOnce(sql,"vault_updated_at,runtime_contract,notification_contract) VALUES(p_dispatch_id,p_kind,slot_at,'awaiting',native_epoch_now,c.readiness->>'evidence_file_sha256',secret_id,secret_updated_at,selected_contract,selected_notification);",
  "vault_updated_at,runtime_contract,notification_contract,native_contract) VALUES(p_dispatch_id,p_kind,slot_at,'awaiting',native_epoch_now,c.readiness->>'evidence_file_sha256',secret_id,secret_updated_at,selected_contract,selected_notification,selected_native);");
 sql=replaceOnce(sql,"  -- Never inline or return the credential. pg_net's restricted unlogged queue\n  -- necessarily holds the live header until dispatch; it is NOT durable proof.\n",'');
 sql=replaceOnce(sql,"  IF selected_notification IS NOT NULL THEN request_body:=request_body||jsonb_build_object('notification_admission',selected_notification);END IF;\n  request_id:=net.http_post(url:=c.endpoint,headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||credential),body:=request_body,timeout_milliseconds:=120000);",
 `  IF selected_notification IS NOT NULL THEN request_body:=request_body||jsonb_build_object('notification_admission',selected_notification);END IF;
  IF selected_native IS NOT NULL THEN request_body:=request_body||jsonb_build_object('native_sms_admission',selected_native);END IF;
  request_body:=request_body||jsonb_build_object('dispatch_expires_at',floor(extract(epoch FROM statement_timestamp()))::bigint+180);
  INSERT INTO private.collect_managed_job_tickets(dispatch_id,source_sha256,payload,expires_at)
   VALUES(p_dispatch_id,private.collect_fence_owner_status()->>'sourceSha256',request_body,to_timestamp((request_body->>'dispatch_expires_at')::bigint));
  request_id:=net.http_post(url:=c.endpoint,headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||encode(extensions.hmac(convert_to('collect.jobs.dispatch.v1'||E'\\n'||'__PROJECT_REF__'||E'\\n'||(private.collect_fence_owner_status()->>'sourceSha256')||E'\\n'||p_dispatch_id::text||E'\\n'||(request_body->>'dispatch_expires_at'),'UTF8'),convert_to(credential,'UTF8'),'sha256'),'hex')),body:=request_body,timeout_milliseconds:=120000);`);
 sql=replaceOnce(sql,"notification_contract IS NOT DISTINCT FROM c.readiness->'notification_admission' AND native_epoch=collect_ops.native_jobs_epoch()",
  "notification_contract IS NOT DISTINCT FROM c.readiness->'notification_admission' AND native_contract IS NOT DISTINCT FROM c.readiness->'native_sms_admission' AND native_epoch=collect_ops.native_jobs_epoch()");
 sql=replaceOnce(sql," OR (c.readiness->'notification_admission' IS NOT NULL AND c.readiness->'notification_admission'->>'source_sha256' IS DISTINCT FROM private.collect_fence_owner_status()->>'sourceSha256')",
  " OR (c.readiness->'notification_admission' IS NOT NULL AND c.readiness->'notification_admission'->>'source_sha256' IS DISTINCT FROM private.collect_fence_owner_status()->>'sourceSha256')\n OR (c.readiness->'native_sms_admission' IS NOT NULL AND c.readiness->'native_sms_admission'->>'source_sha256' IS DISTINCT FROM private.collect_fence_owner_status()->>'sourceSha256')");
 sql=replaceOnce(sql,'COMMIT;\n',retention+'\nCOMMIT;\n');
 const configSha=sha(stable(c)),templateSha=sha(sql);
 sql=sql.replaceAll('__TEMPLATE_SHA256__',templateSha).replaceAll('__CONFIG_SHA256__',configSha).replaceAll('__PROJECT_REF__',PROJECT)
  .replaceAll('__ENDPOINT__',c.endpoint).replaceAll('__VAULT_NAME__',c.authorization.vault_secret_name).replaceAll('__JOB_NAME__',c.cron.name).replaceAll('__SCHEDULE__',c.cron.expression);
 if(/__[A-Z0-9_]+__/.test(sql))throw Error('unresolved_scheduler_template_token');
 return {sql,sqlSha:sha(sql),templateSha,configSha,config:c};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
 try{const r=await renderManagedScheduler();console.log(JSON.stringify({project:PROJECT,active:false,sql_sha256:r.sqlSha,template_sha256:r.templateSha,config_sha256:r.configSha,mutated:false}));}
 catch(e){console.error(e.message);process.exitCode=1;}
}
