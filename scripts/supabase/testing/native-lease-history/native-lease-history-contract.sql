-- Synthetic exact-predecessor fixture. Everything below rolls back.
BEGIN;
SET LOCAL search_path=app,pg_catalog,pg_temp;
SELECT pg_advisory_xact_lock_shared(7346371,1);
CREATE TEMP TABLE history_contract(k text PRIMARY KEY,v jsonb) ON COMMIT DROP;
GRANT ALL ON history_contract TO collect_runtime;
CREATE FUNCTION pg_temp.require_history(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'lease history contract: %',label;END IF;END;$f$;
CREATE FUNCTION pg_temp.expect_history(statement text,expected text) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
 BEGIN EXECUTE statement;EXCEPTION WHEN OTHERS THEN IF SQLSTATE=expected THEN RETURN;END IF;RAISE;END;
 RAISE EXCEPTION 'expected SQLSTATE %',expected;
END;$f$;
GRANT EXECUTE ON FUNCTION pg_temp.require_history(boolean,text),pg_temp.expect_history(text,text) TO collect_runtime;
SELECT set_config('collect.edge_verified','true',true),set_config('collect.fence_admission_id','__JOB_ADMISSION__',true),
 set_config('collect.fence_epoch','3',true),set_config('collect.fence_source_sha256','__ADMISSION_SOURCE__',true),
 set_config('burimunsi.collection_id','synthetic-group',true);
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','60000000-0000-4000-8000-000000000001',
 'session_id','60000000-0000-4000-8000-000000000002','role','authenticated','aal','aal1','exp',app.unixepoch()+3500,
 'amr',jsonb_build_array(jsonb_build_object('method','otp','timestamp',app.unixepoch())))::text,true);
SELECT pg_temp.require_history((SELECT lease_version=1 AND attempts=1 AND state='waiting' AND grant_id IS NULL
 FROM private.burimunsi_native_financial_work WHERE id='__LEGACY_JOB_ID__') AND
 (SELECT count(*)=0 FROM private.burimunsi_native_lease_history),'pre-install lease has no invented grant history');
SELECT pg_temp.require_history(NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='private'
 AND table_name='burimunsi_native_lease_history' AND column_name='lease_token'),'history has no raw token column');
SELECT pg_temp.require_history((SELECT count(*)=1 FROM jsonb_array_elements(private._retention_manifest_catalog_v2()->'private_classes') c
 WHERE c->>'relation'='private.burimunsi_native_lease_history' AND c->>'scope'='unmapped_private' AND c->'blocked'='true'::jsonb),
 'shared history class is catalogued but blocked');
SELECT pg_temp.require_history((SELECT count(*)=1 AND bool_and(descriptor->>'status'='unmapped' AND descriptor->>'erasure'='blocked'
 AND descriptor->'subject_count'='null'::jsonb) FROM private._retention_manifest_rows_v2('synthetic-owner')
 WHERE class_name='private:burimunsi_native_lease_history'),'history subject count remains unknown');
SELECT pg_temp.require_history((SELECT count(*)=1 AND bool_and(descriptor->>'status'='unmapped' AND descriptor->>'erasure'='blocked'
 AND descriptor->'subject_count'='null'::jsonb) FROM private._retention_manifest_rows_v2('synthetic-other')
 WHERE class_name='private:burimunsi_native_lease_history'),'other subject remains unknown');
SELECT private._retention_manifest_schema_v2()->>'contract';

-- A later genuine retry creates version 2 only. Version 1 remains a visible
-- unfilled historical gap, not an invented owner or a false complete history.
UPDATE private.burimunsi_native_financial_work SET next_attempt_at=1 WHERE id='__LEGACY_JOB_ID__';
SET LOCAL ROLE collect_runtime;
INSERT INTO history_contract VALUES('lease2',private.burimunsi_native_work_claim('10000000-0000-4000-8000-000000000012','__LEGACY_JOB_ID__',30000));
INSERT INTO history_contract SELECT 'assert2',private.burimunsi_native_work_assert((v->>'jobId')::uuid,(v->>'leaseToken')::uuid,(v->>'leaseVersion')::bigint)
 FROM history_contract WHERE k='lease2';
SELECT pg_temp.require_history((SELECT (v->>'leaseVersion')::bigint=2 AND v->>'workerGrantId'='10000000-0000-4000-8000-000000000012'
 AND v->>'sourceId'='30000000-0000-4000-8000-000000000001' AND v->>'transactionMode'='historical' FROM history_contract WHERE k='assert2'),
 'history assertion preserves native source and actual grant');
SELECT set_config('burimunsi.native_lease_history_frame','1',true);
SELECT pg_temp.expect_history($q$SELECT * FROM private.burimunsi_native_lease_history$q$,'42501');
SELECT pg_temp.expect_history($q$DELETE FROM private.burimunsi_native_lease_history$q$,'42501');
SELECT pg_temp.expect_history($q$INSERT INTO private.burimunsi_native_lease_history DEFAULT VALUES$q$,'42501');
SELECT pg_temp.expect_history(format($q$SELECT private._burimunsi_native_work_assert_base(%L::uuid,%L::uuid,%s::bigint)$q$,
 (SELECT v->>'jobId' FROM history_contract WHERE k='lease2'),(SELECT v->>'leaseToken' FROM history_contract WHERE k='lease2'),
 (SELECT v->>'leaseVersion' FROM history_contract WHERE k='lease2')),'42501');
SELECT set_config('burimunsi.native_lease_history_frame','',true);
RESET ROLE;
SELECT pg_temp.require_history((SELECT count(*)=1 AND min(lease_version)=2 AND max(lease_version)=2
 AND bool_and(grant_id='10000000-0000-4000-8000-000000000012'::uuid AND grant_version=1
  AND source_id='30000000-0000-4000-8000-000000000001' AND transaction_id=source_id
  AND collection_id='synthetic-group' AND transaction_mode='historical' AND source_owner_user_id='synthetic-owner'
  AND source_key=repeat('b',64) AND body_sha256=repeat('d',64) AND object_sha256=repeat('e',64)
  AND source_fingerprint=repeat('f',64) AND source_code_sha256='__ADMISSION_SOURCE__'
  AND lease_token_sha256=(SELECT encode(sha256(convert_to(v->>'leaseToken','UTF8')),'hex') FROM history_contract WHERE k='lease2'))
 FROM private.burimunsi_native_lease_history WHERE work_id='__LEGACY_JOB_ID__'),'one exact post-install source-bound record');
SELECT pg_temp.expect_history($q$UPDATE private.burimunsi_native_lease_history SET grant_version=grant_version+1$q$,'55000');
SELECT pg_temp.expect_history($q$DELETE FROM private.burimunsi_native_lease_history$q$,'55000');
SELECT pg_temp.expect_history($q$TRUNCATE private.burimunsi_native_lease_history$q$,'55000');

-- Fault-inject missing journal in this disposable transaction only. The
-- admitted helper and custody snapshot must both refuse an unjournaled lease.
SAVEPOINT missing_history;
ALTER TABLE private.burimunsi_native_lease_history DISABLE TRIGGER native_lease_history_retain;
ALTER TABLE private.burimunsi_native_lease_history DISABLE TRIGGER collect_fence_statement_v1;
DELETE FROM private.burimunsi_native_lease_history WHERE work_id='__LEGACY_JOB_ID__' AND lease_version=2;
ALTER TABLE private.burimunsi_native_lease_history ENABLE ALWAYS TRIGGER native_lease_history_retain;
ALTER TABLE private.burimunsi_native_lease_history ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.expect_history(format($q$SELECT private.burimunsi_native_work_assert(%L::uuid,%L::uuid,%s::bigint)$q$,
 (SELECT v->>'jobId' FROM history_contract WHERE k='lease2'),(SELECT v->>'leaseToken' FROM history_contract WHERE k='lease2'),
 (SELECT v->>'leaseVersion' FROM history_contract WHERE k='lease2')),'55000');
SELECT pg_temp.expect_history(format($q$SELECT private.burimunsi_native_custody_snapshot(%L::uuid,%L::uuid,%s::bigint)$q$,
 (SELECT v->>'jobId' FROM history_contract WHERE k='lease2'),(SELECT v->>'leaseToken' FROM history_contract WHERE k='lease2'),
 (SELECT v->>'leaseVersion' FROM history_contract WHERE k='lease2')),'55000');
SELECT pg_temp.expect_history(format($q$SELECT private.burimunsi_native_work_defer(%L::uuid,%L::uuid,%s::bigint,'identity_unavailable',30000)$q$,
 (SELECT v->>'jobId' FROM history_contract WHERE k='lease2'),(SELECT v->>'leaseToken' FROM history_contract WHERE k='lease2'),
 (SELECT v->>'leaseVersion' FROM history_contract WHERE k='lease2')),'55000');
SELECT pg_temp.expect_history(format($q$SELECT private.burimunsi_native_work_complete(%L::uuid,%L::uuid,%s::bigint)$q$,
 (SELECT v->>'jobId' FROM history_contract WHERE k='lease2'),(SELECT v->>'leaseToken' FROM history_contract WHERE k='lease2'),
 (SELECT v->>'leaseVersion' FROM history_contract WHERE k='lease2')),'55000');
ROLLBACK TO missing_history;
SELECT pg_temp.require_history((SELECT count(*)=1 FROM private.burimunsi_native_lease_history WHERE work_id='__LEGACY_JOB_ID__')
 AND (SELECT count(*)=2 FROM pg_trigger WHERE tgrelid='private.burimunsi_native_lease_history'::regclass
  AND tgname IN('native_lease_history_retain','collect_fence_statement_v1') AND tgenabled='A'),'fault rollback restores row and guards');

-- Clearing a lease never clears its immutable journal.
SET LOCAL ROLE collect_runtime;
SELECT private.burimunsi_native_work_defer((v->>'jobId')::uuid,(v->>'leaseToken')::uuid,(v->>'leaseVersion')::bigint,'identity_unavailable',30000)
 FROM history_contract WHERE k='lease2';
INSERT INTO history_contract VALUES('other',private.burimunsi_native_work_enqueue('10000000-0000-4000-8000-000000000013','30000000-0000-4000-8000-000000000003'));
RESET ROLE;
SELECT pg_temp.require_history((SELECT state='waiting' AND grant_id IS NULL AND lease_token IS NULL AND lease_version=2
 FROM private.burimunsi_native_financial_work WHERE id='__LEGACY_JOB_ID__') AND
 (SELECT count(*)=1 FROM private.burimunsi_native_lease_history WHERE work_id='__LEGACY_JOB_ID__'),'defer clears lease but preserves history');

-- An injected journal-write failure must roll back the entire new claim.
CREATE FUNCTION pg_temp.reject_history_insert() RETURNS trigger LANGUAGE plpgsql AS $f$
BEGIN RAISE EXCEPTION 'synthetic journal failure' USING ERRCODE='P0001';END;$f$;
CREATE TRIGGER synthetic_history_insert_failure BEFORE INSERT ON private.burimunsi_native_lease_history
 FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_history_insert();
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.expect_history(format($q$SELECT private.burimunsi_native_work_claim('10000000-0000-4000-8000-000000000013',%L::uuid,30000)$q$,
 (SELECT v->>'jobId' FROM history_contract WHERE k='other')),'P0001');
RESET ROLE;
SELECT pg_temp.require_history((SELECT state='queued' AND lease_version=0 AND attempts=0 FROM private.burimunsi_native_financial_work
 WHERE id=(SELECT (v->>'jobId')::uuid FROM history_contract WHERE k='other')) AND NOT EXISTS(
 SELECT 1 FROM private.burimunsi_native_lease_history WHERE work_id=(SELECT (v->>'jobId')::uuid FROM history_contract WHERE k='other')),
 'journal failure rolls back claim');
DROP TRIGGER synthetic_history_insert_failure ON private.burimunsi_native_lease_history;
SAVEPOINT rolled_back_claim;
SET LOCAL ROLE collect_runtime;
INSERT INTO history_contract SELECT 'rollback-lease',private.burimunsi_native_work_claim('10000000-0000-4000-8000-000000000013',(v->>'jobId')::uuid,30000)
 FROM history_contract WHERE k='other';
RESET ROLE;
SELECT pg_temp.require_history((SELECT count(*)=1 FROM private.burimunsi_native_lease_history WHERE work_id=(SELECT (v->>'jobId')::uuid FROM history_contract WHERE k='other')),
 'claim wrote history in the same transaction');
ROLLBACK TO rolled_back_claim;
SELECT pg_temp.require_history((SELECT state='queued' AND lease_version=0 FROM private.burimunsi_native_financial_work
 WHERE id=(SELECT (v->>'jobId')::uuid FROM history_contract WHERE k='other')) AND NOT EXISTS(
 SELECT 1 FROM private.burimunsi_native_lease_history WHERE work_id=(SELECT (v->>'jobId')::uuid FROM history_contract WHERE k='other')),
 'transaction rollback removes both claim and history');

-- Exercise a real minimum-duration expiry without changing the lease clock or
-- bypassing its immutability guard, then reclaim with a different grant.
SET LOCAL ROLE collect_runtime;
INSERT INTO history_contract SELECT 'expired-lease',private.burimunsi_native_work_claim('10000000-0000-4000-8000-000000000013',(v->>'jobId')::uuid,30000)
 FROM history_contract WHERE k='other';
SELECT pg_sleep(30.2);
SELECT pg_temp.expect_history(format($q$SELECT private.burimunsi_native_work_assert(%L::uuid,%L::uuid,%s::bigint)$q$,
 (SELECT v->>'jobId' FROM history_contract WHERE k='expired-lease'),(SELECT v->>'leaseToken' FROM history_contract WHERE k='expired-lease'),
 (SELECT v->>'leaseVersion' FROM history_contract WHERE k='expired-lease')),'55000');
INSERT INTO history_contract SELECT 'reclaimed-lease',private.burimunsi_native_work_claim('10000000-0000-4000-8000-000000000012',(v->>'jobId')::uuid,30000)
 FROM history_contract WHERE k='other';
RESET ROLE;
SELECT pg_temp.require_history((SELECT count(*)=2 AND min(lease_version)=1 AND max(lease_version)=2
 AND count(DISTINCT grant_id)=2 AND bool_and(source_id='30000000-0000-4000-8000-000000000003')
 FROM private.burimunsi_native_lease_history WHERE work_id=(SELECT (v->>'jobId')::uuid FROM history_contract WHERE k='other')),
 'expired lease and genuine reclaim retain both grant versions');

-- Revocation after clearing prevents reuse; a different grant on a genuine
-- retry creates a second independently bound version and retains the first.
UPDATE private.burimunsi_native_financial_work SET next_attempt_at=1 WHERE id='__LEGACY_JOB_ID__';
SET LOCAL ROLE collect_runtime;
SELECT set_config('collect.fence_admission_id','__ADMIN_ADMISSION__',true);
SELECT private.burimunsi_native_grant_revoke('synthetic-admin',repeat('a',64),'https://admin.synthetic.invalid',
 '60000000-0000-4000-8000-000000000003','synthetic-group','70000000-0000-4000-8000-000000000031',
 '10000000-0000-4000-8000-000000000012');
SELECT set_config('collect.fence_admission_id','__JOB_ADMISSION__',true);
SELECT pg_temp.expect_history($q$SELECT private.burimunsi_native_work_claim('10000000-0000-4000-8000-000000000012','__LEGACY_JOB_ID__',30000)$q$,'42501');
INSERT INTO history_contract VALUES('lease3',private.burimunsi_native_work_claim('10000000-0000-4000-8000-000000000013','__LEGACY_JOB_ID__',30000));
SELECT pg_temp.require_history((SELECT (private.burimunsi_native_work_assert((v->>'jobId')::uuid,(v->>'leaseToken')::uuid,
 (v->>'leaseVersion')::bigint)->>'workerGrantId')='10000000-0000-4000-8000-000000000013' FROM history_contract WHERE k='lease3'),
 'new lease binds the replacement grant');
SELECT set_config('collect.fence_admission_id','__ADMIN_ADMISSION__',true);
SELECT private.burimunsi_native_grant_revoke('synthetic-admin',repeat('a',64),'https://admin.synthetic.invalid',
 '60000000-0000-4000-8000-000000000003','synthetic-group','70000000-0000-4000-8000-000000000032',
 '10000000-0000-4000-8000-000000000013');
SELECT set_config('collect.fence_admission_id','__JOB_ADMISSION__',true);
SELECT pg_temp.expect_history(format($q$SELECT private.burimunsi_native_work_assert(%L::uuid,%L::uuid,%s::bigint)$q$,
 (SELECT v->>'jobId' FROM history_contract WHERE k='lease3'),(SELECT v->>'leaseToken' FROM history_contract WHERE k='lease3'),
 (SELECT v->>'leaseVersion' FROM history_contract WHERE k='lease3')),'42501');
RESET ROLE;
SELECT pg_temp.require_history((SELECT count(*)=2 AND min(lease_version)=2 AND max(lease_version)=3
 AND count(DISTINCT grant_id)=2 FROM private.burimunsi_native_lease_history WHERE work_id='__LEGACY_JOB_ID__')
 AND NOT EXISTS(SELECT 1 FROM private.burimunsi_native_lease_history WHERE work_id='__LEGACY_JOB_ID__' AND lease_version=1)
 AND (SELECT count(*)=1 FROM app.ledger_entries),'revocation preserves both genuine entries and the old gap without a credit');
ROLLBACK;
SELECT jsonb_build_object('status','pass','fixture','native-lease-history','synthetic_only',true,'legacy_version_uninvented',true,'new_financial_postings',0);
