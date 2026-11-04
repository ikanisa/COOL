// OpenSMS v0.3 wire contract, inspected source archive SHA256:
// fbb65c024d8b1c1340245ea0014d525f7b1e2009910598e34de56c2ca0eb4909.
// A receipt transport only. Supabase remains the durable business authority.
const encoder=new TextEncoder();
const safeError=()=>new Error('opensms_receipt_unconfirmed');
const sha=async value=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',encoder.encode(value))),b=>b.toString(16).padStart(2,'0')).join('');
const states=new Set(['accepted','assigned','phone_accepted','queued','handoff_started','sent','delivered','delivery_unconfirmed','partial','failed','outcome_unknown','cancelled','expired']);

export function openSmsReceiptConfiguration(env){
 if(env.COLLECT_RECEIPT_SMS_ENABLED!=='true')return null;
 const origin=env.OPENSMS_RECEIPT_BASE_URL,applicationId=env.OPENSMS_RECEIPT_APPLICATION_ID,token=env.OPENSMS_RECEIPT_APPLICATION_TOKEN;
 let url;try{url=new URL(origin);}catch{throw safeError();}
 if(![url.origin,url.origin+'/functions/v1/collect-sms'].includes(origin)||url.protocol!=='https:'||url.username||url.password||url.port||
  !/^[A-Za-z0-9_-]{1,100}$/.test(applicationId??'')||typeof token!=='string'||token.length<32||token.length>4096||/[\s\x00-\x1f]/.test(token)||
  !/^[a-f0-9]{64}$/.test(env.COLLECT_RECEIPT_SMS_APPROVAL_SHA256??'')||!/^[a-f0-9]{64}$/.test(env.BUILD_SOURCE_ID??''))throw safeError();
 return Object.freeze({origin,applicationId,token});
}

export function createOpenSmsReceiptTransport(configuration,{fetchImpl=(request,init)=>globalThis.fetch(request,init)}={}){
 const config=configuration;
 async function request(path,{body,idempotencyKey}={}){
  const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),8000);
  try{
   const response=await fetchImpl(config.origin+path,{method:body?'POST':'GET',redirect:'error',cache:'no-store',signal:controller.signal,
    headers:{Authorization:'Bearer '+config.token,Accept:'application/json',...(body?{'Content-Type':'application/json','Idempotency-Key':idempotencyKey}:{})},
    ...(body?{body:JSON.stringify(body)}:{})});
   if(response.redirected||response.status!==(body?202:200)||!/^application\/json(?:;|$)/i.test(response.headers.get('content-type')??''))throw safeError();
   const reader=response.body?.getReader();if(!reader)throw safeError();let size=0;const chunks=[];
   try{while(true){const part=await reader.read();if(part.done)break;size+=part.value.length;if(size>131072){await reader.cancel();throw safeError();}chunks.push(part.value);}}finally{reader.releaseLock();}
   const bytes=new Uint8Array(size);let offset=0;for(const part of chunks){bytes.set(part,offset);offset+=part.length;}
   const result=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));
   if(!result||Array.isArray(result)||typeof result!=='object')throw safeError();return result;
  }catch{throw safeError();}finally{clearTimeout(timer);}
 }
 function payload(message){
  if(!message||typeof message.messageId!=='string'||!message.messageId.startsWith(config.applicationId+':')||message.messageId.length>200||
   !/^\+2507[2389][0-9]{7}$/.test(message.to)||typeof message.text!=='string'||message.text.length<1||message.text.length>2000||
   typeof message.notAfter!=='string'||!Number.isFinite(Date.parse(message.notAfter)))throw safeError();
  return {message_id:message.messageId,kind:'receipt',to:message.to,text:message.text,not_after:message.notAfter,priority:80,metadata:{}};
 }
 async function inspect(message){
  payload(message);
  const result=await request('/v1/messages/'+encodeURIComponent(message.messageId)),row=result.message;
  if(!row||row.message_id!==message.messageId||row.application_id!==config.applicationId||row.kind!=='receipt'||
   row.to!==message.to||row.text!==message.text||row.priority!==80||row.not_after!==message.notAfter||
   typeof row.available_at!=='string'||!Number.isFinite(Date.parse(row.available_at))||
   row.campaign_id!==null||!states.has(row.state)||row.content_redacted_at!==null)throw safeError();
  const fields=[row.message_id,row.application_id,row.kind,row.to,row.text,String(row.priority),row.not_after,row.available_at,''];
  const digest=await sha('collect-sms-payload-v1\n'+fields.map(value=>`${encoder.encode(value).byteLength}:${value}`).join(''));
  if(row.payload_digest!==digest)throw safeError();
  const observation=['sent','delivered','delivery_unconfirmed'].includes(row.state)?'observed_sent':
    ['failed','partial','outcome_unknown','cancelled','expired'].includes(row.state)?'uncertain':null;
  const evidence=await sha(JSON.stringify({message_id:row.message_id,payload_digest:digest,state:row.state,updated_at:row.updated_at??null}));
  return {state:row.state,providerAccepted:true,observation,evidenceSha256:evidence};
 }
 return Object.freeze({
  async submit(message){
   const body=payload(message);
   // One POST only. Every timeout/non-acknowledgment is retained by the caller;
   // subsequent explicit reconciliation uses inspect(), never another POST.
   const idempotencyKey=message.messageId.slice(config.applicationId.length+1);
   if(!idempotencyKey||idempotencyKey.length>128)throw safeError();
   const result=await request('/v1/messages',{body,idempotencyKey});
   if(result.message_id!==message.messageId||!states.has(result.state))throw safeError();
   return inspect(message);
  },inspect,
 });
}
