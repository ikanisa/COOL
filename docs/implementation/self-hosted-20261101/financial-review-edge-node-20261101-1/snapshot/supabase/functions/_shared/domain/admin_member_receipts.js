import {ApiError,uuid} from './core.js';
import {accountDatabase} from './admin_accounts.js';
import {captureDeviceSeconds} from './admin_sms_receipts.js';

// The canonical capture is a client observation, not a reviewed submission or
// a payment. This explicit variant preserves the recorded source state without
// manufacturing review history, a payment association, or provider finality.
const sourceSql=`SELECT s.id,s.owner_user_id,s.body_sha256,s.status,s.evidence_level,
 s.received_at_device,s.created_at,u.public_id,u.full_name
 FROM sms_receipts s JOIN users u ON u.id=s.owner_user_id`;
const statuses=new Set(['received','under_review','rejected','linked','needs_review','reviewed']);
const fail=(status,code,message)=>{throw new ApiError(status,code,message);};
const invalid=()=>fail(400,'invalid_filter','This receipt filter is unavailable.');
const badSource=()=>fail(503,'invalid_source_data','Receipt metadata is unavailable.');
function sourceRow(row){
 if(!['received','under_review','rejected','linked'].includes(row.status)||row.evidence_level!=='client_received'||
  typeof row.body_sha256!=='string'||! /^[a-f0-9]{64}$/.test(row.body_sha256)||
  typeof row.public_id!=='string'||! /^\d{6}$/.test(row.public_id)||typeof row.full_name!=='string'||
  typeof row.created_at!=='string'||! /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(row.created_at))badSource();
 const created=Date.parse(row.created_at);if(!Number.isFinite(created)||new Date(created).toISOString()!==row.created_at)badSource();
 const received=captureDeviceSeconds(row.received_at_device);
 return {id:uuid(row.id),user_id:uuid(row.owner_user_id),body_sha256:row.body_sha256,status:row.status,
  // Immutable capture version; never a mutable classification revision.
  version:1,received_at:received===null?null:new Date(received*1000).toISOString(),created_at:row.created_at,
  public_id:row.public_id,display_name:row.full_name||null,transaction_id:null,reviewed_at:null,
  source_kind:'capture',received_at_device:row.received_at_device,evidence_level:'client_received',
  provider_confirmation:false,settlement_status:'not_asserted',source_content_reveal_required:true};
}
function filters(url,list){
 const allowed=list?['limit','offset','status']:[];
 for(const key of url.searchParams.keys())if(!allowed.includes(key)||url.searchParams.getAll(key).length!==1)invalid();
 const number=(key,fallback,min,max)=>{const raw=url.searchParams.get(key);if(raw===null)return fallback;
  if(!/^(0|[1-9][0-9]*)$/.test(raw))invalid();const value=Number(raw);if(!Number.isSafeInteger(value)||value<min||value>max)invalid();return value;};
 const status=url.searchParams.get('status')??'';if(status&&!statuses.has(status))invalid();
 return {limit:number('limit',25,1,100),offset:number('offset',0,0,2147483647),status};
}
export async function adminMemberReceiptRead(request,env,account,actor,parts,url){
 if(!actor.permissions.has('payments.read'))fail(403,'permission_required','Receipt metadata is unavailable for this account.');
 if(request.method!=='GET')fail(405,'method_not_allowed','Captured receipt metadata is read-only.');
 const list=parts.length===1&&parts[0]==='receipts',detail=parts.length===2&&parts[0]==='receipts';
 if(!list&&!detail)fail(404,'not_found','This receipt view does not exist.');
 const f=filters(url,list),scoped=accountDatabase(env,account,'payments.read');
 if(detail){
  const id=uuid(parts[1],'receipt_id');
  const [result]=await scoped.DB.batch([scoped.DB.prepare(sourceSql+' WHERE s.id=?').bind(id)]);
  if(result.results.length!==1)fail(404,'not_found','This captured receipt was not found.');
  return {resource_type:'member_receipts',resource:sourceRow(result.results[0]),current_actor_id:account.id,
   can_manage:false,related:{reviews:[]},related_truncated:false};
 }
 const where=f.status?' WHERE s.status=?':'',args=f.status?[f.status]:[];
 const [count,result]=await scoped.DB.batch([
  scoped.DB.prepare('SELECT count(*) AS total FROM sms_receipts s JOIN users u ON u.id=s.owner_user_id'+where).bind(...args),
  scoped.DB.prepare(sourceSql+where+' ORDER BY s.created_at DESC,s.id ASC LIMIT ? OFFSET ?').bind(...args,f.limit,f.offset)]);
 const total=count.results[0].total,rows=result.results.map(sourceRow);
 if(!Number.isSafeInteger(total)||total<0||rows.length!==Math.max(0,Math.min(f.limit,total-f.offset)))badSource();
 return {rows,total};
}
