-- READ ONLY; no credential, header, payload or managed-row content query.
SELECT current_user,current_database(),current_setting('cron.timezone',true) AS cron_timezone,
 to_regprocedure('cron.schedule(text,text,text)') AS schedule,
 to_regprocedure('cron.alter_job(bigint,text,text,text,text,boolean)') AS alter_job;
SELECT extname,extversion,pg_get_userbyid(extowner) AS owner
 FROM pg_extension WHERE extname IN('pg_cron','pg_net','supabase_vault') ORDER BY extname;
SELECT n.nspname,pg_get_userbyid(n.nspowner) AS owner,
 CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END AS grantee,
 pg_get_userbyid(a.grantor) AS grantor,a.privilege_type,a.is_grantable
 FROM pg_namespace n LEFT JOIN LATERAL aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner))) a ON true
 WHERE n.nspname IN('collect_ops','cron','net','vault') ORDER BY 1,3,5;
SELECT n.nspname,c.relname,pg_get_userbyid(c.relowner) AS owner,
 CASE a.grantee WHEN 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END AS grantee,
 pg_get_userbyid(a.grantor) AS grantor,a.privilege_type,a.is_grantable
 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 LEFT JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a ON true
 WHERE (n.nspname='app' AND c.relname='auth_google_flows') OR
 (n.nspname='net' AND c.relname IN('http_request_queue','_http_response')) OR
 (n.nspname='vault' AND c.relname IN('secrets','decrypted_secrets')) ORDER BY 1,2,4,6;
SELECT r.rolname,
 has_schema_privilege(r.rolname,'net','USAGE') AS net_usage,
 has_table_privilege(r.rolname,'net.http_request_queue','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') AS queue_any,
 has_table_privilege(r.rolname,'net._http_response','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') AS response_any,
 has_schema_privilege(r.rolname,'vault','USAGE') AS vault_usage,
 has_schema_privilege(r.rolname,'vault','USAGE WITH GRANT OPTION') AS vault_usage_grantable
 FROM pg_roles r WHERE rolname IN('postgres','anon','authenticated','service_role','collect_runtime','collect_importer') ORDER BY 1;
SELECT e.evtname,e.evtevent,e.evtenabled,e.evttags,n.nspname,p.proname,
 pg_get_userbyid(e.evtowner) AS owner,
 encode(sha256(convert_to(pg_get_functiondef(p.oid),'UTF8')),'hex') AS definition_sha256
 FROM pg_event_trigger e JOIN pg_proc p ON p.oid=e.evtfoid JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE p.proname IN('grant_pg_net_access','grant_pg_cron_access') ORDER BY 1;
SELECT jobid,jobname,schedule,command,database,username,active FROM cron.job
 WHERE jobname='collect-google-ciphertext-expiry-v1';
SELECT p.oid::regprocedure::text AS identity,pg_get_userbyid(p.proowner) AS owner,p.prosecdef,p.proconfig,
 encode(sha256(convert_to(pg_get_functiondef(p.oid),'UTF8')),'hex') AS definition_sha256
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='collect_ops';
SELECT count(*) AS eligible_expired FROM app.auth_google_flows
 WHERE expires_at<=floor(extract(epoch FROM clock_timestamp()))::bigint AND status IN('pending','exchanging','ready');
SELECT h.jobid,h.runid,h.status,h.start_time,h.end_time
 FROM cron.job_run_details h JOIN cron.job j ON j.jobid=h.jobid
 WHERE j.jobname='collect-google-ciphertext-expiry-v1' ORDER BY h.runid DESC LIMIT 20;
