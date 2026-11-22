import {ApiError,json,readJson,first,uuid} from './core.js';
import {hasFreshAdminEmail,requireFreshAdminEmail} from './admin_email_policy.js';
import {accountDatabase,accountReadDatabase} from './admin_accounts_legacy.js';
import {adminAccountSession} from './admin_session.js';
import {handleAdminInvitation} from './admin_invitation.js';
import {handleAdminInvitationV2} from './admin_invitation_v2.js';
import {preliminaryCurrentOwner} from './admin_owner_precheck.js';
import {failAdminAccount as fail} from './admin_account_support/errors.js';

const unix=()=>Math.floor(Date.now()/1000);

export async function readAdminTeam(request, env) {
  const account = await adminAccountSession(request, env);
  const permission = 'admin_users.read';
  if (!account.permissions.includes(permission)) fail('permission_required');

  // Resolve the directory and role matrix under the same current session and
  // live read grant, even if either changed after the initial sign-in lookup.
  const {DB: db} = accountReadDatabase(env, account, permission);
  const [members, capabilities] = await db.batch([
    db.prepare(`SELECT a.id,a.email,a.role,a.status,a.display_name,a.created_at,a.invited_at,a.accepted_at,
      (SELECT CASE WHEN i.state IN('reserved','dispatching') THEN 'unknown' ELSE i.state END
       FROM private.admin_invitation_attempts i WHERE i.subject_id=a.id AND i.contract_version=1 AND i.replayed_request_id IS NULL
       ORDER BY i.attempt_sequence DESC LIMIT 1) AS invitation_email_status,
      (SELECT i.request_id::text FROM private.admin_invitation_attempts i
       WHERE i.subject_id=a.id AND i.contract_version=1 AND i.replayed_request_id IS NULL
       ORDER BY i.attempt_sequence DESC LIMIT 1) AS invitation_request_id,
      (SELECT i.kind FROM private.admin_invitation_attempts i
       WHERE i.subject_id=a.id AND i.contract_version=1 AND i.replayed_request_id IS NULL
       ORDER BY i.attempt_sequence DESC LIMIT 1) AS invitation_operation
      FROM admin_users a ORDER BY a.email`),
    db.prepare("SELECT role,permission FROM admin_account_role_capabilities WHERE permission<>'auth.mfa.enroll'"),
  ]);
  const permissionsByRole = {owner: [], admin: [], staff: []};
  for (const {role, permission} of capabilities.results) permissionsByRole[role].push(permission);
  const canManage = account.permissions.includes('admin_users.manage') &&
    hasFreshAdminEmail(account) && await preliminaryCurrentOwner(env, account);
  return json({
    currentEmail: account.email,
    canManage,
    permissionsByRole,
    members: members.results.map(member => ({
      ...member,
      displayName: member.display_name,
      createdAt: new Date(member.created_at * 1000).toISOString(),
      invitedAt: member.invited_at ? new Date(member.invited_at * 1000).toISOString() : null,
      acceptedAt: member.accepted_at ? new Date(member.accepted_at * 1000).toISOString() : null,
      emailStatus: member.invitation_email_status ?? null,
      invitationRequestId: member.invitation_request_id ?? null,
      invitationOperation: member.invitation_operation ?? null,
    })),
  });
}

export async function manageAdminTeam(request,env,path){
 const account=await adminAccountSession(request,env);if(!account.permissions.includes('admin_users.manage')||!await preliminaryCurrentOwner(env,account))fail('owner_required');requireFreshAdminEmail(account);
 const body=request.method==='GET'?{}:await readJson(request);
 const invitationV2=await handleAdminInvitationV2(request,env,account,body,path);if(invitationV2)return invitationV2;
 const invitation=await handleAdminInvitation(request,env,account,body,path);if(invitation)return invitation;
 const match=/^\/team\/([0-9a-f-]{36})\/revoke$/.exec(path);if(!match)fail('not_found',404);
 const subject=await first(env,'SELECT * FROM admin_users WHERE id=?',uuid(match[1]));if(!subject||subject.role==='owner')fail('owner_protected');
 const dynamic=env.COLLECT_ADMIN_DYNAMIC_OWNER_AUTH_ENABLED==='true';
 const update=env.DB.prepare("UPDATE admin_users SET status='revoked',auth_version=auth_version+1,challenge_version=challenge_version+1,updated_at=? WHERE id=?"+
  (dynamic?" AND id <> (private.collect_owner_attestation()->>'adminId')":'' )).bind(unix(),subject.id);
 const changed=await accountDatabase(env,account,'admin_users.manage',{owner:true,mfa:true,fresh:true}).DB.batch([update]);
 if(dynamic&&changed?.[0]?.meta?.changes!==1)throw new ApiError(409,'admin_access_changed','The account changed. Refresh before trying again.');
 return json({ok:true});
}
