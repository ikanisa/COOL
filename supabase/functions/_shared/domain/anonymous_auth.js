import {ApiError,json,first,id,uuid} from './core.js';
import {authRequest,verifyToken} from '../auth-http.js';

const unavailable=()=>new ApiError(503,'anonymous_unavailable','Guest access is unavailable.');
const unknown=()=>new ApiError(503,'guest_upgrade_unknown','The account verification result is not confirmed. Check this request before trying again.');
const enabled=env=>{if(env.AUTH_ANONYMOUS_ENABLED!=='true')throw unavailable();};
const bearer=request=>{const token=request.headers.get('Authorization')?.match(/^Bearer (\S+)$/)?.[1];if(!token)throw new ApiError(401,'guest_session_required','Open a guest session first.');return token;};
const cleanBody=(body,keys)=>{
 if(!body||Array.isArray(body)||typeof body!=='object'||Object.keys(body).some(key=>!keys.includes(key)))throw new ApiError(400,'invalid_request','This identity request is invalid.');
};
const captcha=body=>{
 if(typeof body.captcha_token!=='string'||!body.captcha_token||body.captcha_token.length>2048)throw new ApiError(400,'captcha_required','Complete security verification.');
};
function target(body,env){
 if(body.surface!==undefined&&body.surface!=='member'||(body.phone==null)===(body.email==null))throw new ApiError(400,'invalid_identity','Enter an email address or phone number.');
 if(body.phone!=null){
  if(typeof body.phone!=='string'||!/^\+2507[2389][0-9]{7}$/.test(body.phone)||!['sms','whatsapp'].includes(body.channel))throw new ApiError(400,'invalid_phone','Enter a Rwanda phone number and a supported channel.');
  if(env[body.channel==='sms'?'AUTH_SMS_ENABLED':'AUTH_WHATSAPP_ENABLED']!=='true')throw new ApiError(503,body.channel+'_unavailable','This sign-in channel is unavailable.');
  return {type:'phone',value:body.phone,channel:body.channel};
 }
 if(typeof body.email!=='string'||body.email.length>254||!/^\S+@[^\s@]+\.[^\s@]+$/.test(body.email.trim())||body.channel!==undefined)throw new ApiError(400,'invalid_email','Enter an email address.');
 return {type:'email',value:body.email.trim().toLowerCase(),channel:'email'};
}
async function query(env,sql,...values){
 try{return await first(env,sql,...values);}
 catch(error){
  if(error instanceof ApiError)throw error;
  const message=String(error?.message??'');
  if(message.includes('identity_already_exists'))throw new ApiError(409,'identity_already_exists','This identity already has an account. Sign in to that account separately.');
  if(message.includes('guest_upgrade_busy'))throw new ApiError(409,'guest_upgrade_busy','Check the existing request before requesting another code.');
  if(/guest_session_required|guest_challenge_required|verified_identity_required|verified_identity_mismatch|invalid_session/.test(message))throw new ApiError(403,'guest_challenge_required','This guest verification is no longer available.');
  throw unknown();
 }
}
async function guest(request,env,{allowConverted=false}={}){
 enabled(env);
 const verified=await verifyToken(env,bearer(request),{allowAnonymous:true,allowAnonymousTransition:allowConverted});
 if(verified.claims.is_anonymous!==true||!allowConverted&&verified.user.is_anonymous!==true)throw new ApiError(403,'guest_session_required','Open a guest session first.');
 env.DB.setClaims(verified.claims);
 await query(env,'SELECT private.guest_auth_session(?) AS actor',allowConverted);
 return verified;
}
export async function guestResponseSession(env,data){
 enabled(env);
 if(!data||typeof data.refresh_token!=='string'||!data.refresh_token||data.refresh_token.length>4096)throw unavailable();
 const verified=await verifyToken(env,data.access_token,{allowAnonymous:true});
 if(verified.user.is_anonymous!==true||verified.claims.is_anonymous!==true)throw unavailable();
 env.DB.setClaims(verified.claims);
 await query(env,'SELECT private.guest_auth_session(false) AS actor');
 // Only the explicit guest shape leaves this route. No user metadata, roles,
 // principal link, device enrollment or financial object is created.
 return {access_token:data.access_token,refresh_token:data.refresh_token,token_type:'bearer',expires_at:verified.claims.exp,
  expires_in:Math.max(1,verified.claims.exp-Math.floor(Date.now()/1000)),user:{id:verified.user.id,auth_user_id:verified.user.id,
   aud:'authenticated',role:'authenticated',is_anonymous:true,app_metadata:{provider:'anonymous',capabilities:['public_read']},user_metadata:{}}};
}
async function startGuest(env,body){
 enabled(env);cleanBody(body,['surface','captcha_token']);if(body.surface!=='member')throw new ApiError(400,'invalid_surface','Guest access is for members.');captcha(body);
 const data=await authRequest(env,'/signup',{body:{gotrue_meta_security:{captcha_token:body.captcha_token}}});
 return json(await guestResponseSession(env,data));
}
async function beginUpgrade(request,env,body){
 cleanBody(body,['surface','phone','email','channel','captcha_token']);captcha(body);
 if(env.AUTH_MEMBER_REGISTRATION_ENABLED!=='true')throw new ApiError(403,'registration_unavailable','Account registration is unavailable.');
 const original=await guest(request,env),identity=target(body,env),challenge=id();
 await query(env,'SELECT private.guest_upgrade_begin(?::uuid,?,?,?) AS challenge',challenge,identity.type,identity.value,identity.channel);
 let delivery='accepted';
 try{
  const user=await authRequest(env,'/user',{method:'PUT',token:original.token,body:{[identity.type]:identity.value,...(identity.type==='phone'?{channel:identity.channel}:{}),gotrue_meta_security:{captcha_token:body.captcha_token}}});
  // Autoconfirm cannot be used as an identity verification shortcut. A provider
  // configured that way leaves this operation unconfirmed and grants no member.
  if(user?.id!==original.user.id||user.is_anonymous!==true)throw unknown();
 }catch(error){
  delivery=error instanceof ApiError&&error.status<500?'rejected':'unknown';
  await query(env,'SELECT private.guest_upgrade_delivery(?::uuid,?)',challenge,delivery);
  if(delivery==='rejected')throw error;
 }
 if(delivery==='accepted')await query(env,'SELECT private.guest_upgrade_delivery(?::uuid,?)',challenge,delivery);
 return json({challenge_id:challenge,request_id:challenge,retry_after:60,expires_in:300,channel:identity.channel,delivery_status:delivery});
}
function confirmedIdentity(verified,challenge){
 const user=verified.user;
 const actual=challenge.identity_type==='email'?(user.email_confirmed_at?user.email?.toLowerCase():null):
  (user.phone_confirmed_at?'+'+String(user.phone??'').replace(/^\+/,''):null);
 return user.id===challenge.auth_user_id&&user.is_anonymous===false&&verified.claims.is_anonymous===false&&actual===challenge.identity_value;
}
async function finishUpgrade(env,data,challenge,project){
 const verified=await verifyToken(env,data.access_token);
 if(!confirmedIdentity(verified,challenge)||typeof data.refresh_token!=='string'||!data.refresh_token||data.refresh_token.length>4096){
  if(typeof data?.access_token==='string')await authRequest(env,'/logout?scope=local',{token:data.access_token}).catch(()=>{});
  throw new ApiError(403,'verified_identity_mismatch','The verified identity does not match this guest request.');
 }
 env.DB.setClaims(verified.claims);
 await query(env,'SELECT private.guest_upgrade_finish(?::uuid,?::uuid) AS result',challenge.id,challenge.verification_operation);
 // Existing member/admin identities are never silently merged into a guest.
 const actor=await project(env,verified,{surface:'member',rejectExistingIdentity:true,expectedAuthUserId:challenge.auth_user_id});
 return json({...data,user:actor.user});
}
async function verifyUpgrade(request,env,body,project){
 cleanBody(body,['surface','phone','email','channel','code','challenge_id','captcha_token']);captcha(body);
 if(typeof body.code!=='string'||!/^\d{6}$/.test(body.code))throw new ApiError(400,'invalid_credentials','Enter the verification code.');
 const original=await guest(request,env),operation=id(),challengeId=uuid(body.challenge_id,'challenge_id');
 const row=await query(env,'SELECT private.guest_upgrade_claim(?::uuid,?::uuid) AS challenge',challengeId,operation),challenge=row?.challenge;
 if(!challenge||challenge.auth_user_id!==original.user.id)throw unknown();
 let data;
 try{
  data=await authRequest(env,'/verify',{token:original.token,body:{[challenge.identity_type]:challenge.identity_value,token:body.code,
   type:challenge.identity_type==='email'?'email_change':'phone_change',gotrue_meta_security:{captcha_token:body.captcha_token}}});
 }catch(error){
  const state=error instanceof ApiError&&error.status<500?'rejected':'unknown';
  await query(env,'SELECT private.guest_upgrade_failure(?::uuid,?::uuid,?)',challengeId,operation,state);
  if(state==='unknown')throw unknown();
  // Only this explicit provider rejection authorizes the client to submit a
  // code again. A later projection/collision error is an unknown mutation.
  throw new ApiError(error.status,'guest_otp_rejected','The verification code was rejected.');
 }
 try{return await finishUpgrade(env,data,challenge,project);}
 catch(error){
  env.DB.setClaims(original.claims);
  await query(env,'SELECT private.guest_upgrade_failure(?::uuid,?::uuid,?)',challengeId,operation,'unknown').catch(()=>{});
  if(error instanceof ApiError&&error.status<500)throw error;throw unknown();
 }
}
async function reconcileUpgrade(request,env,body,project){
 cleanBody(body,['challenge_id','refresh_token']);
 if(typeof body.refresh_token!=='string'||!body.refresh_token||body.refresh_token.length>4096)throw new ApiError(400,'invalid_request','A retained session is required.');
 const challengeId=uuid(body.challenge_id,'challenge_id');
 // The retained access token may have expired. Refresh first, verify the newly
 // issued JWT through GoTrue, and bind its native session in SQL. Never decode
 // an expired bearer as proof, or accept another login for the same Auth UUID.
 const data=await authRequest(env,'/token?grant_type=refresh_token',{body:{refresh_token:body.refresh_token}});
 const fresh=await verifyToken(env,data.access_token,{allowAnonymous:true});
 if(typeof data.refresh_token!=='string'||!data.refresh_token||data.refresh_token.length>4096)throw unknown();
 env.DB.setClaims(fresh.claims);
 const row=await query(env,'SELECT private.guest_upgrade_recovery_read(?::uuid) AS challenge',challengeId),challenge=row?.challenge;
 if(!challenge||challenge.auth_user_id!==fresh.user.id||challenge.initiating_session_id!==fresh.claims.session_id)throw unknown();
 // A pending response retains the refreshed credential in the protected
 // recovery journal only. It does not install a member or permit code replay.
 const pending=()=>json({upgrade_status:'unconfirmed',challenge_id:challenge.id,auth_user_id:challenge.auth_user_id,
  initiating_session_id:challenge.initiating_session_id,recovery_refresh_token:data.refresh_token});
 if(!confirmedIdentity(fresh,challenge))return pending();
 try{return await finishUpgrade(env,data,challenge,project);}
 catch{return pending();}
}
export async function handleGuestAuth(request,env,body,project){
 const path=new URL(request.url).pathname;
 if(path==='/v1/auth/anonymous')return startGuest(env,body);
 if(path==='/v1/auth/upgrade/otp')return beginUpgrade(request,env,body);
 if(path==='/v1/auth/upgrade/verify')return verifyUpgrade(request,env,body,project);
 if(path==='/v1/auth/upgrade/reconcile')return reconcileUpgrade(request,env,body,project);
 return null;
}
