// Mirrors the pinned upstream self-hosted key contract using Node's built-in
// crypto. Only the named new 0600 file receives secrets; nothing is printed.
import {generateKeyPairSync,randomBytes,randomUUID,createHash,createHmac,sign} from 'node:crypto';
import {writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
const b64=value=>Buffer.from(typeof value==='string'?value:JSON.stringify(value)).toString('base64url');
export function generateDeploymentKeys(){
 const jwtSecret=randomBytes(48).toString('base64url'),{privateKey}=generateKeyPairSync('ec',{namedCurve:'P-256'}),jwk=privateKey.export({format:'jwk'}),kid=randomUUID();
 const common={kty:'EC',kid,use:'sig',alg:'ES256',ext:true,crv:jwk.crv,x:jwk.x,y:jwk.y};
 const oct={kty:'oct',k:Buffer.from(jwtSecret).toString('base64url'),alg:'HS256'};
 const now=Math.floor(Date.now()/1000),payload=role=>({role,iss:'supabase',iat:now,exp:now+5*365*24*3600});
 const symmetric=role=>{const input=b64({alg:'HS256',typ:'JWT'})+'.'+b64(payload(role));return input+'.'+createHmac('sha256',jwtSecret).update(input).digest('base64url');};
 const asymmetric=role=>{const input=b64({alg:'ES256',typ:'JWT',kid})+'.'+b64(payload(role));return input+'.'+sign('SHA256',Buffer.from(input),{key:privateKey,dsaEncoding:'ieee-p1363'}).toString('base64url');};
 const opaque=prefix=>{const input=prefix+randomBytes(17).toString('base64url').slice(0,22);return input+'_'+createHash('sha256').update('supabase-self-hosted|'+input).digest('base64url').slice(0,8);};
 return {format:'collect.selfhost.private-keys.v1',POSTGRES_PASSWORD:randomBytes(32).toString('hex'),COLLECT_EDGE_PASSWORD:randomBytes(32).toString('hex'),COLLECT_SMS_EDGE_PASSWORD:randomBytes(32).toString('hex'),
  JWT_SECRET:jwtSecret,ANON_KEY:symmetric('anon'),SERVICE_ROLE_KEY:symmetric('service_role'),ANON_KEY_ASYMMETRIC:asymmetric('anon'),SERVICE_ROLE_KEY_ASYMMETRIC:asymmetric('service_role'),
  JWT_KEYS:JSON.stringify([{...common,key_ops:['sign','verify'],d:jwk.d},oct]),JWT_JWKS:JSON.stringify({keys:[{...common,key_ops:['verify']},oct]}),
  SUPABASE_PUBLISHABLE_KEY:opaque('sb_publishable_'),SUPABASE_SECRET_KEY:opaque('sb_secret_'),
  SECRET_KEY_BASE:randomBytes(48).toString('base64'),REALTIME_DB_ENC_KEY:randomBytes(8).toString('hex'),VAULT_ENC_KEY:randomBytes(16).toString('hex'),PG_META_CRYPTO_KEY:randomBytes(32).toString('base64'),
  DASHBOARD_USERNAME:'collect-operator',DASHBOARD_PASSWORD:randomBytes(32).toString('hex'),S3_PROTOCOL_ACCESS_KEY_ID:randomBytes(16).toString('hex'),S3_PROTOCOL_ACCESS_KEY_SECRET:randomBytes(32).toString('hex'),
  COLLECT_JOB_TOKEN:randomBytes(48).toString('base64url'),COLLECT_EMAIL_JOB_TOKEN:randomBytes(48).toString('base64url'),COLLECT_SMS_HOOK_SECRET:randomBytes(32).toString('base64'),
  ROOT_ADMIN_TOKEN:randomBytes(48).toString('base64url'),OTP_HMAC_KEY:randomBytes(48).toString('base64url'),CALLBACK_ENCRYPTION_KEY:randomBytes(32).toString('hex'),COLLECT_SMS_MAINTENANCE_TOKEN:randomBytes(48).toString('base64url'),
  // Existing encrypted business payloads require their ORIGINAL key. A fresh
  // deployment key never authorizes importing ciphertext from another source.
  DATA_KEY_ID:'collect-data-v1',DATA_ENCRYPTION_KEY:randomBytes(32).toString('base64'),SESSION_KEY_ID:'collect-session-v1',SESSION_ENCRYPTION_KEY:randomBytes(32).toString('base64'),
  LOGFLARE_PUBLIC_ACCESS_TOKEN:randomBytes(32).toString('base64url'),LOGFLARE_PRIVATE_ACCESS_TOKEN:randomBytes(32).toString('base64url')};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
 if(process.argv.length!==3||resolve(process.argv[2])!==process.argv[2])throw new Error('One new absolute private output path is required');
 await writeFile(process.argv[2],JSON.stringify(generateDeploymentKeys())+'\n',{flag:'wx',mode:0o600});
}
