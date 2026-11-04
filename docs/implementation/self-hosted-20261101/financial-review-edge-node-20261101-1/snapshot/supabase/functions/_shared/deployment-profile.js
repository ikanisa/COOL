// Public configuration identity, never a credential or an approval. This module
// runs in both the Edge runtime and the static Admin proxy without Node imports.
export const PROFILE_FORMAT='collect.deployment.v1';
export const MANAGED_SUPABASE_ORIGIN='https://rrlduytparvsjfmegalh.supabase.co';
const FIELDS=['admin_origin','environment','format','google_callback_origin','id','member_api_origin','mode','public_origin','supabase_origin'];
export function normalizeHttpsOrigin(value){
 if(typeof value!=='string'||!value||value.length>2048||/[\s\\\x00-\x1f]/.test(value))throw new Error('Invalid deployment origin');
 let u;try{u=new URL(value);}catch{throw new Error('Invalid deployment origin');}
 if(u.protocol!=='https:'||u.username||u.password||u.port||!['','/'].includes(u.pathname)||u.search||u.hash||!u.hostname.includes('.')||u.hostname.endsWith('.')||/^[\d.]+$/.test(u.hostname)||u.hostname.includes(':')||u.hostname.length>253||u.hostname.split('.').some(x=>! /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(x)))throw new Error('Invalid deployment origin');
 return u.origin;
}
export function canonicalProfile(profile){return JSON.stringify(Object.fromEntries(FIELDS.map(k=>[k,profile[k]])));}
export function validateDeploymentProfile(profile){
 if(!profile||Array.isArray(profile)||typeof profile!=='object'||Object.keys(profile).sort().join('|')!==FIELDS.join('|')||FIELDS.some(k=>typeof profile[k]!=='string')||profile.format!==PROFILE_FORMAT||! /^[a-z][a-z0-9-]{0,62}$/.test(profile.id)||!['managed','self_hosted'].includes(profile.mode)||!['production','qualification'].includes(profile.environment))throw new Error('Invalid public deployment profile');
 for(const k of FIELDS)if(k.endsWith('_origin')&&normalizeHttpsOrigin(profile[k])!==profile[k])throw new Error('Noncanonical deployment origin');
 if(![profile.member_api_origin,profile.admin_origin].includes(profile.google_callback_origin))throw new Error('Unapproved Google callback origin');
 if(profile.mode==='managed'&&profile.supabase_origin!==MANAGED_SUPABASE_ORIGIN)throw new Error('Unexpected managed project');
 return Object.freeze({...profile});
}
export function legacyDeploymentProfile(qualification=false){
 const admin=qualification?'https://admin-supabase-qa.collect.ikanisa.com':'https://platform-admin.collect.ikanisa.com';
 return Object.freeze({format:PROFILE_FORMAT,id:qualification?'collect-managed-qualification':'collect-managed-production',mode:'managed',environment:qualification?'qualification':'production',supabase_origin:MANAGED_SUPABASE_ORIGIN,member_api_origin:admin,admin_origin:admin,public_origin:'https://collect.ikanisa.com',google_callback_origin:admin});
}
export function resolveDeploymentProfile(env){
 const raw=env.COLLECT_DEPLOYMENT_PROFILE,digest=env.COLLECT_DEPLOYMENT_PROFILE_SHA256;
 if(raw===undefined&&digest===undefined)return legacyDeploymentProfile(env.APP_ENVIRONMENT==='qualification');
 if(typeof raw!=='string'||!raw||new TextEncoder().encode(raw).length>8192||typeof digest!=='string'||! /^[a-f0-9]{64}$/.test(digest))throw new Error('Deployment profile and SHA256 required');
 let parsed;try{parsed=JSON.parse(raw);}catch{throw new Error('Invalid public deployment profile');}
 const profile=validateDeploymentProfile(parsed);
 // Require canonical serialization. Besides cross-runtime stability, this
 // refuses duplicate JSON keys that JSON.parse would otherwise silently accept.
 if(raw!==canonicalProfile(profile))throw new Error('Deployment profile must be canonical JSON');
 return profile;
}
export async function verifyDeploymentProfile(env){
 const profile=resolveDeploymentProfile(env);
 if(env.COLLECT_DEPLOYMENT_PROFILE!==undefined){
  const bytes=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(canonicalProfile(profile)));
  const digest=Array.from(new Uint8Array(bytes),b=>b.toString(16).padStart(2,'0')).join('');
  if(digest!==env.COLLECT_DEPLOYMENT_PROFILE_SHA256)throw new Error('Deployment profile SHA256 mismatch');
 }
 return profile;
}
