import {LEGACY_ADMIN_OWNER_EMAIL} from '../admin-security.js';
import {ApiError} from './core.js';
import {fenceFailure} from '../application-fence.js';

/** Preliminary display/dispatch check only. Every sensitive mutation must still
 * revalidate the cookie-bound actor, protected owner, grants and email proof
 * inside its existing fenced database transaction. */
export async function preliminaryCurrentOwner(env,account){
 if(account?.role!=='owner')return false;
 if(env?.COLLECT_ADMIN_DYNAMIC_OWNER_AUTH_ENABLED!=='true')return account.email===LEGACY_ADMIN_OWNER_EMAIL;
 if(typeof account.id!=='string'||typeof account.principal_id!=='string'||typeof account.email!=='string')return false;
 try{
  const row=await env.DB.prepare('SELECT private.collect_owner_is(?,?,?) AS result')
   .bind(account.id,account.principal_id,account.email).first();
  return row?.result===true;
 }catch(error){
  if(['application_fenced','application_fence_unavailable'].includes(error?.code))throw error;
  if(['collect_fence_closed','collect_fence_unavailable'].includes(error?.message))throw fenceFailure(error);
  throw new ApiError(503,'owner_identity_unavailable','The current owner identity could not be confirmed. Try again later.');
 }
}
