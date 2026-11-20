// Compiles a reviewable managed-cloud candidate from the exact retained source.
// It performs no connection, migration-history write, or production dispatch.
import {createHash} from 'node:crypto';
const SOURCE_SHA='8f9be631ba0a6a2d9ecda7c5cac8bb79884fde2a605fd71507b9d636124d8663';
const CLOUD_SHAPE='27b92cac21dab5b92f0f389a9635adeaddbd4952868fa6d9285f18205533e333';
const PROJECT='rrlduytparvsjfmegalh',HASH=/^[a-f0-9]{64}$/;
const sha=x=>createHash('sha256').update(x).digest('hex');
const fail=code=>{throw Error(code);};
function once(source,oldValue,newValue){if(source.split(oldValue).length!==2)fail('candidate_preimage_changed');return source.replace(oldValue,()=>newValue);}
export function compileManagedLifecycleCandidate(source,{profileSha,sourceSha,historySha,historyCount,storageShapeSha}={}){
 if(!Buffer.isBuffer(source)||sha(source)!==SOURCE_SHA||![profileSha,sourceSha,historySha].every(x=>HASH.test(x??''))||
  storageShapeSha!==CLOUD_SHAPE||!Number.isSafeInteger(historyCount)||historyCount<16||historyCount>1000)fail('candidate_input_refused');
 let sql=source.toString('utf8');
 const replacements=[
  ['18f9b92d996651911d57693b7ba7e3c1c782c85cf17142983f2061ea592de5c1',profileSha],
  ['9559229f34e297bbc7ad7c379a27e2a81fd4f419b4bfbce8926c290730c3067c',sourceSha],
  ['24610061c44731ecaec5d748c4bace03ad6388ebce30c462602079abf8667e12',historySha],
  ['967a55245c51a1fee2dcaa65d1598fde05d60a0cc7f6f5b0eb9287c556f3f89e',storageShapeSha],
  ['d52ac01bf7b93c13358eacf5d12c3effa6a5ac2baedd6941eed937bee3e69c14','280322e19785ab89b91595a62111f6561f82fcd6cd0673ef0f648b6cb135695d'],
  ['d9364415fdc44d1052619b7e916f6949b0c53ab0e6c344b67b0eee62af4f0adc','0bf0ae01fff8b85b9722530b6ea35fd3b359f9f7df1bed3920d7cd6b2e4ce04e']];
 for(const [oldValue,newValue] of replacements)sql=once(sql,oldValue,newValue);
 const locks="SET LOCAL statement_timeout = '60s';\n";
 sql=once(sql,locks,locks+"SELECT pg_advisory_xact_lock(7346371,11);\nLOCK TABLE supabase_migrations.schema_migrations IN SHARE MODE;\nSELECT pg_advisory_xact_lock(7346371,1);\nSELECT pg_advisory_xact_lock(7346371,2);\n");
 const profile='  PERFORM private.collect_assert_deployment(expected_profile);\n';
 sql=once(sql,profile,profile+`  IF NOT EXISTS (SELECT 1 FROM private.collect_deployment_identity
    WHERE singleton AND profile_sha256=expected_profile AND profile_raw::jsonb->>'mode'='managed'
      AND profile_raw::jsonb->>'environment'='production'
      AND profile_raw::jsonb->>'supabase_origin'='https://${PROJECT}.supabase.co') THEN
    RAISE EXCEPTION 'managed_lifecycle_profile_mismatch' USING ERRCODE='55000';
  END IF;\n`);
 sql=once(sql,"WHERE singleton AND mode = 'fenced' AND source_sha256 = expected_source",
  `WHERE singleton AND mode = 'fenced' AND source_sha256 = expected_source AND project_ref = '${PROJECT}'`);
 const oldHistory=`  SELECT count(*), encode(sha256(convert_to(
    string_agg(version || ':' || source_sha256 || ':' || profile_sha256, E'\\n' ORDER BY version COLLATE "C"),
    'UTF8')), 'hex')
  INTO receipt_count, prefix_digest
  FROM supabase_migrations.collect_installation_steps;
  IF receipt_count <> 61 OR prefix_digest IS DISTINCT FROM expected_app_prefix THEN`;
 const newHistory=`  SELECT count(*), encode(sha256(convert_to(
    string_agg(version || ':' || coalesce(name,'') || ':' || encode(sha256(convert_to(statements[1],'UTF8')),'hex'), E'\\n' ORDER BY version COLLATE "C"),
    'UTF8')), 'hex')
  INTO receipt_count, prefix_digest
  FROM supabase_migrations.schema_migrations;
  IF receipt_count <> ${historyCount} OR prefix_digest IS DISTINCT FROM expected_app_prefix
    OR EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version IS NULL OR name IS NULL OR cardinality(statements) IS DISTINCT FROM 1 OR statements[1] IS NULL) THEN`;
 sql=once(sql,oldHistory,newHistory);
 if(sql.includes('collect_installation_steps'))fail('candidate_local_history_reference');
 return Object.freeze({sql,sha256:sha(sql),sourceSha256:SOURCE_SHA,storageShapeSha256:CLOUD_SHAPE,historyCount,productionDispatched:false});
}
