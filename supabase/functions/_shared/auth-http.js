import {guardedFetch,noteUnknownEffect} from './application-fence.js';
import {ApiError} from './domain/core.js';
export async function authRequest(env, path, {method='POST',token=null,body=null,admin=false}={}) {
 const key=admin?env.SUPABASE_SERVICE_ROLE_KEY:env.SUPABASE_PUBLISHABLE_KEY;
 if(!env.SUPABASE_URL||!key)throw new ApiError(503,'auth_unavailable','Sign-in is not configured.');
 const response=await guardedFetch(env,'auth',env.SUPABASE_URL+'/auth/v1'+path,{method,redirect:'error',signal:AbortSignal.timeout(15000),headers:{apikey:key,...(token?{Authorization:'Bearer '+token}:admin&&!key.startsWith('sb_secret_')?{Authorization:'Bearer '+key}:{}),'Content-Type':'application/json'},...(body===null?{}:{body:JSON.stringify(body)})});
 // GoTrue logout succeeds with 204 and no JSON. Accept that contract only
 // for the existing authenticated POST logout paths; other empty replies fail.
 if(response.status===204&&response.ok&&method==='POST'&&
  (path==='/logout'||path==='/logout?scope=local'||path==='/logout?scope=global')&&
  typeof token==='string'&&token.length>0&&!/\s/.test(token))return {};
 let data;try{data=await response.json();}catch{noteUnknownEffect(env,'auth');throw new ApiError(503,'auth_unavailable','The identity service is unavailable.');}
 if(!response.ok&&response.status>=500)noteUnknownEffect(env,'auth');
 if(!response.ok)throw new ApiError([400,401,403,422,429].includes(response.status)?response.status:503,data.error_code??'auth_unavailable',response.status===429?'Too many attempts. Try again later.':'The identity request could not be verified.');
 return data;
}
export function claimsOf(token) {
 try {const parts=token.split('.');if(parts.length!==3)throw 0;const raw=parts[1].replace(/-/g,'+').replace(/_/g,'/');return JSON.parse(atob(raw));}catch{throw new ApiError(401,'invalid_session','Sign in again.');}
}
export async function verifyToken(env,token) {
 if(typeof token!=='string'||token.startsWith('sb_'))throw new ApiError(401,'invalid_session','A signed-in user token is required.');
 // getUser hits GoTrue. Decoding alone or verify_jwt at the gateway does not
 // prove that the bearer is an actual current user rather than an API key.
 const user=await authRequest(env,'/user',{method:'GET',token});
 const claims=claimsOf(token),now=Math.floor(Date.now()/1000);
 if(claims.sub!==user.id||claims.role!=='authenticated'||!(claims.aud==='authenticated'||Array.isArray(claims.aud)&&claims.aud.includes('authenticated'))||typeof claims.session_id!=='string'||!Number.isSafeInteger(claims.exp)||claims.exp<=now||claims.iss!==env.SUPABASE_URL+'/auth/v1')throw new ApiError(401,'invalid_session','Sign in again.');
 return {user,claims,token};
}
