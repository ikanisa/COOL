import {ApiError,digest,stableJson,id} from './domain/core.js';
export const MEMBER_REALTIME_CLASS='managed:realtime_messages';
const fail=()=>{throw new ApiError(409,'privacy_retention_realtime_changed','Realtime inventory or approval changed. Obtain a current reviewed decision.');};
// Preserve the shipping accountDatabase transaction: its batch prefix installs
// current email proof and rechecks current grants before this sensitive read.
const first=async(env,statement,column)=>(await env.DB.batch([statement]))[0].results[0]?.[column];
const read=async(env,subject)=>first(env,env.DB.prepare('SELECT private.retention_member_realtime_inventory(?) AS inventory').bind(subject),'inventory');
export async function memberRealtimeRetentionIdentity(env){
 const value=await read(env,null);
 if(value?.contract_version!==1||value.schema?.contract!=='collect.member.realtime.inventory.v1'||!/^[a-f0-9]{64}$/.test(value.schema?.metadata_sha256??'')||!/^[a-f0-9]{64}$/.test(value.schema?.partitions_sha256??''))fail();
 const helper=await first(env,env.DB.prepare("SELECT encode(sha256(convert_to(pg_get_functiondef('private.retention_member_realtime_inventory(text)'::regprocedure),'UTF8')),'hex') AS sha256"),'sha256');
 if(!/^[a-f0-9]{64}$/.test(helper??''))fail();return{schema:value.schema,helper_sha256:helper};
}
export async function inventoryMemberRealtime(env,subject,identity){
 const value=await read(env,subject),entry=value?.class;
 if(value?.contract_version!==1||stableJson(value.schema)!==stableJson(identity.schema)||!entry||!['observed','unavailable'].includes(entry.status)||!Number.isSafeInteger(entry.count)||entry.count<0||entry.count>500||!Array.isArray(entry.rows)||entry.rows.length!==entry.count||entry.rows.some(r=>!/^[a-f0-9]{64}$/.test(r.key_sha256??'')||!/^[a-f0-9]{64}$/.test(r.row_sha256??'')))fail();
 return{...entry,sha256:await digest(stableJson(entry.rows))};
}
export function memberRealtimeRetentionGuards(env,plan,className,inventory,identity){
 if(!inventory||!identity)fail();const{sha256,...expected}=inventory;
 return[
  env.DB.prepare(`INSERT INTO app.privacy_retention_guards(id,plan_id,class_name,passed) SELECT ?,?,?,CASE WHEN private.retention_member_realtime_inventory(?)->'class'=?::jsonb AND private.retention_member_realtime_inventory(NULL)->'schema'=?::jsonb AND encode(sha256(convert_to(pg_get_functiondef('private.retention_member_realtime_inventory(text)'::regprocedure),'UTF8')),'hex')=? THEN 1 ELSE 0 END`).bind(id(),plan.id,className,plan.subject_id,expected,identity.schema,identity.helper_sha256)
 ];
}
// This proposal adds no erasure adapter. Catalog policy MUST require blocked for
// managed:realtime_messages. Unavailable is never an observed-empty disposition;
// source comparison rejects every added/expired/changed message or partition.
