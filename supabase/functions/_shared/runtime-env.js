export const COLLECT_PROJECT_REF='rrlduytparvsjfmegalh';
export const COLLECT_SUPABASE_ORIGIN='https://'+COLLECT_PROJECT_REF+'.supabase.co';
function field(env,key){if(!Object.hasOwn(env,key))return null;const v=env[key];if(typeof v!=='string'||!v.trim()||v!==v.trim())throw new Error('Invalid '+key);return v;}
function dictionary(env,key){const raw=field(env,key);if(raw===null)return null;let object;try{object=JSON.parse(raw);}catch{throw new Error('Invalid '+key);}if(!object||Array.isArray(object)||typeof object!=='object'||typeof object.default!=='string'||!object.default||object.default!==object.default.trim())throw new Error('Invalid '+key);return object.default;}
function key(value,type,fixture){if(typeof value!=='string'||value.length<8||value.length>16384||/[\s\x00-\x1f]/.test(value))throw new Error('Missing configured '+type+' key');if(!fixture&&!new RegExp('^sb_'+type+'_[A-Za-z0-9_-]+$').test(value)&&!/^eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(value))throw new Error('Invalid configured '+type+' key');return value;}
export function normalizeRuntimeEnv(input){
 const env={...input},url=field(env,'SUPABASE_URL'),database=field(env,'COLLECT_DATABASE_URL')??field(env,'SUPABASE_DB_URL');
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
 if(!fixture){
  if(url!==COLLECT_SUPABASE_ORIGIN)throw new Error('Unexpected Supabase project');
  const direct=db.hostname==='db.'+COLLECT_PROJECT_REF+'.supabase.co',pooler=db.hostname.endsWith('.pooler.supabase.com')&&decodeURIComponent(db.username).endsWith('.'+COLLECT_PROJECT_REF);
  if((!direct&&!pooler)||db.pathname!=='/postgres'||!['','5432','6543'].includes(db.port))throw new Error('Database project identity mismatch');
 }
 db.search='';
 const publicDefault=dictionary(env,'SUPABASE_PUBLISHABLE_KEYS'),secretDefault=dictionary(env,'SUPABASE_SECRET_KEYS');
 const publicKey=field(env,'SUPABASE_PUBLISHABLE_KEY')??publicDefault??field(env,'SUPABASE_ANON_KEY');
 const serverKey=field(env,'SUPABASE_SECRET_KEY')??secretDefault??field(env,'SUPABASE_SERVICE_ROLE_KEY');
 env.COLLECT_DATABASE_URL=db.href;env.SUPABASE_PUBLISHABLE_KEY=key(publicKey,'publishable',fixture);env.SUPABASE_SECRET_KEY=key(serverKey,'secret',fixture);env.SUPABASE_SERVICE_ROLE_KEY=env.SUPABASE_SECRET_KEY;
 return env;
}

export function isGoogleProviderNavigation(request){return request.method==='GET'&&new URL(request.url).pathname==='/v1/auth/google/callback'&&request.headers.get('Origin')===COLLECT_SUPABASE_ORIGIN&&request.headers.get('Sec-Fetch-Mode')==='navigate'&&request.headers.get('Sec-Fetch-Dest')==='document';}
