import {resolveDeploymentProfile} from './deployment-profile.js';
export const COLLECT_PROJECT_REF='rrlduytparvsjfmegalh';
export const COLLECT_SUPABASE_ORIGIN='https://'+COLLECT_PROJECT_REF+'.supabase.co';
function field(env,key){if(!Object.hasOwn(env,key))return null;const v=env[key];if(typeof v!=='string'||!v.trim()||v!==v.trim())throw new Error('Invalid '+key);return v;}
function dictionary(env,key){const raw=field(env,key);if(raw===null)return null;let object;try{object=JSON.parse(raw);}catch{throw new Error('Invalid '+key);}if(!object||Array.isArray(object)||typeof object!=='object'||typeof object.default!=='string'||!object.default||object.default!==object.default.trim())throw new Error('Invalid '+key);return object.default;}
function key(value,type,fixture){if(typeof value!=='string'||value.length<8||value.length>16384||/[\s\x00-\x1f]/.test(value))throw new Error('Missing configured '+type+' key');if(!fixture&&!new RegExp('^sb_'+type+'_[A-Za-z0-9_-]+$').test(value)&&!/^eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(value))throw new Error('Invalid configured '+type+' key');return value;}
export function configurePublicRuntimeEnv(input){
 const env={...input},profile=resolveDeploymentProfile(env);
 if(env.COLLECT_DEPLOYMENT_PROFILE===undefined)return env;
 if(env.APP_ENVIRONMENT!==profile.environment&&!(env.APP_ENVIRONMENT==='test'&&profile.environment==='qualification'))throw new Error('Deployment environment mismatch');
 if(env.ADMIN_ORIGIN!==undefined&&env.ADMIN_ORIGIN!==profile.admin_origin)throw new Error('Admin origin does not match deployment');
 if(env.ADMIN_ORIGINS!==undefined&&env.ADMIN_ORIGINS!==profile.admin_origin)throw new Error('Admin origins do not match deployment');
 const allowed=[profile.admin_origin,profile.member_api_origin,profile.public_origin];
 if(env.ALLOWED_ORIGINS!==undefined&&env.ALLOWED_ORIGINS.split(',').some(v=>!allowed.includes(v)))throw new Error('Browser origin does not match deployment');
 env.ADMIN_ORIGIN=profile.admin_origin;env.ADMIN_ORIGINS=profile.admin_origin;env.ALLOWED_ORIGINS=[...new Set(allowed)].join(',');
 return env;
}
// Validate the database target independently of Supabase application keys.
// The signed SMS hook needs the same target policy but does not receive those keys.
function databaseTarget(env){
 const url=field(env,'SUPABASE_URL'),database=field(env,'COLLECT_DATABASE_URL')??field(env,'SUPABASE_DB_URL');
 if(!url||!database)throw new Error('Supabase origin and database must be configured');
 const origin=new URL(url),db=new URL(database),loopback=['127.0.0.1','localhost','::1','[::1]'].includes(db.hostname),fixture=env.APP_ENVIRONMENT==='test'&&loopback;
 if(origin.origin!==url||origin.protocol!=='https:'||origin.username||origin.password)throw new Error('Invalid Supabase origin');
 if(!['postgres:','postgresql:'].includes(db.protocol)||!db.username||!db.password||db.hash)throw new Error('Invalid database configuration');
 const options=[...db.searchParams];
 // Supabase injects sslmode=prefer. Accept its documented/default TLS hints only from
 // the reserved provider URL; never pass it to the driver. connection() still
 // enforces certificate verification for every non-loopback connection.
 const injected=field(env,'COLLECT_DATABASE_URL')===null;
 if(options.length>1||options.some(([name,value])=>name!=='sslmode'||!(value==='verify-full'||injected&&['require','prefer'].includes(value))))throw new Error('Database connection overrides are not permitted');
 const profile=resolveDeploymentProfile(env),explicit=env.COLLECT_DEPLOYMENT_PROFILE!==undefined,selfHosted=explicit&&profile.mode==='self_hosted';
 if(explicit&&url!==profile.supabase_origin)throw new Error('Unexpected Supabase project');
 if(!fixture){
  if(selfHosted){
   // The private Compose DNS name and least-privilege login are intentional.
   // Operator migrations/recovery use separate credentials, never this runtime.
   if(db.hostname!=='db'||db.pathname!=='/postgres'||!['','5432'].includes(db.port)||decodeURIComponent(db.username)!=='collect_edge')throw new Error('Database deployment identity mismatch');
   const ca=field(env,'COLLECT_DB_CA_PEM');
   if(!ca||ca.length>32768||!/^-----BEGIN CERTIFICATE-----\n[A-Za-z0-9+/=\n]+\n-----END CERTIFICATE-----$/.test(ca))throw new Error('Verified database CA required');
  }else{
   if(url!==COLLECT_SUPABASE_ORIGIN)throw new Error('Unexpected Supabase project');
   const direct=db.hostname==='db.'+COLLECT_PROJECT_REF+'.supabase.co',pooler=db.hostname.endsWith('.pooler.supabase.com')&&decodeURIComponent(db.username).endsWith('.'+COLLECT_PROJECT_REF);
   if((!direct&&!pooler)||db.pathname!=='/postgres'||!['','5432','6543'].includes(db.port))throw new Error('Database project identity mismatch');
  }
 }
 db.search='';
 return {url,db,fixture,selfHosted};
}
export function normalizeDatabaseTarget(input){
 return databaseTarget(configurePublicRuntimeEnv(input)).db.href;
}
export function normalizeRuntimeEnv(input){
 const env=configurePublicRuntimeEnv(input),{url,db,fixture,selfHosted}=databaseTarget(env);
 const issuer=field(env,'SUPABASE_AUTH_ISSUER');
 if(issuer!==null&&issuer!==url+'/auth/v1')throw new Error('Auth issuer must use the public Supabase origin');
 env.SUPABASE_AUTH_ISSUER=url+'/auth/v1';
 const internal=field(env,'SUPABASE_INTERNAL_URL');
 if(internal!==null&&internal!==url&&!(selfHosted&&internal==='http://api-gw:8000')&&!(fixture&&/^http:\/\/(?:127\.0\.0\.1|localhost):\d{1,5}$/.test(internal)))throw new Error('Unapproved internal Supabase origin');
 env.SUPABASE_INTERNAL_URL=internal??url;
 for(const name of ['AUTH_ANONYMOUS_ENABLED','AUTH_SMS_ENABLED','AUTH_WHATSAPP_ENABLED']){
  if(env[name]!==undefined&&!['true','false'].includes(env[name]))throw new Error('Invalid '+name);
 }
 const publicDefault=dictionary(env,'SUPABASE_PUBLISHABLE_KEYS'),secretDefault=dictionary(env,'SUPABASE_SECRET_KEYS');
 const publicKey=field(env,'SUPABASE_PUBLISHABLE_KEY')??publicDefault??field(env,'SUPABASE_ANON_KEY');
 const serverKey=field(env,'SUPABASE_SECRET_KEY')??secretDefault??field(env,'SUPABASE_SERVICE_ROLE_KEY');
 env.COLLECT_DATABASE_URL=db.href;env.SUPABASE_PUBLISHABLE_KEY=key(publicKey,'publishable',fixture);env.SUPABASE_SECRET_KEY=key(serverKey,'secret',fixture);env.SUPABASE_SERVICE_ROLE_KEY=env.SUPABASE_SECRET_KEY;
 return env;
}

export function isGoogleProviderNavigation(request,env={}){const origin=env.COLLECT_DEPLOYMENT_PROFILE!==undefined?resolveDeploymentProfile(env).supabase_origin:COLLECT_SUPABASE_ORIGIN;return request.method==='GET'&&new URL(request.url).pathname==='/v1/auth/google/callback'&&request.headers.get('Origin')===origin&&request.headers.get('Sec-Fetch-Mode')==='navigate'&&request.headers.get('Sec-Fetch-Dest')==='document';}
