// Offline compiler only. It never loads credentials, connects to a database,
// runs SQL, invokes a CLI, writes a file, or authorizes a production change.
import {createHash} from 'node:crypto';
import {canonicalProfile,validateDeploymentProfile} from '../../../supabase/functions/_shared/deployment-profile.js';

export const ORIGINAL_SHA256='16e8d236686789397edbfe71f6e6a7e13367ba22c0fdfabf0ca322e03779bd65';
export const PROJECT_REF='rrlduytparvsjfmegalh';
export const SCHEDULER_SHA256='5dc44f65fb52562bc6a0391a7f7b7d050c333c2276f98097943d9c1e340d926d';
export const TRUST='trust-provider-administrators-and-all-owner-actors-v1';
export const HISTORY_DIGEST_SQL=`encode(sha256(convert_to(coalesce(jsonb_agg(jsonb_build_array(version,name,statements) ORDER BY version)::text,'[]'),'UTF8')),'hex')`;
const oldGuard=` IF EXISTS(SELECT 1 FROM pg_roles r WHERE NOT r.rolsuper AND r.rolname<>'postgres'
   AND pg_has_role(r.oid,'postgres'::regrole,'MEMBER'))
 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='managed_deployment_owner_role_preimage';END IF;`;
const hash=s=>createHash('sha256').update(s).digest('hex');
const plain=o=>o!==null&&typeof o==='object'&&!Array.isArray(o)&&(Object.getPrototypeOf(o)===Object.prototype||Object.getPrototypeOf(o)===null);
const exact=(o,keys)=>plain(o)&&Object.keys(o).sort().join('\0')===[...keys].sort().join('\0');
const hex=x=>typeof x==='string'&&/^[0-9a-f]{64}$/.test(x);
const oid=x=>Number.isSafeInteger(x)&&x>0&&x<=4294967295;
const instant=x=>typeof x==='string'&&/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(x)&&
 Number.isFinite(Date.parse(x))&&new Date(x).toISOString()===x;
const canonical=v=>{
 if(v===null||typeof v!=='object')return JSON.stringify(v);
 if(Array.isArray(v))return '['+v.map(canonical).join(',')+']';
 return '{'+Object.keys(v).sort().map(k=>JSON.stringify(k)+':'+canonical(v[k])).join(',')+'}';
};
function body(sql,start,end){
 const pos=sql.indexOf(start),last=sql.indexOf(end,pos+start.length);
 if(pos<0||last<0||sql.indexOf(start,pos+start.length)!==-1)throw new Error('compiled_body_preimage_mismatch');
 return sql.slice(pos+start.length,last);
}

// Converts the reviewed aggregate SELECT output to compiler input. Supplying a
// project string does not authenticate a provider endpoint; the operator must
// verify that independently and the SQL rechecks its database-local facts.
export function preparePreimageV1({observation,project,trust}){
 if(project!==PROJECT_REF||trust!==TRUST||!exact(observation,['observedAt','suggestedValidUntil','database','serverVersion',
    'sessionUser','currentUser','role','history','roleOids','roleChecks','scheduler']))throw new Error('invalid_observation_or_trust');
 const c=observation.roleChecks,s=observation.scheduler,h=observation.history;
 if(observation.database!=='postgres'||observation.sessionUser!=='postgres'||observation.currentUser!=='postgres'||
    !['none','postgres'].includes(observation.role)||
    !exact(c,['owner','provider','cli','ownerPaths','superuserPaths','directMembershipCount'])||
    c.owner!==true||c.provider!==true||c.cli!==true||c.ownerPaths!==true||c.superuserPaths!==true||c.directMembershipCount!==1||
    !exact(s,['sha256','metadataOk'])||s.metadataOk!==true||s.sha256!==SCHEDULER_SHA256)
  throw new Error('observed_preimage_not_qualified');
 if(!exact(h,['count','sha256','fence','archive','identity'])||h.fence!==true||h.archive!==true||h.identity!==true)
  throw new Error('required_predecessor_history_absent_or_invalid');
 return {format:'collect.managed-provider-identity.v1',project,trust,observedAt:observation.observedAt,
  validUntil:observation.suggestedValidUntil,serverVersion:observation.serverVersion,
  history:{...h},roleOids:{...observation.roleOids},schedulerSha256:s.sha256};
}

// `history` is an aggregate catalogue result captured after all three
// predecessors are actually installed. Supplying values does not prove their
// truth: generated SQL rechecks them in its transaction, under the original
// migration-history lock. Cross-system project identity is checked externally.
export function compileManagedBinderV1({source,preimage,binding}){
 if(typeof source!=='string'||hash(source)!==ORIGINAL_SHA256||source.split(oldGuard).length!==2)
  throw new Error('original_binder_preimage_mismatch');
 if(!exact(preimage,['format','project','trust','observedAt','validUntil','serverVersion','history','roleOids','schedulerSha256'])||
    preimage.format!=='collect.managed-provider-identity.v1'||preimage.project!==PROJECT_REF||preimage.trust!==TRUST)
  throw new Error('explicit_project_and_trust_required');
 if(!instant(preimage.observedAt)||!instant(preimage.validUntil)||Date.parse(preimage.validUntil)<=Date.parse(preimage.observedAt)||
    Date.parse(preimage.validUntil)-Date.parse(preimage.observedAt)>900000||
    !Number.isSafeInteger(preimage.serverVersion)||preimage.serverVersion<170000||preimage.serverVersion>=180000)
  throw new Error('invalid_preimage_validity_or_version');
 const h=preimage.history,r=preimage.roleOids;
 if(!exact(h,['count','sha256','fence','archive','identity'])||!Number.isSafeInteger(h.count)||h.count<3||h.count>10000||
    !hex(h.sha256)||h.fence!==true||h.archive!==true||h.identity!==true)
  throw new Error('required_predecessor_history_absent_or_invalid');
 if(!exact(r,['owner','provider','cli','membership'])||Object.values(r).some(x=>!oid(x))||new Set(Object.values(r)).size!==4)
  throw new Error('invalid_role_preimage');
 if(preimage.schedulerSha256!==SCHEDULER_SHA256)throw new Error('scheduler_variant_not_qualified');
 const uuid=x=>typeof x==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(x)&&x!=='00000000-0000-0000-0000-000000000000';
 if(!exact(binding,['operationId','profileRaw','fenceOperationId','fenceEpoch','fenceSourceSha256'])||
    !uuid(binding.operationId)||!uuid(binding.fenceOperationId)||!Number.isSafeInteger(binding.fenceEpoch)||binding.fenceEpoch<1||
    !hex(binding.fenceSourceSha256)||typeof binding.profileRaw!=='string'||Buffer.byteLength(binding.profileRaw,'utf8')>8192)
  throw new Error('invalid_atomic_binding');
 try{
  const profile=validateDeploymentProfile(JSON.parse(binding.profileRaw));
  if(profile.mode!=='managed'||profile.environment!=='production'||binding.profileRaw!==canonicalProfile(profile)||
     Object.entries(profile).some(([k,v])=>k.endsWith('_origin')&&new URL(v).hostname.split('.').some(label=>label.startsWith('xn--'))))
   throw new Error('invalid');
 }catch{throw new Error('invalid_managed_profile');}
 const {owner,provider,cli,membership}=r;
 const replacement=` -- Additional v1 qualification: an exact short-lived catalog preimage, and
 -- the explicitly trusted provider administrative role. This does not prove
 -- absence of provider sessions, outstanding effects, or other owner actors.
 IF current_database() IS DISTINCT FROM 'postgres' OR current_setting('server_version_num')::integer<>${preimage.serverVersion}
  OR clock_timestamp()<timestamptz '${preimage.observedAt}' OR clock_timestamp()>=timestamptz '${preimage.validUntil}'
 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='managed_deployment_scope_or_preimage_expired';END IF;
 IF (SELECT count(*) FROM supabase_migrations.schema_migrations)<>${h.count}
  OR (SELECT ${HISTORY_DIGEST_SQL} FROM supabase_migrations.schema_migrations) IS DISTINCT FROM '${h.sha256}'
 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='managed_deployment_full_history_preimage';END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles r WHERE r.oid=${owner}::oid AND r.rolname='postgres' AND NOT r.rolsuper
    AND r.rolcanlogin AND r.rolinherit AND r.rolcreatedb AND r.rolcreaterole AND r.rolreplication AND r.rolbypassrls)
  OR NOT EXISTS(SELECT 1 FROM pg_roles r WHERE r.oid=${provider}::oid AND r.rolname='supabase_admin' AND r.rolsuper)
  OR NOT EXISTS(SELECT 1 FROM pg_roles r WHERE r.oid=${cli}::oid AND r.rolname='cli_login_postgres'
    AND r.rolcanlogin AND NOT r.rolsuper AND NOT r.rolinherit AND NOT r.rolcreatedb AND NOT r.rolcreaterole
    AND NOT r.rolreplication AND NOT r.rolbypassrls AND r.rolconnlimit=-1)
  OR (SELECT count(*) FROM pg_auth_members m WHERE m.member=${cli}::oid)<>1
  OR NOT EXISTS(SELECT 1 FROM pg_auth_members m WHERE m.oid=${membership}::oid AND m.roleid=${owner}::oid
    AND m.member=${cli}::oid AND m.grantor=${provider}::oid AND m.set_option AND NOT m.inherit_option AND NOT m.admin_option)
  OR EXISTS(SELECT 1 FROM pg_roles r WHERE NOT r.rolsuper AND r.oid NOT IN(${owner}::oid,${cli}::oid)
    AND (pg_has_role(r.oid,${owner}::oid,'MEMBER') OR pg_has_role(r.oid,${cli}::oid,'MEMBER')))
  OR EXISTS(SELECT 1 FROM pg_roles r CROSS JOIN pg_roles s WHERE NOT r.rolsuper AND s.rolsuper
    AND pg_has_role(r.oid,s.oid,'MEMBER'))
 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='managed_deployment_provider_role_preimage';END IF;`;
 const quoted=s=>"'"+s.replaceAll("'","''")+"'";
 const install=source.replace(oldGuard,replacement);
 if(!install.endsWith('\nCOMMIT;\n'))throw new Error('original_transaction_preimage_mismatch');
 const profileSha256=hash(binding.profileRaw);
 const atomicBind=`\n-- Install and bind are one atomic transaction; failure rolls both back.
DO $atomic_bind$ BEGIN
 -- Preserve the original migration -> work -> write -> identity lock order.
 -- Do not let the original idempotent existing-row branch bypass fence checks.
 PERFORM pg_advisory_xact_lock(7346371,11);
 LOCK TABLE supabase_migrations.schema_migrations IN SHARE MODE;
 PERFORM pg_advisory_xact_lock(7346371,1);PERFORM pg_advisory_xact_lock(7346371,2);
 LOCK TABLE private.collect_deployment_identity IN SHARE ROW EXCLUSIVE MODE;
 IF EXISTS(SELECT 1 FROM private.collect_deployment_identity)
 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='managed_deployment_atomic_bind_requires_empty_identity';END IF;
 IF private.collect_bind_managed_deployment(${quoted(binding.operationId)}::uuid,${quoted(binding.profileRaw)}::text,
  ${quoted(profileSha256)}::text,${quoted(binding.fenceOperationId)}::uuid,${binding.fenceEpoch}::bigint,
  ${quoted(binding.fenceSourceSha256)}::text) IS DISTINCT FROM true
 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='managed_deployment_atomic_bind_refused';END IF;
END $atomic_bind$;
COMMIT;\n`;
 const sql='-- collect.managed-provider-identity.v1; generated offline; provider administration explicitly trusted\n'+
  install.slice(0,-'\nCOMMIT;\n'.length)+atomicBind;
 const helper=body(sql,'AS $identity_preimage$','$identity_preimage$;');
 const binder=body(sql,'AS $fn$','$fn$;');
 return Object.freeze({sql,receipt:Object.freeze({format:'collect.managed-provider-identity.receipt.v1',project:PROJECT_REF,
  sourceSha256:ORIGINAL_SHA256,preimageSha256:hash(canonical(preimage)),sqlSha256:hash(sql),helperBodySha256:hash(helper),
  binderBodySha256:hash(binder),validUntil:preimage.validUntil,operationId:binding.operationId,profileSha256,
  productionDispatch:false})});
}

// Pure review aid, not a transaction manager or automatic retry policy. A
// present/absent catalogue snapshot does not settle an unacknowledged request.
export function assessAcknowledgement({phase,acknowledgement,readback}){
 if(!['install','bind'].includes(phase)||!['success','error','unknown'].includes(acknowledgement)||
    !['matches','absent','different','unavailable'].includes(readback))throw new Error('invalid_observation');
 return Object.freeze({phase,acknowledgement,readback,decision:'hold_for_external_reconciliation',automaticRetry:false,
  actorAbsenceProven:false,productionReleaseProven:false});
}
export function executeManaged(){throw new Error('managed_dispatch_not_implemented');}
