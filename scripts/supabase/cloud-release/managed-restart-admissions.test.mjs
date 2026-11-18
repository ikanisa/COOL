import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import { PGlite } from '@electric-sql/pglite';

const migration = name => readFile(new URL('../../../supabase/migrations/' + name, import.meta.url), 'utf8');
const project = 'rrlduytparvsjfmegalh';
const source = 'a'.repeat(64);
const profile = 'b'.repeat(64);
const control = 'a0000000-0000-4000-8000-000000000001';

test('only old hosted admissions with a verified restart can retire while production stays open', async (t) => {
  const db = new PGlite();
  t.after(() => db.close());
  await db.exec(`
    CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role;
    CREATE ROLE collect_runtime; CREATE ROLE collect_importer;
    CREATE SCHEMA private; GRANT USAGE ON SCHEMA private TO collect_runtime;
    CREATE TABLE private.collect_fence_control(singleton boolean,project_ref text,source_sha256 text,
      epoch bigint,mode text,operation_id uuid,changed_at timestamptz);
    CREATE TABLE private.collect_fence_admissions(admission_id uuid PRIMARY KEY,epoch bigint,
      source_sha256 text,kind text,state text,created_at timestamptz);
    CREATE TABLE private.collect_fence_operations(operation_id uuid);
    CREATE TABLE private.collect_fence_source_upgrades(operation_id uuid);
    CREATE TABLE private.collect_fence_stopped_admissions(recovery_operation_id uuid);
    CREATE TABLE private.collect_deployment_identity(singleton boolean,profile_raw text,profile_sha256 text);
    CREATE TABLE private.collect_sms_fence_admissions(admission_id uuid,profile_sha256 text);
    CREATE FUNCTION private._collect_stopped_require_owner() RETURNS void LANGUAGE plpgsql AS $$BEGIN
      IF current_setting('role',true) <> 'none' THEN RAISE EXCEPTION 'owner required' USING ERRCODE='42501'; END IF;
    END$$;
    CREATE FUNCTION private._collect_fence_require_rc(boolean) RETURNS void LANGUAGE sql AS $$SELECT$$;
    CREATE FUNCTION private._collect_stopped_matches(uuid,bigint,text,text) RETURNS boolean LANGUAGE sql AS $$SELECT false$$;
    CREATE FUNCTION private._collect_fence_no_erasure() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN
      RAISE EXCEPTION 'immutable' USING ERRCODE='42501'; END$$;
  `);
  await db.query("INSERT INTO private.collect_fence_control VALUES(true,$1,$2,37,'quiescing',$3,clock_timestamp()-interval '30 minutes')", [project, source, control]);
  await db.query('INSERT INTO private.collect_deployment_identity VALUES(true,$1,$2)', [JSON.stringify({
    id: 'collect-managed-production-cloud', environment: 'production', mode: 'managed',
    supabase_origin: 'https://' + project + '.supabase.co',
  }), profile]);
  await db.exec(await migration('20261117064828_collect_managed_executor_retirement.sql'));
  await db.exec("UPDATE private.collect_fence_control SET mode='open'");
  await db.exec(await readFile(new URL('./managed-restart-admissions.sql', import.meta.url), 'utf8'));
  const insert = `WITH p AS (
    SELECT a.*,to_jsonb(a) snapshot,c.project_ref,c.operation_id,pg_postmaster_start_time() started,
      jsonb_build_object('format','collect.managed-executor-restart.v1','project',c.project_ref,
       'controlOperationId',c.operation_id,'sourceSha256',a.source_sha256,'admissionId',a.admission_id,'epoch',a.epoch,
       'gatewayProfileSha256',g.profile_sha256,
       'postmasterStartedAt',to_char(pg_postmaster_start_time() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
       'maximumWorkerLifetimeSeconds',400,'externalEffectsSettled',false,
       'limitsSource','https://supabase.com/docs/guides/functions/limits') || $2::jsonb evidence
    FROM private.collect_fence_admissions a LEFT JOIN private.collect_sms_fence_admissions g USING(admission_id)
    CROSS JOIN private.collect_fence_control c WHERE a.admission_id=$1
   ) INSERT INTO private.collect_managed_executor_retirements(operation_id,admission_id,fence_operation_id,epoch,
    source_sha256,kind,project_ref,maintenance_verified_at,evidence_sha256,evidence,original_admission,retained_unknown_obligation_id)
    SELECT gen_random_uuid(),admission_id,operation_id,epoch,source_sha256,kind,project_ref,started,
      encode(sha256(convert_to(evidence::text,'UTF8')),'hex'),evidence,snapshot,gen_random_uuid() FROM p`;
  const admit = async (seconds, kind = 'http_collect') => (await db.query(`INSERT INTO private.collect_fence_admissions
    VALUES(gen_random_uuid(),37,$1,$2,'active',pg_postmaster_start_time()+make_interval(secs=>$3)) RETURNING admission_id`,
  [source, kind, seconds])).rows[0].admission_id;
  const previous = await admit(-900);
  const recent = await admit(-5);
  const current = await admit(1);
  const jobs = await admit(-900, 'jobs');
  const gateway = await admit(-900);
  const foreignGateway = await admit(-900);
  await db.query('INSERT INTO private.collect_sms_fence_admissions VALUES($1,$2),($3,$4)', [gateway, profile, foreignGateway, 'c'.repeat(64)]);
  for (const [id, change] of [[recent, {}], [current, {}], [jobs, {}], [foreignGateway, {}], [previous, {externalEffectsSettled: true}],
    [previous, {sourceSha256: 'b'.repeat(64)}], [previous, {postmasterStartedAt: '2026-01-01T00:00:00.000Z'}]]) {
    await assert.rejects(db.query(insert, [id, JSON.stringify(change)]), {code: '55000'});
  }
  await assert.rejects(db.transaction(async (tx) => {
    await tx.exec('SET LOCAL ROLE collect_runtime');
    await tx.query(insert, [previous, '{}']);
  }), {code: '42501'});
  await db.query(insert, [previous, '{}']);
  await db.query(insert, [gateway, '{}']);
  const observed = await db.query(`SELECT r.external_effects_settled,a.state,c.mode
    FROM private.collect_managed_executor_retirements r JOIN private.collect_fence_admissions a USING(admission_id)
    CROSS JOIN private.collect_fence_control c`);
  assert.deepEqual(observed.rows, Array.from({length: 2}, () => ({external_effects_settled: false, state: 'active', mode: 'open'})));
  await assert.rejects(db.query('UPDATE private.collect_fence_admissions SET state = \'settled\' WHERE admission_id = $1', [previous]), {code: '55000'});
});
