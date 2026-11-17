-- Synthetic owner uses the existing managed Admin session and email proof.
-- Only a disposable test database and an admitted http_admin fence are used.
BEGIN;
SELECT pg_advisory_xact_lock_shared(7346371,1);
SET LOCAL ROLE collect_runtime;
SELECT set_config('collect.edge_verified','true',true),set_config('collect.fence_admission_id','__ADMIN_ADMISSION__',true),
 set_config('collect.fence_epoch','2',true),set_config('collect.fence_source_sha256','__ADMISSION_SOURCE__',true),
 set_config('burimunsi.collection_id','synthetic-group',true);
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','60000000-0000-4000-8000-000000000001',
 'session_id','60000000-0000-4000-8000-000000000002','role','authenticated','aal','aal1','exp',app.unixepoch()+3500,
 'amr',jsonb_build_array(jsonb_build_object('method','otp','timestamp',app.unixepoch())))::text,true);
SELECT private.admin_email_record_initial('synthetic-admin',repeat('a',64),'https://admin.synthetic.invalid',
 '60000000-0000-4000-8000-000000000003','synthetic-email-challenge');
SELECT private.burimunsi_native_grant_issue('synthetic-admin',repeat('a',64),'https://admin.synthetic.invalid',
 '60000000-0000-4000-8000-000000000003','synthetic-group','70000000-0000-4000-8000-000000000011',
 '10000000-0000-4000-8000-000000000011','disabled-worker',1,'synthetic-policy',8000000000000);
SELECT private.burimunsi_native_grant_issue('synthetic-admin',repeat('a',64),'https://admin.synthetic.invalid',
 '60000000-0000-4000-8000-000000000003','synthetic-group','70000000-0000-4000-8000-000000000012',
 '10000000-0000-4000-8000-000000000012','synthetic-worker',1,'synthetic-policy',8000000000000,true);
SELECT private.burimunsi_native_grant_issue('synthetic-admin',repeat('a',64),'https://admin.synthetic.invalid',
 '60000000-0000-4000-8000-000000000003','synthetic-group','70000000-0000-4000-8000-000000000013',
 '10000000-0000-4000-8000-000000000013','replacement-worker',1,'synthetic-policy',8000000000000,true);
COMMIT;
