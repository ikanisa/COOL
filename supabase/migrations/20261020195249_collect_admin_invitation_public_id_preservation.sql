-- PRIVATE UNVERSIONED ADDITIVE PROPOSAL. Migration owns adoption/execution.
-- Preserve the existing function OID/ACL and all authority/receipt behavior.
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
  INTO permissions FROM app.admin_account_role_capabilities c;
 RETURN jsonb_build_object('members',members,'permissionsByRole',permissions);
END$$;
