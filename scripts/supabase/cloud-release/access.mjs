import {readFileSync,lstatSync,realpathSync,mkdirSync,writeFileSync,openSync,fsyncSync,closeSync} from 'node:fs';
import {dirname} from 'node:path';
import {execFileSync} from 'node:child_process';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import {loadProviderRoot} from '../managed-cloud-migrations/provider-ca.mjs';

export const PROJECT='rrlduytparvsjfmegalh';
const t7Mounts = ['/Volumes/T7/01 Projects/COLLECT/Project', '/Volumes/COLLECT-STAGING-20261109'];
function productionDirectories() {
 return t7Mounts.filter(mount => {
  const volume = lstatSync(mount, {throwIfNoEntry:false});
  const lock = lstatSync(mount+'/COLLECT-Production/.collect-operation-lock-v1/operation.lock', {throwIfNoEntry:false});
  return volume?.isDirectory() && lock?.isFile() && lock.dev === volume.dev &&
   volume.dev !== lstatSync(dirname(mount)).dev && (lock.mode & 0o777) === 0o600 &&
   lock.uid === process.getuid() && realpathSync(mount+'/COLLECT-Production') === mount+'/COLLECT-Production';
 }).map(mount => mount+'/COLLECT-Production');
}
const production = productionDirectories()[0] ?? t7Mounts[0]+'/COLLECT-Production';
export const ROOT=production+'/2026-11-17/burimunsi-live-cutover-001';
export const sha=value=>createHash('sha256').update(value).digest('hex');
export function record(name,value){
 if(!/^[a-z0-9_.-]+$/.test(name))throw Error('invalid_record_name');
 const current = productionDirectories();
 if(current.length!==1 || current[0]!==production)throw Error('t7_production_volume_required');
 mkdirSync(ROOT,{recursive:true,mode:0o700});
 const fd=openSync(ROOT+'/'+name,'wx',0o600);
 try{writeFileSync(fd,typeof value==='string'?value:JSON.stringify(value,null,2)+'\n');fsyncSync(fd);}finally{closeSync(fd);}
}
export async function connect(){
 const path='/Users/jeanbosco/Library/Application Support/Collect-Cloud-Recovery/production-db-credential-kq92ggw9/database-password.txt';
 const s=lstatSync(path);if(!s.isFile()||s.isSymbolicLink()||(s.mode&0o077)!==0||s.uid!==process.getuid())throw Error('private_credential_required');
 return connectWithPassword(readFileSync(path,'utf8').trim());
}
export async function connectWithPassword(password){
 const {Client}=createRequire(import.meta.url)('pg');
 const client=new Client({host:'aws-0-eu-north-1.pooler.supabase.com',port:5432,user:'postgres.'+PROJECT,
  password,database:'postgres',ssl:{ca:loadProviderRoot(),rejectUnauthorized:true},
  connectionTimeoutMillis:15000,statement_timeout:90000,application_name:'collect_cloud_release_20261117'});
 client.on('error',()=>{});await client.connect();
 const i=(await client.query("select session_user,current_user,current_database(),current_setting('server_version_num')::int as version,(select project_ref from private.collect_fence_control where singleton) project")).rows[0];
 if(i.session_user!=='postgres'||i.current_user!=='postgres'||i.current_database!=='postgres'||Math.floor(i.version/10000)!==17||i.project!==PROJECT){await client.end();throw Error('cloud_identity_mismatch');}
 return client;
}
export async function management(path,options={}){
 if(!/^[a-z0-9_/?=&.-]+$/i.test(path))throw Error('invalid_management_path');
 const token=execFileSync('/usr/bin/security',['find-generic-password','-s','Supabase CLI','-a','supabase','-w'],{encoding:'utf8'}).trim();
 const r=await fetch('https://api.supabase.com/v1/projects/'+PROJECT+'/'+path,{...options,headers:{Authorization:'Bearer '+token,...options.headers},redirect:'error',signal:AbortSignal.timeout(90000)});
 const bytes=Buffer.from(await r.arrayBuffer());
 if(!r.ok){const e=Error('management_request_failed_'+r.status);e.status=r.status;throw e;}
 return {status:r.status,bytes,json:()=>JSON.parse(bytes.toString('utf8'))};
}
