import {ApiError,json,readJson} from './core.js';
import {authRequest} from '../auth-http.js';
import {requireFreshAdminEmail} from './admin_email_policy.js';
import {accountDatabase,adminCookie} from './admin_accounts_legacy.js';

export async function changeAdminPassword(request,env,account){
 const body=await readJson(request,4096);
 // Check the existing sensitive policy before credential validation or dispatch.
 requireFreshAdminEmail(account);
 if(!body||Array.isArray(body)||Object.keys(body).length!==2||
  !Object.hasOwn(body,'currentPassword')||!Object.hasOwn(body,'newPassword')||
  typeof body.currentPassword!=='string'||body.currentPassword.length<1||body.currentPassword.length>512||
  typeof body.newPassword!=='string'||body.newPassword.length<12||body.newPassword.length>128)
  throw new ApiError(400,'invalid_password_change','Enter your current password and a new password of 12 to 128 characters.');
 let authority;
 try{authority=await accountDatabase(env,account,null,{fresh:true}).DB.batch([
  env.DB.prepare('SELECT private.assert_admin_password_change_context() AS allowed')]);}
 catch(error){if(String(error?.message??error).includes('password_recovery_required'))
   throw new ApiError(403,'password_recovery_required','Use the email password recovery link to set or recover your password.');
  throw error;}
 if(authority?.[0]?.results?.length!==1||authority[0].results[0]?.allowed!==true)
  throw new ApiError(503,'password_change_unavailable','Your current password authority could not be confirmed.');
 // Deployment requires the existing managed current-password policy enabled.
 // The SQL guard excludes passwordless/OTP/magiclink/recovery originals;
 // GoTrue verifies the
 // actual current password for this normal account. No password grant is made.
 await authRequest(env,'/user',{method:'PUT',token:account.supabaseTokens.access_token,
  body:{password:body.newPassword,current_password:body.currentPassword}});
 // Preserve the existing password-change sign-out scope, explicitly.
 await authRequest(env,'/logout?scope=global',{token:account.supabaseTokens.access_token});
 await env.DB.prepare('DELETE FROM admin_sessions WHERE token_hash=?').bind(account.token_hash).run();
 return json({ok:true},200,{'Set-Cookie':adminCookie()});
}
