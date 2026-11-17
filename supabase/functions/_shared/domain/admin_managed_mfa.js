import {ApiError} from './core.js';

// This adapter is deliberately not registered as a route. It is a narrow
// boundary for the existing Admin BFF, not a member/native MFA API. The
// caller must provide the current cookie-bound database guard and a durable
// two-phase session-upgrade implementation before it can be exposed.
const unavailable=()=>new ApiError(410,'mfa_not_available','Verify your email to confirm sensitive changes.');
const unknown=()=>new ApiError(503,'mfa_operation_unknown','The authenticator result could not be confirmed. Recheck your setup or sign-in before trying again.');
const denied=()=>new ApiError(403,'mfa_admin_denied','This authenticator action is unavailable.');
const invalid=()=>new ApiError(400,'invalid_mfa_request','Check the authenticator request and try again.');
const uuid=v=>typeof v==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
const object=v=>v!==null&&typeof v==='object'&&!Array.isArray(v);
const exact=(v,fields)=>object(v)&&Object.keys(v).length===fields.length&&fields.every(k=>Object.hasOwn(v,k));
const time=()=>Math.floor(Date.now()/1000);

function factorsOf(user){
 const factors=user?.factors??[];
 if(!Array.isArray(factors)||factors.length>128)throw unknown();
 const seen=new Set(),out=[];
 for(const f of factors){
  if(!object(f)||!uuid(f.id)||typeof f.factor_type!=='string'||!['verified','unverified'].includes(f.status)||seen.has(f.id.toLowerCase()))throw unknown();
  seen.add(f.id.toLowerCase());
  if(f.factor_type!=='totp')continue;
  const name=f.friendly_name??'Authenticator';
  if(typeof name!=='string'||!name.trim()||name.length>64||/[\x00-\x1f\x7f]/.test(name))throw unknown();
  out.push({id:f.id,factor_type:'totp',status:f.status,friendly_name:name});
 }
 return out;
}

function owned(user,id){
 const matches=factorsOf(user).filter(v=>v.id===id);
 if(matches.length!==1)throw denied();
 return matches[0];
}

function enrollment(result,email,name){
 if(!object(result)||!uuid(result.id)||result.type!=='totp'||result.friendly_name!==name||
    result.status!==undefined&&result.status!=='unverified'||!object(result.totp)||
    typeof result.totp.secret!=='string'||!/^[A-Z2-7]{32}$/.test(result.totp.secret)||
    typeof result.totp.uri!=='string'||result.totp.uri.length>2048)throw unknown();
 let supplied,label;
 try{supplied=new URL(result.totp.uri);label=decodeURIComponent(supplied.pathname.slice(1));}catch{throw unknown();}
 const expected={secret:result.totp.secret,issuer:'Collect',algorithm:'SHA1',digits:'6',period:'30'};
 if(supplied.protocol!=='otpauth:'||supplied.hostname!=='totp'||supplied.username||supplied.password||supplied.port||supplied.hash||
    supplied.pathname.split('/').length!==2||label!==`Collect:${email}`||
    [...supplied.searchParams.keys()].some(k=>!Object.hasOwn(expected,k))||
    Object.entries(expected).some(([k,v])=>{const found=supplied.searchParams.getAll(k);return found.length>1||found.length===1&&found[0]!==v||['secret','issuer'].includes(k)&&found.length!==1;}))throw unknown();
 const uri=new URL('otpauth://totp/'+encodeURIComponent(`Collect:${email}`));
 for(const [key,value] of Object.entries(expected))uri.searchParams.set(key,value);
 return {id:result.id,factor_type:'totp',status:'unverified',friendly_name:name,totp:{secret:result.totp.secret,uri:uri.href}};
}

function challenge(result,factor,now){
 if(!object(result)||!uuid(result.id)||result.type!=='totp'||
    result.challenge_id!==undefined&&result.challenge_id!==result.id||
    result.factor_id!==undefined&&result.factor_id!==factor||
    !Number.isSafeInteger(result.expires_at)||result.expires_at<=now||result.expires_at>now+600)throw unknown();
 return {id:result.id,challenge_id:result.id,factor_id:factor,expires_at:result.expires_at};
}

function verifiedIdentity(verified,account){
 if(!object(verified)||!object(verified.user)||!object(verified.claims)||verified.claims.role!=='authenticated'||
    verified.user.is_anonymous===true||verified.claims.is_anonymous===true||
    verified.user.id!==account.auth_user_id||verified.claims.session_id!==account.auth_session_id||
    verified.claims.sub!==account.auth_user_id||typeof verified.user.email!=='string'||
    verified.user.email.toLowerCase()!==account.email||!verified.user.email_confirmed_at)throw denied();
 return verified;
}

/**
 * `provider` must be the guarded, current local GoTrue transport. `guard` must
 * recheck the exact cookie, active Admin identity, role, grant, origin and
 * freshness in the database, including after any provider mutation. `claim`
 * exclusively leases the original BFF session before provider verification;
 * `release` may release it only after a definite provider rejection. `stage`
 * must prove and durably stage an AAL2 cookie change without invalidating the
 * old AAL1 cookie until the browser acknowledges the new one. If any port is
 * absent, this adapter is unavailable; there is no permissive fallback.
 */
export async function adminManagedMfa({enabled,account,operation,body,provider,guard,claim,release,stage,clock=time}){
 if(enabled!==true)throw unavailable();
 if(!object(account)||!['owner','admin','staff'].includes(account.role)||!uuid(account.auth_user_id)||
    !uuid(account.auth_session_id)||typeof account.principal_id!=='string'||!account.principal_id||
    typeof account.email!=='string'||account.email!==account.email.toLowerCase()||
    !object(account.supabaseTokens)||typeof account.supabaseTokens.access_token!=='string'||
    typeof provider?.identity!=='function'||typeof provider?.request!=='function'||typeof guard!=='function')throw denied();
 if(!['list','enroll','challenge','verify','cancel'].includes(operation))throw invalid();
 const shapes={list:[],enroll:['friendly_name','factor_type'],challenge:['factor_id'],verify:['factor_id','challenge_id','code','verification_id'],cancel:['factor_id']};
 if(!exact(body,shapes[operation]))throw invalid();
 if(operation==='enroll'&&(body.friendly_name!=='Collect Admin'||body.factor_type!=='totp'))throw invalid();
 if(['challenge','verify','cancel'].includes(operation)&&!uuid(body.factor_id))throw invalid();
 if(operation==='verify'&&(!uuid(body.challenge_id)||typeof body.code!=='string'||!/^\d{6}$/.test(body.code)||typeof body.verification_id!=='string'||!/^[a-f0-9]{64}$/.test(body.verification_id)))throw invalid();
 if(operation==='verify'&&[claim,release,stage].some(v=>typeof v!=='function'))throw unavailable();
 const fresh=operation==='enroll'||operation==='cancel';
 await guard({fresh,operation,factorId:body.factor_id??null});
 const before=verifiedIdentity(await provider.identity(account.supabaseTokens.access_token),account);
 const factor=['challenge','verify','cancel'].includes(operation)?owned(before.user,body.factor_id):null;
 if(operation==='cancel'&&factor.status!=='unverified')throw denied();
 let result;
 if(operation==='list')result={id:account.principal_id,factors:factorsOf(before.user)};
 else if(operation==='enroll'){
  const response=await provider.request('/factors',{method:'POST',token:account.supabaseTokens.access_token,body:{factor_type:'totp',friendly_name:'Collect Admin',issuer:'Collect'}});
  result=enrollment(response,account.email,'Collect Admin');
 }else if(operation==='challenge'){
  const response=await provider.request(`/factors/${factor.id}/challenge`,{method:'POST',token:account.supabaseTokens.access_token,body:{}});
  result=challenge(response,factor.id,clock());
 }else if(operation==='cancel'){
  const response=await provider.request(`/factors/${factor.id}`,{method:'DELETE',token:account.supabaseTokens.access_token});
  if(!object(response)||response.id!==factor.id||response.factor_type!==undefined&&response.factor_type!=='totp'||response.type!==undefined&&response.type!=='totp'||response.status!==undefined&&response.status!=='revoked')throw unknown();
  result={id:factor.id,factor_type:'totp',status:'revoked'};
 }else{
  const lease=await claim({account,factorId:factor.id,challengeId:body.challenge_id,verificationId:body.verification_id,code:body.code});
  if(!object(lease)||typeof lease.id!=='string'||!Number.isSafeInteger(lease.version))throw unknown();
  let tokens;
  try{
   tokens=await provider.request(`/factors/${factor.id}/verify`,{method:'POST',token:account.supabaseTokens.access_token,body:{challenge_id:body.challenge_id,code:body.code}});
  }catch(error){
   // A definite rejected verification did not issue tokens. Unknown provider
   // outcomes retain the lease for the existing bounded recovery path.
   if(error instanceof ApiError&&[400,401,403,422,429].includes(error.status))await release({account,lease,factorId:factor.id,challengeId:body.challenge_id,verificationId:body.verification_id});
   throw error;
  }
  try{
   if(!object(tokens)||typeof tokens.access_token!=='string'||typeof tokens.refresh_token!=='string'||!tokens.refresh_token||tokens.refresh_token.length>4096)throw unknown();
   const verified=verifiedIdentity(await provider.identity(tokens.access_token),account);
   if(verified.claims.aal!=='aal2'||owned(verified.user,factor.id).status!=='verified')throw unknown();
   // The SQL staging port rechecks current access with this exact lease after
   // the provider request. A separate guard cannot run while the lease is held.
   const staged=await stage({account,verified,tokens,factorId:factor.id,challengeId:body.challenge_id,verificationId:body.verification_id,lease});
   const cookie=typeof staged?.cookie==='string'?/^__Host-collect_admin=[a-f0-9]{64}; Path=\/; HttpOnly; SameSite=Strict; Max-Age=([1-9][0-9]{0,7}); Secure$/.exec(staged.cookie):null;
   if(!object(staged)||staged.ok!==true||!cookie||Number(cookie[1])>34560000)throw unknown();
   return {ok:true,cookie:staged.cookie};
  }catch{
   // Once GoTrue may have verified the factor, even a later 401 or lost
   // staging response is uncertain. Never turn that into local sign-out.
   throw unknown();
  }
 }
 await guard({fresh,operation,factorId:body.factor_id??null});
 return result;
}
