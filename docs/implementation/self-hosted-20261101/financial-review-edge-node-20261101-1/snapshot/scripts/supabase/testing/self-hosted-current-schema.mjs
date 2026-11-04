// Native qualification only. Applies the complete reviewed additive chain to a
// newly allocated, private, literal-loopback original16 fixture. No reset path.
import {readFile,readdir,realpath} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {createHash} from 'node:crypto';
import {EXACT_CURRENT16} from './curated-platform-fixture.mjs';
import {SELF_HOSTED_ADDITIONS} from './reviewed-self-hosted-migrations.mjs';

export const CURRENT_NATIVE_PROFILE='reviewed_current_self_hosted';
export const CURRENT_MIGRATION_NAMES=Object.freeze([...EXACT_CURRENT16,...Object.keys(SELF_HOSTED_ADDITIONS)]);
export const CURRENT_MIGRATION_COUNT=CURRENT_MIGRATION_NAMES.length;
export const CURRENT_ADDITIONS=Object.freeze(Object.keys(SELF_HOSTED_ADDITIONS));
const ROOT=resolve(import.meta.dirname,'../../..');
const need=(ok,code)=>{if(!ok)throw Error(code);};
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');

export async function reviewedCurrentMigrations(root=ROOT){
 need(await realpath(root)===root,'PHYSICAL_CURRENT_SOURCE_REQUIRED');
 const lock=JSON.parse(await readFile(join(root,'deploy/self-hosted/migrations.lock.json'),'utf8'));
 need(lock.format==='collect.selfhost.migrations.v1'&&lock.original_count===16&&
  CURRENT_MIGRATION_COUNT>=24&&JSON.stringify(lock.migrations.map(row=>row.name))===JSON.stringify(CURRENT_MIGRATION_NAMES),
  'EXACT_REVIEWED_CURRENT_CHAIN_REQUIRED');
 const names=(await readdir(join(root,'supabase/migrations'))).filter(name=>/^\d{14}_.*\.sql$/.test(name)).sort();
 need(JSON.stringify(names)===JSON.stringify(CURRENT_MIGRATION_NAMES),'UNREVIEWED_CURRENT_MIGRATION_REFUSED');
 const result=[];
 for(const item of lock.migrations){
  const path=join(root,'supabase/migrations',item.name);
  need(await realpath(path)===path,'PHYSICAL_CURRENT_MIGRATION_REQUIRED');
  const bytes=await readFile(path);
  need(sha(bytes)===item.sha256&&(!SELF_HOSTED_ADDITIONS[item.name]||SELF_HOSTED_ADDITIONS[item.name]===item.sha256),
   'REVIEWED_CURRENT_MIGRATION_CHANGED');
  result.push({name:item.name,sha256:item.sha256,sql:bytes.toString('utf8')});
 }
 return result;
}

export function validateCurrentFixtureDescriptor(value,{purpose}={}){
 need(value?.format==='collect.selfhost.fixture.v1'&&value.synthetic===true&&value.public_acceptance===false&&
  value.controller_initialized===true&&value.migration_count===16&&(!purpose||value.purpose===purpose)&&
  /^[a-f0-9]{64}$/.test(value.source_sha256),'FRESH_ORIGINAL16_DESCRIPTOR_REQUIRED');
 const target=new URL(value.url);
 need(target.protocol==='postgres:'&&target.hostname==='127.0.0.1'&&['55439','55443','55444','55445','55446','55447','55448','55449'].includes(target.port)&&
  target.username==='postgres'&&target.password&&!target.search&&!target.hash&&
  /^collect_selfhost_(backend|auth|notifications|recovery|gateway)_[a-f0-9]{24}_test$/.test(value.database)&&
  target.pathname==='/'+value.database,'OWNED_CURRENT_FIXTURE_REQUIRED');
 return target;
}

export async function installCurrentFixtureAdditions(owner,{root=ROOT}={}){
 const files=await reviewedCurrentMigrations(root);
 const [identity]=await owner.unsafe("SELECT current_user AS owner,session_user AS session,current_database() AS database,host(inet_server_addr()) AS host,inet_server_port() AS port,current_setting('server_version_num')::int/10000 AS major,(SELECT rolsuper OR rolbypassrls FROM pg_roles WHERE rolname=current_user) AS privileged");
 need(identity.owner==='postgres'&&identity.session==='postgres'&&!identity.privileged&&identity.host==='127.0.0.1'&&identity.major===17&&
  [55439,55443,55444,55445,55446,55447,55448,55449].includes(identity.port)&&
  /^collect_selfhost_(backend|auth|notifications|recovery|gateway)_[a-f0-9]{24}_test$/.test(identity.database),
  'OWNED_CURRENT_PG17_REQUIRED');
 const [prior]=await owner.unsafe("SELECT to_regclass('private.collect_fence_admission_archive') AS archive,to_regclass('private.guest_upgrade_challenges') AS guest,to_regnamespace('collect_sms') AS gateway,to_regclass('private.retention_row_plans') AS retention,to_regclass('private.collect_sms_fence_admissions') AS gateway_fence");
 need(Object.values(prior).every(value=>value===null),'FRESH_CURRENT_ADDITIONS_REQUIRED');
 // These are native GoTrue columns absent from the immutable historical Auth
 // double. They extend only this fresh synthetic database, never shipping SQL.
 await owner.unsafe('ALTER TABLE auth.users ADD COLUMN email_confirmed_at timestamptz; ALTER TABLE auth.users ADD COLUMN is_anonymous boolean NOT NULL DEFAULT false');
 for(const item of files.slice(16))await owner.unsafe(item.sql);
 const [installed]=await owner.unsafe("SELECT to_regclass('private.collect_fence_admission_archive') IS NOT NULL AND to_regclass('private.guest_upgrade_challenges') IS NOT NULL AND to_regclass('app.notification_email_job_dispatches') IS NOT NULL AND to_regclass('collect_sms.messages') IS NOT NULL AND to_regclass('private.collect_deployment_identity') IS NOT NULL AND to_regclass('private.retention_inventory_manifests') IS NOT NULL AND to_regclass('private.retention_row_plans') IS NOT NULL AND to_regclass('private.collect_sms_fence_admissions') IS NOT NULL AS complete");
 need(installed.complete===true,'CURRENT_SCHEMA_INSTALLATION_UNCONFIRMED');
 return {profile:CURRENT_NATIVE_PROFILE,migration_count:CURRENT_MIGRATION_COUNT,migrations:files.map(({name,sha256})=>({name,sha256})),
  synthetic_auth_columns:['email_confirmed_at','is_anonymous'],production_acceptance:false};
}
