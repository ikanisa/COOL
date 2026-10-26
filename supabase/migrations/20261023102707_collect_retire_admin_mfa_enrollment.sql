-- Retire effective Admin MFA enrollment without changing immutable capability,
-- grant, factor, proof or audit rows. Legacy Cloudflare deployment is unchanged.
-- CREATE OR REPLACE preserves the current function/view identities and ACLs;
-- their signatures, security modes, search paths and unrelated behavior remain.
REVOKE EXECUTE ON FUNCTION private.record_mfa_projection(uuid) FROM collect_runtime;

CREATE OR REPLACE FUNCTION private.assert_actor(p_permission text DEFAULT NULL,p_collection_id text DEFAULT NULL,p_group_role text DEFAULT NULL,p_min_aal bigint DEFAULT 1,p_fresh_seconds bigint DEFAULT NULL)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=app,pg_catalog AS $$
DECLARE principal text;claims jsonb;projected app.auth_sessions%ROWTYPE;managed jsonb;
 now_seconds bigint:=app.unixepoch();admin_actor jsonb;email_ttl bigint;
BEGIN
 IF p_permission='auth.mfa.enroll' THEN RAISE EXCEPTION 'permission_denied' USING ERRCODE='42501';END IF;
 claims:=private.request_claims();principal:=api.current_principal_id();
 IF principal IS NULL OR claims->>'role' IS DISTINCT FROM 'authenticated' THEN RAISE EXCEPTION 'session_changed' USING ERRCODE='42501';END IF;
 SELECT s.* INTO projected FROM app.auth_sessions s JOIN app.users u ON u.id=s.user_id
 WHERE s.id=api.current_session_id() AND s.user_id=principal AND s.revoked_at IS NULL
 AND s.expires_at>now_seconds AND u.access_status='active' FOR SHARE OF s,u;
 IF NOT FOUND THEN RAISE EXCEPTION 'session_changed' USING ERRCODE='42501';END IF;
 SELECT to_jsonb(s) INTO managed FROM auth.sessions s JOIN auth.users u ON u.id=s.user_id
 WHERE s.id::text=projected.id AND u.id::text=claims->>'sub' AND to_jsonb(u)->>'deleted_at' IS NULL
 AND (to_jsonb(u)->>'banned_until' IS NULL OR (to_jsonb(u)->>'banned_until')::timestamptz<=now())
 AND (to_jsonb(s)->>'not_after' IS NULL OR (to_jsonb(s)->>'not_after')::timestamptz>now()) FOR SHARE OF s,u;
 IF managed IS NULL THEN RAISE EXCEPTION 'session_changed' USING ERRCODE='42501';END IF;
 IF projected.surface='admin' THEN
  admin_actor:=private._admin_email_context();
  IF admin_actor->>'principal_id' IS DISTINCT FROM principal OR admin_actor->>'session_id' IS DISTINCT FROM projected.id
  THEN RAISE EXCEPTION 'session_changed' USING ERRCODE='42501';END IF;
  -- Requested policy thresholds remain unchanged in stored mutation guards.
  -- Admin policy is satisfied by email possession/current intent, not fake AAL2.
  IF p_min_aal>1 OR p_fresh_seconds IS NOT NULL THEN
   email_ttl:=CASE WHEN p_min_aal>1 THEN least(300,coalesce(p_fresh_seconds,300)) ELSE p_fresh_seconds END;
   PERFORM private.assert_admin_email_context(email_ttl);
  END IF;
  IF p_permission IS NOT NULL AND NOT EXISTS(SELECT 1 FROM app.admin_account_role_capabilities c
    WHERE c.role=admin_actor->>'role' AND c.permission=p_permission)
  THEN RAISE EXCEPTION 'permission_denied' USING ERRCODE='42501';END IF;
 ELSE
  -- Exact preexisting managed MFA and freshness conditions for members.
  IF p_min_aal>1 AND (claims->>'aal' IS DISTINCT FROM 'aal2' OR managed->>'aal' IS DISTINCT FROM 'aal2' OR projected.assurance_level<>2 OR projected.mfa_at IS NULL OR projected.mfa_at<now_seconds-300 OR NOT EXISTS(SELECT 1 FROM private.managed_mfa_proofs proof JOIN auth.mfa_factors f ON f.id=proof.factor_id AND f.user_id=proof.user_id WHERE proof.session_id::text=projected.id AND proof.user_id::text=claims->>'sub' AND proof.factor_id::text=projected.mfa_factor_id AND f.status::text='verified' AND proof.verified_at_epoch=projected.mfa_at)) THEN RAISE EXCEPTION 'mfa_required' USING ERRCODE='42501';END IF;
  IF p_fresh_seconds IS NOT NULL AND greatest(projected.auth_at,coalesce(projected.mfa_at,0))<now_seconds-p_fresh_seconds THEN RAISE EXCEPTION 'fresh_auth_required' USING ERRCODE='42501';END IF;
 END IF;
 IF p_permission IS NOT NULL AND (projected.surface<>'admin' OR NOT EXISTS(SELECT 1 FROM app.admin_grants g WHERE g.user_id=principal AND g.permission=p_permission)) THEN RAISE EXCEPTION 'permission_denied' USING ERRCODE='42501';END IF;
 IF p_collection_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM app.memberships m JOIN app.collections c ON c.id=m.collection_id WHERE m.user_id=principal AND m.collection_id=p_collection_id AND m.active=1 AND c.status='active' AND (p_group_role IS NULL OR m.role=p_group_role OR (p_group_role='admin' AND m.role='owner'))) THEN RAISE EXCEPTION 'group_access_denied' USING ERRCODE='42501';END IF;
 RETURN principal;
END$$;

CREATE OR REPLACE FUNCTION private.admin_invitation_v2_list(p_actor_id text,p_cookie_hash text,p_origin text,p_public_session_id text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE members jsonb; permissions jsonb;
BEGIN
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);PERFORM private.admin_invitation_actor(p_actor_id,p_cookie_hash,p_origin,p_public_session_id);
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',a.id,'publicId',linked_user.public_id,'email',a.email,'role',a.role,'status',a.status,'displayName',a.display_name,
  'createdAt',to_char(to_timestamp(a.created_at) AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
  'invitedAt',CASE WHEN a.invited_at IS NOT NULL THEN to_char(to_timestamp(a.invited_at) AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') END,
  'acceptedAt',CASE WHEN a.accepted_at IS NOT NULL THEN to_char(to_timestamp(a.accepted_at) AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') END,'invitation',
  CASE WHEN latest.request_id IS NOT NULL AND latest.subject_identity_sha256=private.admin_invitation_fingerprint(a.id)
   THEN private.admin_invitation_v2_result(latest::private.admin_invitation_attempts,false) ELSE NULL END) ORDER BY a.email),'[]'::jsonb) INTO members
  FROM app.admin_users a LEFT JOIN app.admin_principal_links member_link ON member_link.admin_user_id=a.id
  LEFT JOIN app.users linked_user ON linked_user.id=member_link.user_id
  LEFT JOIN LATERAL(SELECT r.* FROM private.admin_invitation_attempts r WHERE r.subject_id=a.id
   AND r.replayed_request_id IS NULL ORDER BY r.attempt_sequence DESC LIMIT 1) latest ON true;
 SELECT jsonb_build_object(
  'owner',coalesce(jsonb_agg(c.permission ORDER BY c.permission) FILTER(WHERE c.role='owner'),'[]'::jsonb),
  'admin',coalesce(jsonb_agg(c.permission ORDER BY c.permission) FILTER(WHERE c.role='admin'),'[]'::jsonb),
  'staff',coalesce(jsonb_agg(c.permission ORDER BY c.permission) FILTER(WHERE c.role='staff'),'[]'::jsonb))
  INTO permissions FROM app.admin_account_role_capabilities c WHERE c.permission<>'auth.mfa.enroll';
 RETURN jsonb_build_object('members',members,'permissionsByRole',permissions);
END$$;

CREATE OR REPLACE VIEW app.assisted_sms_current_sessions WITH(security_invoker=true) AS
 SELECT a.id AS admin_id,l.user_id,s.auth_session_id,s.public_id,a.role,a.auth_version,
  s.issued_mfa_at AS mfa_at,s.origin,c.permission,p.id AS email_proof_id,p.verified_at AS email_verified_at
 FROM app.admin_sessions s JOIN app.admin_users a ON a.id=s.user_id
 JOIN app.admin_principal_links l ON l.admin_user_id=a.id JOIN app.users u ON u.id=l.user_id
 JOIN app.auth_sessions ss ON ss.id=s.auth_session_id AND ss.user_id=u.id
 JOIN app.admin_grants g ON g.user_id=u.id
 JOIN app.admin_account_role_capabilities c ON c.permission=g.permission AND c.role=a.role AND c.permission<>'auth.mfa.enroll'
 JOIN LATERAL(
  SELECT proof.* FROM private.admin_sensitive_email_proofs proof
  JOIN private.admin_email_operations o ON o.challenge_id=proof.challenge_id
  WHERE proof.admin_id=a.id AND proof.principal_id=u.id AND proof.original_session_id::text=s.auth_session_id
   AND proof.cookie_hash=s.token_hash AND proof.public_session_id=s.public_id AND proof.auth_version=a.auth_version
   AND proof.origin=s.origin AND proof.identity_value=lower(a.email) AND proof.purpose='admin_sensitive_operations'
   AND o.verification_state='verified' AND o.cleanup_state IN('confirmed','not_required')
   AND proof.verified_session_id=o.verified_session_id AND proof.verified_at=o.verified_amr_at
   AND proof.verified_at BETWEEN app.unixepoch()-300 AND app.unixepoch()
  ORDER BY proof.verified_at DESC,proof.recorded_at DESC,proof.id DESC LIMIT 1
 ) p ON true
 WHERE a.status='active' AND a.auth_version=s.auth_version AND u.access_status='active' AND ss.surface='admin'
  AND s.expires_at>app.unixepoch() AND ss.expires_at>app.unixepoch() AND ss.revoked_at IS NULL
  AND private._admin_email_original_is_live(a.id,s.token_hash,s.origin,s.public_id);
