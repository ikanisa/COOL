-- SELECT-only post-attempt observation. It does not prove who installed an
-- object or that an unacknowledged transaction cannot still commit later.
WITH wanted(signature) AS (VALUES
 ('private._collect_managed_identity_preimage()'),
 ('private.collect_bind_managed_deployment(uuid,text,text,uuid,bigint,text)')
)
SELECT jsonb_agg(jsonb_build_object(
 'signature',w.signature,'present',p.oid IS NOT NULL,
 'bodySha256',CASE WHEN p.oid IS NOT NULL THEN encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') END,
 'owner',pg_get_userbyid(p.proowner),'language',l.lanname,'securityDefiner',p.prosecdef,
 'volatility',p.provolatile,'strict',p.proisstrict,'returns',p.prorettype::regtype::text,'settings',p.proconfig,
 'ownerOnlyAcl',CASE WHEN p.oid IS NOT NULL THEN NOT EXISTS(
  SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE a.grantee<>p.proowner) END
) ORDER BY w.signature) AS routine_observation
FROM wanted w LEFT JOIN pg_proc p ON p.oid=to_regprocedure(w.signature) LEFT JOIN pg_language l ON l.oid=p.prolang;
