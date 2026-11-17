import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const modulePath=process.env.COLLECT_CLOUD_TEST_PGLITE_MODULE;
const sql=readFileSync(new URL('../../../supabase/migrations/20261117220000_burimunsi_held_resume_guard.sql',import.meta.url),'utf8');
function extract(name){
 const start=sql.indexOf(`CREATE FUNCTION private.${name}(`),open=sql.indexOf('$fn$',start),end=sql.indexOf('$fn$;',open+4);
 assert(start>=0&&open>=0&&end>=0);return sql.slice(start,end+5).replaceAll('private.','pg_temp.')
  .replaceAll('734636924058501::bigint','9223372036854773001::bigint');
}
test('held exact-request guard permits one durable attempt and validates current consent',{skip:!modulePath},async()=>{
 const {PGlite}=await import(modulePath),db=new PGlite();
 try{
  await db.exec(`CREATE TEMP TABLE storage_put_intents(operation_id text PRIMARY KEY,object_key text,state text,
   attempts integer,active_attempt uuid,upload_unresolved boolean,delete_tombstone boolean);
   CREATE TEMP TABLE storage_upload_attempts(id uuid PRIMARY KEY,operation_id text);
   CREATE TEMP TABLE burimunsi_recovered_sms_holds(source_id text,object_key text);
   CREATE TEMP TABLE burimunsi_observation_requests(source_id text,initial_consent_generation bigint);
   CREATE FUNCTION pg_temp.collect_fence_assert_write(uuid,bigint,text) RETURNS void LANGUAGE plpgsql AS $$BEGIN RETURN;END$$;
   CREATE FUNCTION pg_temp.burimunsi_observation_consent_current() RETURNS jsonb LANGUAGE sql AS $$
    SELECT jsonb_build_object('enabled',current_setting('fixture.consent',true)='yes',
     'generation',coalesce(nullif(current_setting('fixture.generation',true),''),'1')::bigint)$$;
   CREATE FUNCTION pg_temp.burimunsi_sms_recovery_hold(text,uuid,text,text,timestamptz) RETURNS boolean LANGUAGE plpgsql AS $$
    BEGIN IF current_setting('fixture.authorized',true) IS DISTINCT FROM 'yes' OR $1<>'source-1'
      OR $2<>'00000000-0000-4000-8000-000000000001'::uuid OR $3<>repeat('a',64)
      OR $4<>repeat('b',64) OR $5<>'2026-11-11 12:00:00+00'::timestamptz THEN
      RAISE EXCEPTION 'denied' USING ERRCODE='42501';END IF; RETURN true; END$$;
   ${extract('collect_sms_held_upload_guard')}
   ${extract('collect_sms_held_resume_check')}
   CREATE TRIGGER held_upload BEFORE INSERT ON pg_temp.storage_upload_attempts FOR EACH ROW EXECUTE FUNCTION pg_temp.collect_sms_held_upload_guard();
   INSERT INTO pg_temp.burimunsi_recovered_sms_holds VALUES('source-1','sms/source-1');
   INSERT INTO pg_temp.burimunsi_observation_requests VALUES('source-1',1);
   INSERT INTO pg_temp.storage_put_intents VALUES('held','sms/source-1','pending',0,NULL,false,false),
    ('normal','sms/other','pending',1,NULL,false,false),('unknown','sms/source-1','pending',1,NULL,true,false),
    ('accepted','sms/source-1','pending',1,NULL,false,false),('conflict','sms/source-1','pending',1,NULL,false,false),
    ('active','sms/source-1','pending',0,'00000000-0000-4000-8000-000000000020',false,false);
   SELECT set_config('fixture.authorized','yes',false),set_config('fixture.consent','yes',false),
    set_config('collect.fence_admission_id','00000000-0000-4000-8000-000000000005',false),
    set_config('collect.fence_epoch','1',false),set_config('collect.fence_source_sha256',repeat('f',64),false);`);
  const args=['source-1','00000000-0000-4000-8000-000000000001','a'.repeat(64),'b'.repeat(64),'2026-11-11T12:00:00Z'];
  const check=()=>db.query('SELECT pg_temp.collect_sms_held_resume_check($1,$2::uuid,$3,$4,$5::timestamptz) result',args);
  assert.equal((await check()).rows[0].result,true);
  await db.exec("SELECT set_config('fixture.generation','2',false)");await assert.rejects(check,/sms_held_resume_consent_changed/);
  await db.exec("SELECT set_config('fixture.generation','1',false),set_config('fixture.consent','no',false)");
  await assert.rejects(check,/sms_held_resume_consent_changed/);
  await db.exec("SELECT set_config('fixture.consent','yes',false),set_config('fixture.authorized','no',false)");
  await assert.rejects(check,/denied/);
  await db.exec("SELECT set_config('fixture.authorized','yes',false)");
  await assert.rejects(()=>db.query('SELECT pg_temp.collect_sms_held_resume_check($1,$2::uuid,$3,$4,$5::timestamptz)',
   [args[0],args[1],'c'.repeat(64),args[3],args[4]]),/denied/);
  // An aborted database start has not produced a durable attempt and can be
  // retried. Once committed, even stale counters cannot authorize another PUT.
  await db.exec(`BEGIN; SAVEPOINT first_try;
   INSERT INTO pg_temp.storage_upload_attempts VALUES('00000000-0000-4000-8000-000000000010','held');
   ROLLBACK TO first_try; COMMIT;`);
  await db.exec("INSERT INTO pg_temp.storage_upload_attempts VALUES('00000000-0000-4000-8000-000000000011','held')");
  await assert.rejects(()=>db.exec("INSERT INTO pg_temp.storage_upload_attempts VALUES('00000000-0000-4000-8000-000000000012','held')"),/sms_held_upload_already_attempted/);
  await assert.rejects(()=>db.exec("INSERT INTO pg_temp.storage_upload_attempts VALUES('00000000-0000-4000-8000-000000000013','unknown')"),/sms_held_upload_already_attempted/);
  for(const [suffix,operation] of [['015','accepted'],['016','conflict'],['017','active']])
   await assert.rejects(()=>db.exec(`INSERT INTO pg_temp.storage_upload_attempts VALUES('00000000-0000-4000-8000-000000000${suffix}','${operation}')`),/sms_held_upload_already_attempted/);
  await db.exec("INSERT INTO pg_temp.storage_upload_attempts VALUES('00000000-0000-4000-8000-000000000014','normal')");
 }finally{await db.close();}
});
