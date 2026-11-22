import {ApiError,uuid} from './core.js';
import {accountDatabase} from './admin_accounts.js';

// Canonical captures have no extracted source facts, receiver-ingress record,
// payment association, or extraction history. Never manufacture those facts to
// resemble the older member/receiver parser model. The capture DTO is explicit.
const sourceKinds=new Set(['capture','member','receiver']);
const statuses=new Set(['received','under_review','rejected','linked','pending','parsed','parse_failed','needs_review','reviewed']);
const extractionStatuses=new Set(['not_extracted','parsed','needs_review']);
const sourceSql=`SELECT s.id,s.owner_user_id,s.body_sha256,s.status,s.evidence_level,
 s.received_at_device,s.created_at,u.public_id,u.full_name
 FROM sms_receipts s JOIN users u ON u.id=s.owner_user_id`;
const fail=(status,code,message)=>{throw new ApiError(status,code,message);};
const invalid=()=>fail(400,'invalid_filter','This SMS receipt filter is unavailable.');
const badSource=()=>fail(503,'invalid_source_data','SMS receipt metadata is unavailable.');
const emptyPage=(limit,offset)=>({rows:[],total:0,limit,offset,next_offset:null});
const factKeys=['source_fact_id','parser_version','source_body_sha256','source_payload_sha256','parsed_at',
 'payer_name','payer_phone','payer_masked_phone','payer_last3','payee_momo_number','payee_momo_code',
 'momo_transaction_reference','momo_timestamp_local','momo_timezone_offset','amount_rwf','wallet_balance_rwf',
 'network','direction','is_payment'];

// Device time is untrusted source TEXT. Only an explicit, valid zoned ISO
// datetime has an epoch projection. Naive/date-only values keep their exact
// text with a null epoch; no timezone or fallback receipt time is invented.
export function captureDeviceSeconds(value){
 if(value===null)return null;
 if(typeof value!=='string'||value.length>64)badSource();
 const match=/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?(Z|[+-]\d{2}:\d{2})$/.exec(value);
 if(!match)return null;
 const [,year,month,day,hour,minute,second,zone]=match,n=[year,month,day,hour,minute,second].map(Number);
 const leap=n[0]%4===0&&(n[0]%100!==0||n[0]%400===0),days=[31,leap?29:28,31,30,31,30,31,31,30,31,30,31];
 if(n[1]<1||n[1]>12||n[2]<1||n[2]>days[n[1]-1]||n[3]>23||n[4]>59||n[5]>59)return null;
 if(zone!=='Z'&&(Number(zone.slice(1,3))>23||Number(zone.slice(4,6))>59))return null;
 // setUTCFullYear avoids Date.UTC's special handling of years00..99. Ignore
 // the nonnegative fractional part: floor(epoch seconds) is the whole local
 // second minus its exact minute offset, including dates before1970.
 const local=new Date(0);local.setUTCFullYear(n[0],n[1]-1,n[2]);local.setUTCHours(n[3],n[4],n[5],0);
 const offset=zone==='Z'?0:(zone[0]==='-'?-1:1)*(Number(zone.slice(1,3))*60+Number(zone.slice(4,6)))*60;
 const seconds=local.getTime()/1000-offset;
 return Number.isSafeInteger(seconds)&&Math.abs(seconds)<=8640000000000?seconds:null;
}
function createdSeconds(value){
 if(typeof value!=='string'||!/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(value))badSource();
 const parsed=Date.parse(value);if(!Number.isFinite(parsed)||new Date(parsed).toISOString()!==value)badSource();
 return Math.floor(parsed/1000);
}
function sourceRow(row){
 if(!['received','under_review','rejected','linked'].includes(row.status)||row.evidence_level!=='client_received'||
  typeof row.body_sha256!=='string'||! /^[a-f0-9]{64}$/.test(row.body_sha256)||
  typeof row.public_id!=='string'||! /^\d{6}$/.test(row.public_id)||typeof row.full_name!=='string')badSource();
 return {source_kind:'capture',id:uuid(row.id),user_id:uuid(row.owner_user_id),payee_id:null,
  source_sha256:row.body_sha256,status:row.status,
  // This is the version of the immutable captured source, not a status revision.
  version:1,received_at:captureDeviceSeconds(row.received_at_device),received_at_device:row.received_at_device,
  created_at:createdSeconds(row.created_at),public_id:row.public_id,display_name:row.full_name||null,
  transaction_id:null,evidence_level:'client_received',...Object.fromEntries(factKeys.map(key=>[key,null])),
  extraction_status:'not_extracted',transaction_reference:null,duplicate_reference_count:0,conflicting_reference_count:0,
  provider_confirmation:false,settlement_status:'not_asserted',timezone_known:false,payer_last3_known:false,
  source_content_reveal_required:true};
}
function filters(url,allowed){
 for(const key of url.searchParams.keys())if(!allowed.includes(key)||url.searchParams.getAll(key).length!==1)invalid();
 const number=(key,fallback,min,max)=>{const raw=url.searchParams.get(key);if(raw===null)return fallback;
  if(!/^(0|[1-9][0-9]*)$/.test(raw))invalid();const value=Number(raw);if(!Number.isSafeInteger(value)||value<min||value>max)invalid();return value;};
 const search=url.searchParams.get('search')??'';if(search.length>200||/[\u0000-\u001f\u007f]/.test(search))invalid();
 const status=url.searchParams.get('status')??'',sourceKind=url.searchParams.get('source_kind')??'',
  extraction=url.searchParams.get('extraction_status')??'',duplicates=url.searchParams.get('duplicates')??'';
 if(status&&!statuses.has(status)||sourceKind&&!sourceKinds.has(sourceKind)||extraction&&!extractionStatuses.has(extraction)||
  !['','all','conflicting'].includes(duplicates))invalid();
 return {limit:number('limit',25,1,100),offset:number('offset',0,0,2147483647),search:search.trim(),status,sourceKind,extraction,duplicates};
}
export async function adminSmsMetadataRead(request,env,account,actor,parts,url){
 if(!actor.permissions.has('sms.read'))fail(403,'permission_required','SMS receipt metadata is unavailable for this account.');
 if(request.method!=='GET')fail(405,'method_not_allowed','SMS receipt metadata is read-only.');
 const list=parts.length===1&&parts[0]==='receipts',detail=parts.length===3&&parts[0]==='receipts';
 if(!list&&!detail)fail(404,'not_found','This SMS metadata view does not exist.');
 const f=filters(url,list?['limit','offset','search','status','source_kind','extraction_status','duplicates']:['limit','offset']);
 const scoped=accountDatabase(env,account,'sms.read');
 if(detail){
  if(parts[1]!=='capture')fail(404,'not_found','This capture metadata view does not exist.');
  const id=uuid(parts[2],'receipt_id');
  const [result]=await scoped.DB.batch([scoped.DB.prepare(sourceSql+' WHERE s.id=?').bind(id)]);
  if(result.results.length!==1)fail(404,'not_found','This capture was not found.');
  return {resource_type:'sms_receipts',resource:sourceRow(result.results[0]),current_actor_id:account.id,
   can_extract:false,related:{duplicate_references:emptyPage(f.limit,f.offset)}};
 }
 const conditions=[],args=[];
 if(f.status){conditions.push('s.status=?');args.push(f.status);}
 // Valid legacy filters return no captures. They do not create receiver rows,
 // extracted facts, or reference matches that the canonical source lacks.
 if(f.sourceKind&&f.sourceKind!=='capture'||f.extraction&&f.extraction!=='not_extracted'||f.duplicates)conditions.push('0=1');
 if(f.search){conditions.push('(instr(lower(s.id),lower(?))>0 OR instr(u.public_id,?)>0 OR instr(lower(u.full_name),lower(?))>0)');args.push(f.search,f.search,f.search);}
 const where=conditions.length?' WHERE '+conditions.join(' AND '):'';
 const [count,result]=await scoped.DB.batch([
  scoped.DB.prepare('SELECT count(*) AS total FROM sms_receipts s JOIN users u ON u.id=s.owner_user_id'+where).bind(...args),
  scoped.DB.prepare(sourceSql+where+' ORDER BY s.created_at DESC,s.id ASC LIMIT ? OFFSET ?').bind(...args,f.limit,f.offset)]);
 const total=count.results[0].total,rows=result.results.map(sourceRow);
 if(!Number.isSafeInteger(total)||total<0||rows.length!==Math.max(0,Math.min(f.limit,total-f.offset)))badSource();
 return {rows,total,limit:f.limit,offset:f.offset,next_offset:f.offset+rows.length<total?f.offset+rows.length:null};
}
