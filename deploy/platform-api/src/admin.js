import {ApiError,first,rows,uuid,text,integer,id,now,pagination,requirePermission} from './core.js';
import {mutation} from './mutations.js';
import {assertMemberManagementTarget,memberManagementGuard} from './user_access.js';
const lists={admin_list_collections:['collections','collections.read','title','status'],admin_list_members:['users','users.read','public_id','access_status'],admin_list_users:['users','users.read','public_id','access_status'],admin_list_non_member_users:['users','users.read','public_id','access_status'],admin_list_payments:['payments','payments.read','payer_display_name','status'],admin_list_collect_transactions:['payments','payments.read','payer_display_name','status'],admin_list_payment_intents:['payment_intents','payments.read','id','status'],admin_list_collect_reconciliations:['reconciliations','payments.read','id','status'],admin_list_collect_ledgers:['ledger_entries','ledger.read','id','kind'],admin_list_ledger:['ledger_entries','ledger.read','id','kind'],admin_list_notifications:['notification_events','notifications.read','title','status'],admin_list_audit_logs:['audit_log','audit.read','action','action'],admin_list_settings:['runtime_config','settings.read','key','key']};
export const adminListOperations=Object.freeze(Object.keys(lists));
function rowJson(row,table,title,status){
 const value={id:String(row.id??row.key),title:String(row[title]??row.id??row.key),subtitle:row.public_id?`Collect ID ${row.public_id}`:'',status:String(row[status]??'active'),amount:Number.isSafeInteger(row.amount_minor)?`${row.amount_minor} RWF`:'',created_at:row.created_at??row.updated_at??null,country_code:'RW'};
 if(table==='payments'){value.rail='rwanda_momo';value.evidence_level=row.status==='confirmed'?'provider_authenticated':'operator_recorded';}
 if(table==='collections'){value.creator_user_id=row.creator_user_id;value.visibility_status=row.visibility_status;}
 if(table==='users'){value.public_id=row.public_id;value.country_code=row.country_code;}
 return value;
}
export async function adminRpc(operation,body,env,actor) {
 if(operation==='admin_current_user'){const assigned=actor.permissions.size?await rows(env,'SELECT role FROM admin_role_assignments WHERE user_id=? ORDER BY role',actor.userId):[];return {handled:true,value:actor.permissions.size?{user_id:actor.userId,display_name:actor.user.user_metadata.full_name||'Collect admin',phone_masked:actor.user.phone?`•••${actor.user.phone.slice(-3)}`:null,roles:assigned.map(r=>r.role),permissions:[...actor.permissions].sort()}:null};}
 if(operation==='is_platform_admin')return {handled:true,value:actor.permissions.size>0};
 if(operation==='admin_overview'){
  requirePermission(actor,'overview.read');const metrics=[];
  for(const [table,label,permission] of [['users','Members','users.read'],['collections','Groups','collections.read'],['payments','Recorded payments','payments.read']])if(actor.permissions.has(permission))metrics.push({label,value:(await first(env,`SELECT count(*) AS n FROM ${table}`)).n,status:'active'});
  return {handled:true,value:{metrics}};
 }
 if(lists[operation]){
  const [table,permission,title,status]=lists[operation];requirePermission(actor,permission);const {limit,offset}=pagination(body);
  const search=body.p_search??body.search??'';if(typeof search!=='string'||search.length>80)throw new ApiError(400,'invalid_search','Invalid search.');
  const filter=body.p_status??body.status??null;
  const where=`WHERE (?='' OR ${title} LIKE ?) AND (? IS NULL OR ${status}=?)`;
  const params=[search,'%'+search+'%',filter,filter];
  const total=(await first(env,`SELECT count(*) AS n FROM ${table} ${where}`,...params)).n;
  const order=table==='audit_log'?'id DESC':table==='runtime_config'?'key ASC':'created_at DESC,id ASC';
  const result=await rows(env,`SELECT * FROM ${table} ${where} ORDER BY ${order} LIMIT ? OFFSET ?`,...params,limit,offset);
  return {handled:true,value:{rows:result.map(r=>rowJson(r,table,title,status)),total}};
 }
 if(operation==='admin_runtime_config'){
  requirePermission(actor,'overview.read');const nav=[['overview','Overview','dashboard','/admin','overview.read'],['collections','Groups','groups','/admin/collections','collections.read'],['members','Members','people','/admin/members','users.read'],['transactions','Payments','receipt_long','/admin/transactions','payments.read'],['notifications','Notifications','notifications','/admin/notifications','notifications.read'],['settings','Settings','settings','/admin/settings','settings.read']];
  return {handled:true,value:{navigation_items:nav.filter(n=>actor.permissions.has(n[4])).map((n,i)=>({key:n[0],label:n[1],icon_key:n[2],route_path:n[3],required_permission:n[4],display_order:i})),queue_specs:Object.entries(lists).filter(([name,v])=>actor.permissions.has(v[1])).map(([name,v])=>({rpc_name:name,title:v[0].replaceAll('_',' '),subtitle:'Review current records.',required_permission:v[1],status_options:[{value:'',label:'All'}],sort_options:[{value:'newest',label:'Newest'}],priority_signals:[],workflow_steps:[]}))}};
 }
 if(operation==='admin_get_user'){
  requirePermission(actor,'users.read');const user=await first(env,'SELECT * FROM users WHERE id=?',uuid(body.p_id??body.p_user_id,'user_id'));if(!user)throw new ApiError(404,'user_unavailable','Member is unavailable.');
  return {handled:true,value:{id:user.id,phone_masked:user.phone?`•••${user.phone.slice(-3)}`:null,country_code:user.country_code,payment_profile:user.momo_provider||'not_configured',momo_masked:user.momo_number?`•••${user.momo_number.slice(-3)}`:null,active_groups:(await first(env,'SELECT count(*) AS n FROM memberships WHERE user_id=? AND active=1',user.id)).n,status:user.access_status,created_at:user.created_at,updated_at:user.updated_at}};
 }
 if(operation==='admin_set_user_access'){
  requirePermission(actor,'users.manage');const target=uuid(body.p_user_id??body.user_id,'user_id');const status=text(body.p_access_status??body.status,'status',16);
  if(!['active','suspended'].includes(status))throw new ApiError(400,'invalid_status','Invalid account status.');
  if(target===actor.userId&&status==='suspended')throw new ApiError(409,'self_suspend','Ask another administrator to suspend this account.');
  const row=await first(env,'SELECT * FROM users WHERE id=?',target);if(!row)throw new ApiError(404,'user_unavailable','Member is unavailable.');
  await assertMemberManagementTarget(env,row);const targetGuard=memberManagementGuard(env,row,status);
  await mutation(env,actor,operation,uuid(body.p_request_id??id(),'request_id'),body,null,[targetGuard[0],env.DB.prepare('UPDATE users SET access_status=?,updated_at=? WHERE id=?').bind(status,now(),target),env.DB.prepare(`UPDATE auth_sessions SET revoked_at=?,revocation_reason='account_suspended' WHERE user_id=? AND revoked_at IS NULL AND ?='suspended'`).bind(Math.floor(Date.now()/1000),target,status),targetGuard[1]],{permission:'users.manage',minimumAssurance:2,freshSeconds:300,entityType:'user',entityId:target});return {handled:true,value:null};
 }
 if(operation==='admin_system_health'){
  requirePermission(actor,'system_health.read');await first(env,'SELECT 1 AS available');return {handled:true,value:{database:'available',storage_binding:!!env.PRIVATE_MEDIA,checked_at:now()}};
 }
 if(operation==='admin_get_queue_sla') {requirePermission(actor,'overview.read');return {handled:true,value:{}};}
 return {handled:false};
}
