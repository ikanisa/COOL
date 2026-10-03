BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SELECT jsonb_build_object(
 'roles',(SELECT coalesce(jsonb_agg(jsonb_build_array(rolname,rolsuper,rolinherit,rolcreaterole,
   rolcreatedb,rolcanlogin,rolreplication,rolbypassrls,rolconnlimit,rolvaliduntil::text,
   encode(sha256(convert_to(ARRAY(SELECT x FROM unnest(rolconfig) x ORDER BY x COLLATE "C")::text,'UTF8')),'hex'))
   ORDER BY rolname COLLATE "C"),'[]') FROM pg_roles),
 'memberships',(SELECT coalesce(jsonb_agg(jsonb_build_array(pg_get_userbyid(roleid),
   pg_get_userbyid(member),pg_get_userbyid(grantor),admin_option,inherit_option,set_option)
   ORDER BY pg_get_userbyid(roleid) COLLATE "C",pg_get_userbyid(member) COLLATE "C",
   pg_get_userbyid(grantor) COLLATE "C"),'[]') FROM pg_auth_members),
 'settings',(SELECT coalesce(jsonb_agg(jsonb_build_array(
   CASE WHEN setdatabase=0 THEN '*' ELSE current_database() END,
   CASE WHEN setrole=0 THEN '*' ELSE pg_get_userbyid(setrole) END,
   encode(sha256(convert_to(ARRAY(SELECT x FROM unnest(setconfig) x ORDER BY x COLLATE "C")::text,'UTF8')),'hex'))
   ORDER BY setdatabase=0,CASE WHEN setrole=0 THEN '*' ELSE pg_get_userbyid(setrole) END COLLATE "C"),'[]')
   FROM pg_db_role_setting WHERE setdatabase=0 OR setdatabase=(SELECT oid FROM pg_database WHERE datname=current_database()))
);
COMMIT;
