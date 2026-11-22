import {bound} from './transactions.ts';
const MAX_RESPONSE=131072;
const FIELDS=['message_id','application_id','kind','to','text','content_redacted_at','content_hold','payload_digest','priority','not_after','available_at','state','owner_installation_id','assignment_version','cancel_requested','created_at','updated_at','phone_accepted_at','campaign_id','parts_total','requires_fresh_decision','eligibility_until','metadata'];
const ATTEMPT_FIELDS=['message_id','attempt_id','installation_id','parts_total','handoff_at','unknown_observed','failed_observed','aborted_before_call','updated_at'];
const PART_FIELDS=['message_id','attempt_id','part_index','sent_at','delivered_at','failed_at','sent_failed_at','delivery_failed_at','delivery_unknown_at','error_code'];
const HISTORY_FIELDS=['event_id','type','attempt_id','at','received_at','part_index','parts_total','error_code','detail_redacted_at','detail'];
const AUDIT_FIELDS=['event_id','actor_type','actor_id','action','resource_id','at'];
const own=(value:unknown):value is Record<string,any>=>!!value&&typeof value==='object'&&!Array.isArray(value);
const keys=(value:Record<string,unknown>,expected:string[])=>Object.keys(value).sort().join('|')===[...expected].sort().join('|');
function has(list:unknown,needed:string){try{if(typeof list!=='string'||list.length>8192)return false;const values=JSON.parse(list);return Array.isArray(values)&&values.length<=32&&values.every(v=>typeof v==='string'&&v.length>0&&v.length<=128)&&new Set(values).size===values.length&&values.includes(needed);}catch{return false;}}
/** Match the stored row to the active application and its receipt read scope. */
export async function receiptReadPrincipal(db:any,tokenHash:string,messageId:string){
 const rows=await db.prepare(`SELECT a.application_id,a.allowed_kinds,a.scopes,m.message_id,m.application_id AS message_application_id,m.kind
 FROM applications a JOIN messages m ON m.application_id=a.application_id
 WHERE a.token_hash=? AND a.revoked_at IS NULL AND m.message_id=?`).bind(tokenHash,messageId).all();
 if(rows?.success!==true||!Array.isArray(rows.results))throw Error('receipt_read_unconfirmed');
 if(rows.results.length===0)return null;
 if(rows.results.length!==1)throw Error('receipt_read_unconfirmed');const r=rows.results[0];
 if(!own(r)||typeof r.application_id!=='string'||r.application_id.length<1||r.application_id.length>200||
    r.message_id!==messageId||r.message_application_id!==r.application_id||r.kind!=='receipt'||
    !has(r.allowed_kinds,'receipt')||!has(r.scopes,'messages:read'))return null;
 return Object.freeze({applicationId:r.application_id,messageId});
}
/** Never release a message body until the actual response is bounded and verified. */
export async function checkedReceiptResponse(response:Response,identity:{applicationId:string;messageId:string},browserOrigin:string|null){
 if(response.status!==200){if([401,403,404].includes(response.status))return new Response(null,{status:response.status});throw Error('receipt_response_unconfirmed');}
 if(!/^application\/json(?:\s*;[^\r\n]*)?$/i.test(response.headers.get('content-type')??'')||!response.body)throw Error('receipt_response_unconfirmed');
 const length=response.headers.get('content-length');if(length!==null&&(!/^(0|[1-9][0-9]*)$/.test(length)||Number(length)>MAX_RESPONSE))throw Error('receipt_response_unconfirmed');
 const reader=response.body.getReader(),chunks:Uint8Array[]=[];let size=0,done=false,bytes:Uint8Array|undefined;const deadline=performance.now()+5000;
 try{while(true){const remaining=deadline-performance.now();if(remaining<=0)throw Error('receipt_response_unconfirmed');const part=await bound(reader.read(),remaining);if(part.done){done=true;break;}size+=part.value.byteLength;if(size>MAX_RESPONSE)throw Error('receipt_response_unconfirmed');chunks.push(part.value);}
  if(length!==null&&size!==Number(length))throw Error('receipt_response_unconfirmed');bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.byteLength;}
  const raw=new TextDecoder('utf-8',{fatal:true}).decode(bytes),value=JSON.parse(raw);
  // The gateway uses JSON.stringify. Requiring an identical round trip rejects
  // duplicate keys and alternate/ambiguous serialization rather than guessing.
  if(JSON.stringify(value)!==raw||!own(value)||!keys(value,['message','attempts','parts','history','audit'])||!own(value.message)||!keys(value.message,FIELDS)||
    value.message.message_id!==identity.messageId||value.message.application_id!==identity.applicationId||value.message.kind!=='receipt'||
    !['attempts','parts','history','audit'].every(k=>Array.isArray(value[k]))||
    !value.attempts.every((v:unknown)=>own(v)&&keys(v,ATTEMPT_FIELDS)&&v.message_id===identity.messageId)||
    !value.parts.every((v:unknown)=>own(v)&&keys(v,PART_FIELDS)&&v.message_id===identity.messageId)||
    !value.history.every((v:unknown)=>own(v)&&keys(v,HISTORY_FIELDS))||!value.audit.every((v:unknown)=>own(v)&&keys(v,AUDIT_FIELDS)&&v.resource_id===identity.messageId))throw Error('receipt_response_unconfirmed');
  const headers=new Headers({'content-type':'application/json; charset=UTF-8'});
  if(browserOrigin){if(response.headers.get('access-control-allow-origin')!==browserOrigin)throw Error('receipt_response_unconfirmed');headers.set('access-control-allow-origin',browserOrigin);headers.set('vary','Origin');}
  return new Response(raw,{status:200,headers});
 }finally{if(!done)void reader.cancel().catch(()=>{});try{reader.releaseLock();}catch{}for(const chunk of chunks)chunk.fill(0);bytes?.fill(0);}
}
