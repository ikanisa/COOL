import {ApiError} from './domain/core.js';
import {MANAGED_SUPABASE_ORIGIN} from './deployment-profile.js';

export const LEGACY_ADMIN_OWNER_EMAIL = 'info@ikanisa.com';

export function adminCookieToken(request) {
  const name = '__Host-collect_admin=';
  const cookies = (request.headers.get('Cookie') ?? '').split(';').map(value => value.trim())
    .filter(value => value.startsWith(name));
  if (cookies.length !== 1) return null;
  const token = cookies[0].slice(name.length);
  return /^[a-f0-9]{64}$/.test(token) ? token : null;
}

// These two Workers terminate their own host-only Admin cookies. The immutable
// managed profile still identifies the database, member API and provider callbacks.
const managedAdminProfile='55ea350d7bf9ddef3e98022952bfe179da6216d52051ae0f4d6457d884ed1c61';
const managedBrowsers=['https://platform-admin.collect.ikanisa.com','https://admin-supabase-qa.collect.ikanisa.com'];
function hasManagedBrowserHosts(env){
 return env.COLLECT_DEPLOYMENT_PROFILE_SHA256===managedAdminProfile&&typeof env.COLLECT_DEPLOYMENT_PROFILE==='string'&&
  env.APP_ENVIRONMENT==='production'&&env.SUPABASE_URL===MANAGED_SUPABASE_ORIGIN&&env.ADMIN_ORIGIN===MANAGED_SUPABASE_ORIGIN;
}
export function isManagedAdminBrowserOrigin(env,origin){
 return hasManagedBrowserHosts(env)&&managedBrowsers.includes(origin);
}
// A challenge embedded by an Admin host is the only member-side document
// that may receive that host as its parent. Other member routes keep their profile.
export function managedAdminChallengeParent(request,env){
 const url=new URL(request.url);
 if(url.pathname!=='/v1/security/challenge'||!['GET','HEAD','OPTIONS'].includes(request.method))return null;
 if(request.method==='OPTIONS'&&!['GET','HEAD'].includes(request.headers.get('Access-Control-Request-Method')))return null;
 const parents=url.searchParams.getAll('parent_origin'),origin=request.headers.get('Origin');
 if(parents.length!==1||!isManagedAdminBrowserOrigin(env,parents[0])||(origin!==null&&origin!==parents[0]))return null;
 return parents[0];
}
export function adminBrowserOrigins(env){
 const configured=(env.ADMIN_ORIGINS??env.ADMIN_ORIGIN??'').split(',').map(v=>v.trim()).filter(Boolean);
 return hasManagedBrowserHosts(env)?[...new Set([...configured,...managedBrowsers])]:configured;
}
export function adminSessionOriginMatches(request,env,profile,account){
 const origin=request.headers.get('Origin');
 return origin!==null&&origin===account.origin&&(origin===profile.admin_origin||
  profile.admin_origin===MANAGED_SUPABASE_ORIGIN&&isManagedAdminBrowserOrigin(env,origin));
}
export function validateAdminOrigin(request,env) {
 const allowed=adminBrowserOrigins(env);
 if(!allowed.length||allowed.some(v=>{try{const u=new URL(v);return u.origin!==v||u.protocol!=='https:';}catch{return true;}}))throw new ApiError(503,'admin_origin_unconfigured','Admin origin is not configured.');
 const origin=request.headers.get('Origin'),mutating=!['GET','HEAD','OPTIONS'].includes(request.method);
 if(new URL(request.url).protocol!=='https:'||request.headers.get('Sec-Fetch-Site')==='cross-site'||origin&&!allowed.includes(origin)||mutating&&(!origin||!allowed.includes(origin)||request.headers.get('X-Collect-Requested-With')!=='collect-admin'||!/^application\/json(?:;|$)/i.test(request.headers.get('Content-Type')??'')))throw new ApiError(403,'origin_rejected','Open the configured Admin website to continue.');
 return origin??(allowed.includes(new URL(request.url).origin)?new URL(request.url).origin:null);
}
