import {ApiError,first,id} from './core.js';

// Generic member management must never become a second operator-account path.
export async function assertMemberManagementTarget(env,row) {
 if(row.member_type==='operator'||await first(env,'SELECT 1 AS linked FROM admin_principal_links WHERE user_id=?',row.id))
  throw new ApiError(501,'operation_unavailable','This action is not available.');
}

// This check shares the actual mutation batch with current actor authority,
// receipt, audit, target update and session revocation. A read is insufficient:
// a target can gain ownership or an operator link during an intervening await.
export function memberManagementGuard(env,row,status) {
 const guardId=id();
 return [env.DB.prepare(`INSERT INTO admin_bridge_guards(id,passed) SELECT ?,(CASE WHEN
  EXISTS(SELECT 1 FROM users u WHERE u.id=? AND u.revision=? AND u.member_type!='operator')
  AND NOT EXISTS(SELECT 1 FROM admin_principal_links WHERE user_id=?)
  AND (?='active' OR NOT EXISTS(SELECT 1 FROM memberships m JOIN collections c ON c.id=m.collection_id
    WHERE m.user_id=? AND m.role='owner' AND m.active=1 AND c.status='active'))
  THEN 1 ELSE 0 END)`).bind(guardId,row.id,row.revision,row.id,status,row.id),
  env.DB.prepare('DELETE FROM admin_bridge_guards WHERE id=?').bind(guardId)];
}
