import {ApiError} from '../core.js';
import {adminEmailArguments} from '../admin_email_policy.js';
import {AdminScopeSetup} from './admin-scope-setup.js';
import {requireId} from './values.js';

/** Only used after the genuine shared owner/fresh-email gate. The selected
 * existing scope is revalidated by every original command and its version CAS.
 * Optional rollout filtering cannot manufacture or silently retarget a scope. */
export async function selectAdminCollection({env,account,requested}){
 const filter=env.BURIMUNSI_COLLECTION_ID;
 if(requested!==null&&requested!==undefined){
  requireId(requested);
  if(filter!==undefined&&filter!==''&&filter!==requested)throw new ApiError(409,'burimunsi_scope_changed','The selected group is outside this rollout.');
  return requested;
 }
 if(filter!==undefined&&filter!==''){requireId(filter);return filter;}
 const value=await new AdminScopeSetup({env,actorArgs:adminEmailArguments(account),actorId:account.principal_id,sessionId:account.auth_session_id}).directory();
 if(value.scopes.length!==1)throw new ApiError(409,'burimunsi_scope_required','Choose an existing prepared group.');
 return value.scopes[0].collectionId;
}
