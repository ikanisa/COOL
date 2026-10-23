// Product adapter of the maintained Revolut focused-task/web references. System
// font fallback is intentional; no trial font or source branding is distributed.
export const privacyPortalCss = String.raw`
:root{color-scheme:dark;--canvas:#000;--surface:#161618;--field:#202024;--text:#f4f4f4;--muted:#b5b5b8;--accent:#a7aaff;--danger:#ff8b95;font:400 100%/1.5 Inter,system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:var(--canvas);color:var(--text)}
*{box-sizing:border-box}body{margin:0}a{color:var(--accent);text-underline-offset:.22em}button,input{font:inherit}button,a,input{touch-action:manipulation}button{min-height:3.25rem;padding:.8rem 1.5rem;border:0;border-radius:999px;background:var(--text);color:#191c1f;font-weight:600;cursor:pointer;white-space:normal;overflow-wrap:anywhere}button.secondary{background:var(--field);color:var(--text)}button:disabled{opacity:.5;cursor:default}button:focus-visible,a:focus-visible,input:focus-visible{outline:3px solid var(--accent);outline-offset:4px}input{width:100%;min-width:0;min-height:3.5rem;padding:1rem;border:1px solid #717173;border-radius:1rem;background:var(--field);color:var(--text)}input[aria-invalid=true]{border-color:var(--danger)}[hidden]{display:none!important}#page{width:min(100% - 2rem,32rem);margin:auto;padding:2rem 0 3rem}header{display:flex;flex-wrap:wrap;align-items:center;justify-content:space-between;gap:1rem;margin-bottom:3rem}.identity{font-size:1.5rem;font-weight:700;text-decoration:none;color:var(--text)}header small{color:var(--muted)}h1{font-size:clamp(2rem,7vw,3rem);line-height:1.12;letter-spacing:-.03em;margin:0 0 1rem;overflow-wrap:anywhere}h2{font-size:1.5rem;line-height:1.25;margin:0 0 1rem}p{margin:0 0 1rem}.muted,.hint{color:var(--muted)}.hint{font-size:.875rem}label{display:block;font-weight:500;margin:1.5rem 0 .5rem}.actions{display:flex;flex-direction:column;gap:.75rem;margin-top:1.5rem}.surface{background:var(--surface);padding:1.5rem;border-radius:1.5rem;margin:1.5rem 0}.notice{border-left:3px solid var(--accent);padding-left:1rem}#error{color:var(--danger);overflow-wrap:anywhere}#status{margin:1.25rem 0;min-height:1.5rem}#reference{font-variant-numeric:tabular-nums;overflow-wrap:anywhere}dl{margin:0}dt{color:var(--muted);margin-top:1rem}dd{margin:.25rem 0 0}footer{border-top:1px solid #333338;margin-top:2.5rem;padding-top:1.5rem;font-size:.875rem;color:var(--muted)}footer nav{display:flex;flex-wrap:wrap;gap:1rem;margin-top:1rem}dialog{width:min(30rem,calc(100% - 2rem));padding:1rem;border:1px solid #717173;border-radius:1.5rem;background:var(--surface);color:var(--text);max-height:calc(100dvh - 2rem);overflow:auto}dialog::backdrop{background:#000b}dialog[data-fallback]{position:fixed;inset:1rem;margin:auto;z-index:2;box-shadow:0 0 0 100vmax #000b}iframe{display:block;width:100%;height:23rem;max-height:calc(100dvh - 10rem);border:0;border-radius:1rem}dialog button{width:100%;margin-top:1rem}.sr-only{position:absolute;width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;clip:rect(0,0,0,0);white-space:nowrap;border:0}@media(min-width:48rem){#page{padding-top:3rem}header{margin-bottom:4rem}}@media(prefers-reduced-motion:no-preference){button,a{transition:opacity .15s}button:not(:disabled):hover{opacity:.85}}@media(forced-colors:active){button,input,.surface,dialog{border:1px solid CanvasText}.notice{border-color:Highlight}}
`;

// Served as a same-origin ES module. Tests import these exact bytes, rather than
// maintaining a second implementation of the browser's state machine.
export const privacyPortalScript = String.raw`
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
function fault(code){const e=new Error(code);e.code=code;return e;}
const baseReceipt=['contract_version','request_id','scope','state','reason_code','reason_supplied','accepted_at','policy_review_pending','subject_scope_review_pending','erasure_completed','account_access_restricted','auth_removed','retention_approval_granted','processor_operation_started'];
function instant(value){if(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/.test(value))return false;const date=new Date(value);return Number.isFinite(+date)&&date.toISOString().replace(/\.(\d{3})Z$/,'.$1000Z')===value;}
function receipt(value,submission=null){
 const keys=submission?baseReceipt.concat(['submission_id','replay','equivalent_active_request']):baseReceipt;
 if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).length!==keys.length||keys.some(k=>!Object.hasOwn(value,k))||value.contract_version!==1||!UUID.test(value.request_id)||value.scope!=='own_account_eligible_data'||value.state!=='pending_review'||value.reason_code!=='account_deletion_requested'||typeof value.reason_supplied!=='boolean'||!instant(value.accepted_at)||value.policy_review_pending!==true||value.subject_scope_review_pending!==true||['erasure_completed','account_access_restricted','auth_removed','retention_approval_granted','processor_operation_started'].some(k=>value[k]!==false))throw fault('protocol_unavailable');
 if(submission&&(value.reason_supplied!==false||value.submission_id!==submission||typeof value.replay!=='boolean'||typeof value.equivalent_active_request!=='boolean'||value.replay&&!value.equivalent_active_request||!value.equivalent_active_request&&value.request_id!==submission))throw fault('protocol_unavailable');
 return Object.freeze({requestId:value.request_id,acceptedAt:value.accepted_at});
}
function review(value,requestId){
 const keys=['contract_version','scope','request_id','checked_at','revision','review_state','outcome_code','outcome_recorded_at','completion','blocking_reason','policy_acceptance_granted','subject_scope_review_pending','legal_hold_review_pending','copy_dispositions_verified','destructive_execution_available','erasure_completed','account_access_restricted','auth_removed','processor_operation_started'];
 const states=['not_started','awaiting_review','claim_active','claim_expired','blocked'];
 if(!value||typeof value!=='object'||Object.keys(value).length!==keys.length||keys.some(k=>!Object.hasOwn(value,k))||value.contract_version!==1||value.scope!=='own_account_privacy_review'||value.request_id!==requestId||!instant(value.checked_at)||!states.includes(value.review_state)||!Number.isSafeInteger(value.revision)||value.revision<0||value.revision>1000000000||value.completion!=='blocked'||value.blocking_reason!=='policy_authority_unavailable'||value.subject_scope_review_pending!==true||value.legal_hold_review_pending!==true||['policy_acceptance_granted','copy_dispositions_verified','destructive_execution_available','erasure_completed','account_access_restricted','auth_removed','processor_operation_started'].some(k=>value[k]!==false))throw fault('protocol_unavailable');
 const blocked=value.review_state==='blocked';
 if((['not_started','awaiting_review'].includes(value.review_state)&&value.revision!==0)||(!['not_started','awaiting_review'].includes(value.review_state)&&value.revision===0)||(blocked?(value.revision<2||value.outcome_code!=='policy_authority_unavailable'||!instant(value.outcome_recorded_at)||value.outcome_recorded_at>value.checked_at):(value.outcome_code!==null||value.outcome_recorded_at!==null)))throw fault('protocol_unavailable');
 return Object.freeze({state:value.review_state,checkedAt:value.checked_at});
}
export function captchaEnvelope(event,{origin,source,attempt}){
 if(event.origin!==origin||event.source!==source)return null;
 let value=event.data;if(typeof value==='string'){if(value.length>4096)throw fault('captcha_unavailable');try{value=JSON.parse(value);}catch{throw fault('captcha_unavailable');}}
 if(!value||typeof value!=='object'||value.attempt_id!==attempt)return null;
 if(value.type!=='collect.turnstile.v1'||Object.keys(value).length!==3||typeof value.token!=='string'||value.token.length<1||value.token.length>2048||/[\x00-\x20\x7f]/.test(value.token)||Object.hasOwn(value,'error'))throw fault('captcha_unavailable');
 return value.token;
}
// Memory-only dedicated email verification. The ordinary intake/checkpoint
// controller below remains the only account-deletion submission owner.
const EMAIL_PURPOSE='account_deletion_request';
const EMAIL_ISSUER='https://rrlduytparvsjfmegalh.supabase.co/auth/v1';
function emailContext(){const bytes=crypto.getRandomValues(new Uint8Array(32));return btoa(String.fromCharCode(...bytes)).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');}
function emailObject(v){return v!==null&&typeof v==='object'&&!Array.isArray(v);}
function emailKeys(v,keys){return emailObject(v)&&Object.keys(v).length===keys.length&&keys.every(k=>Object.hasOwn(v,k));}
function emailEnvelope(v,a){if(v?.contract_version!==1||v.purpose!==EMAIL_PURPOSE||v.mode!=='portal_bootstrap'||v.identity_type!=='email'||v.channel!=='email'||v.challenge_id!==a.id||v.challenge_context!==a.context)throw fault('privacy_email_unconfirmed');}
function emailDescriptor(v,a,at){
 emailEnvelope(v,a);
 const keys=['contract_version','purpose','mode','identity_type','channel','challenge_id','challenge_context','destination_hint','retry_after','created_at','expires_at','delivery_status','verification_state','operation_id','cancelled','candidate_cleanup'];
 if(!emailKeys(v,keys)||typeof v.destination_hint!=='string'||v.destination_hint.length>254||!v.destination_hint.includes('***')||/[\x00-\x1f\x7f]/.test(v.destination_hint)||v.retry_after!==60||!Number.isSafeInteger(v.created_at)||v.created_at<=0||v.created_at>at||!Number.isSafeInteger(v.expires_at)||v.expires_at<=v.created_at||v.expires_at>v.created_at+300||v.delivery_status!=='not_disclosed'||!['not_started','verifying','rejected','unconfirmed','verified'].includes(v.verification_state)||typeof v.cancelled!=='boolean'||!['not_required','confirmed','unconfirmed'].includes(v.candidate_cleanup)||v.operation_id!==null&&!UUID.test(v.operation_id)||a.operation&&v.operation_id!==a.operation&&!(v.operation_id===null&&v.verification_state==='not_started'))throw fault('privacy_email_unconfirmed');
 return Object.freeze({...v});
}
function emailCandidate(value,a,at){
 emailEnvelope(value,a);
 const proof=value.purpose_proof,event=value.auth_event,d=a.descriptor,user=value.user;
 const proofKeys=['purpose','challenge_id','user_id','auth_user_id','initiating_session_id','session_id','method','authenticated_at','expires_at'];
 if(value.operation_id!==a.operation||!emailKeys(event,['method','timestamp'])||event.method!=='otp'||!Number.isSafeInteger(event.timestamp)||event.timestamp<=0||event.timestamp<d.created_at||event.timestamp>d.expires_at||event.timestamp>at||!emailKeys(proof,proofKeys)||proof.purpose!==EMAIL_PURPOSE||proof.challenge_id!==a.id||proof.initiating_session_id!==null||proof.method!=='otp'||proof.authenticated_at!==event.timestamp||proof.expires_at!==d.expires_at||!emailObject(user)||!UUID.test(user.id)||!UUID.test(user.auth_user_id)||proof.user_id!==user.id||proof.auth_user_id!==user.auth_user_id||user.is_anonymous===true||typeof user.email!=='string'||user.email.trim().toLowerCase()!==a.email||typeof user.email_confirmed_at!=='string'||!Number.isFinite(Date.parse(user.email_confirmed_at))||value.token_type!=='bearer'||typeof value.access_token!=='string'||!value.access_token||value.access_token.length>16384||/\s/.test(value.access_token)||typeof value.refresh_token!=='string'||!value.refresh_token||value.refresh_token.length>4096||/\s/.test(value.refresh_token))throw fault('privacy_email_unconfirmed');
 let claims;try{const parts=value.access_token.split('.');if(parts.length!==3)throw 0;const bytes=Uint8Array.from(atob(parts[1].replace(/-/g,'+').replace(/_/g,'/')),c=>c.charCodeAt(0));claims=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));}catch{throw fault('privacy_email_unconfirmed');}
 if(claims.sub!==user.auth_user_id||claims.iss!==EMAIL_ISSUER||claims.aud!=='authenticated'||claims.role!=='authenticated'||!UUID.test(claims.session_id)||proof.session_id!==claims.session_id||!Number.isSafeInteger(claims.exp)||!Array.isArray(claims.amr)||!claims.amr.some(e=>emailObject(e)&&e.method==='otp'&&Number.isSafeInteger(e.timestamp)&&e.timestamp===event.timestamp))throw fault('privacy_email_unconfirmed');
 return Object.freeze({token:value.access_token,userId:user.id,authUserId:user.auth_user_id,sessionId:claims.session_id,expiresAt:claims.exp,authAt:event.timestamp});
}
export function createPrivacyEmailVerification({request,challenge,randomUUID,randomContext=emailContext,now=Date.now}){
 let attempt=null,generation=0;
 const at=()=>Math.floor(now()/1000);
 function current(a){if(a.cancelled||a.epoch!==generation||a.adopted)throw fault('cancelled');}
 const base=a=>({contract_version:1,purpose:EMAIL_PURPOSE,mode:'portal_bootstrap',challenge_id:a.id,challenge_context:a.context});
 function canStart(){return !attempt||attempt.cancelled||attempt.adopted||!attempt.busy&&!attempt.unknown&&attempt.descriptor&&['not_started','rejected'].includes(attempt.descriptor.verification_state)&&at()>=attempt.descriptor.created_at+60;}
 function ready(){const a=attempt,d=a?.descriptor;return !!(a&&d&&!a.cancelled&&!a.adopted&&!a.unknown&&!d.cancelled&&at()<=d.expires_at&&['not_started','rejected'].includes(d.verification_state));}
 async function captcha(a){const token=await challenge();current(a);if(typeof token!=='string'||!token||token.length>2048||/[\x00-\x20\x7f]/.test(token))throw fault('captcha_unavailable');return token;}
 async function cleanup(a){
  if(a.adopted||a.cleanupStarted||!a.candidate)return a.cleanup;
  a.cleanupStarted=true;a.cleanup='unconfirmed';
  try{const result=await request('/v1/privacy/email/cancel',{...base(a),operation_id:a.operation,candidate_access_token:a.candidate.token},null);if(result.status===200&&emailDescriptor(result.body,a,at()).candidate_cleanup==='confirmed')a.cleanup='confirmed';}catch{}
  a.candidate=null;return a.cleanup;
 }
 return {
  get state(){const a=attempt;return Object.freeze({ready:ready(),canStart:canStart(),pending:!!a&&!a.cancelled&&!a.adopted,unknown:!!a?.unknown,hint:a?.descriptor?.destination_hint??'',cooldownUntil:((a?.descriptor?.created_at??a?.started??0)+60)*1000,cleanup:a?.cleanup??'not_required'});},
  async start(address){
   if(!canStart())throw fault('privacy_email_unconfirmed');
   const target=address??attempt?.email;if(typeof target!=='string'||target.length>254||!/^\S+@[^\s@]+\.[^\s@]+$/.test(target.trim()))throw fault('invalid_email');
   const id=randomUUID(),context=randomContext();if(!UUID.test(id)||typeof context!=='string'||!/^[A-Za-z0-9_-]{43}$/.test(context))throw fault('protocol_unavailable');
   let raw;try{raw=atob(context.replace(/-/g,'+').replace(/_/g,'/')+'=');}catch{throw fault('protocol_unavailable');}if(raw.length!==32||btoa(raw).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'')!==context)throw fault('protocol_unavailable');
   const a={id,context,email:target.trim().toLowerCase(),epoch:++generation,started:at(),operation:null,descriptor:null,busy:true,unknown:true,cancelled:false,adopted:false,candidate:null,cleanup:'not_required',cleanupStarted:false};attempt=a;
   let dispatched=false;
   try{const token=await captcha(a);dispatched=true;const response=await request('/v1/privacy/email/challenge',{...base(a),email:a.email,allow_registration:false,should_create_user:false,captcha_token:token},null);current(a);if(response.status!==202)throw fault('privacy_email_unconfirmed');a.descriptor=emailDescriptor(response.body,a,at());a.unknown=false;}
   catch(error){if(!dispatched){a.cancelled=true;a.unknown=false;}throw error;}
   finally{a.busy=false;}
  },
  async verify(code,install){
   const a=attempt;if(!a||a.busy||!ready())throw fault('privacy_email_unconfirmed');if(typeof code!=='string'||!/^\d{6,10}$/.test(code))throw fault('invalid_code');current(a);
   const operation=randomUUID();if(!UUID.test(operation))throw fault('protocol_unavailable');a.operation=operation;a.busy=true;a.unknown=true;
   let dispatched=false;
   try{
    const token=await captcha(a);dispatched=true;const response=await request('/v1/privacy/email/verify',{...base(a),operation_id:operation,code,captcha_token:token},null);
    if([401,429].includes(response.status)&&response.body?.code==='privacy_email_code_rejected'){
     const value={...response.body};delete value.code;delete value.message;const d=emailDescriptor(value,a,at());current(a);if(d.verification_state!=='rejected')throw fault('privacy_email_unconfirmed');a.descriptor=d;a.unknown=false;throw fault(response.status===429?'rate_limited':'invalid_code');
    }
    if(response.status!==200||!response.body?.access_token)throw fault('privacy_email_unconfirmed');
    a.candidate=emailCandidate(response.body,a,at());current(a);
    if(at()>a.descriptor.expires_at||at()-a.candidate.authAt>300||a.candidate.expiresAt<=at()+15)throw fault('privacy_email_unconfirmed');
    // The caller compares its own generation and marks actual synchronous
    // installation before it can perform any status read or await.
    install(a.candidate,()=>{a.adopted=true;});if(!a.adopted)throw fault('privacy_email_unconfirmed');a.unknown=false;
   }catch(error){if(!dispatched){a.operation=null;a.unknown=false;}throw error;}
   finally{a.busy=false;if(a.candidate&&!a.adopted)await cleanup(a);if(a.adopted)a.candidate=null;}
  },
  async status(){const a=attempt;if(!a||a.busy||a.adopted||a.cancelled)throw fault('privacy_email_unconfirmed');current(a);a.busy=true;try{const response=await request('/v1/privacy/email/status',{...base(a),...(a.operation?{operation_id:a.operation}:{})},null);current(a);if(response.status!==200)throw fault('privacy_email_unconfirmed');a.descriptor=emailDescriptor(response.body,a,at());a.unknown=!!a.operation&&a.descriptor.verification_state!=='rejected'||['verifying','unconfirmed','verified'].includes(a.descriptor.verification_state);}finally{a.busy=false;}},
  async cancel(){const a=attempt;++generation;if(!a||a.adopted||a.cancelled)return a?.cleanup??'not_required';a.cancelled=true;if(a.candidate)return cleanup(a);a.cleanup=a.operation?'unconfirmed':'not_required';try{const response=await request('/v1/privacy/email/cancel',{...base(a),...(a.operation?{operation_id:a.operation}:{})},null);if(response.status===200)a.cleanup=emailDescriptor(response.body,a,at()).candidate_cleanup;}catch{if(a.operation)a.cleanup='unconfirmed';}return a.cleanup;},
 };
}

export async function portalEmailRequest(path,body,token){
 if(!['/v1/privacy/email/challenge','/v1/privacy/email/verify','/v1/privacy/email/status','/v1/privacy/email/cancel'].includes(path)||token!==null)throw fault('protocol_unavailable');
 const abort=new AbortController(),timer=setTimeout(()=>abort.abort(),20000);
 try{
  const response=await fetch(path,{method:'POST',credentials:'omit',cache:'no-store',redirect:'error',referrerPolicy:'no-referrer',headers:{'Content-Type':'application/json','Accept':'application/json'},body:JSON.stringify(body),signal:abort.signal});
  if(Number(response.headers.get('content-length'))>32768)throw fault('privacy_email_unconfirmed');
  const reader=response.body?.getReader();if(!reader)throw fault('privacy_email_unconfirmed');let size=0;const chunks=[];
  try{while(true){const next=await reader.read();if(next.done)break;size+=next.value.byteLength;if(size>32768)throw fault('privacy_email_unconfirmed');chunks.push(next.value);}}finally{await reader.cancel().catch(()=>{});}
  const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.byteLength;}
  const value=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));if(!emailObject(value))throw fault('privacy_email_unconfirmed');
  return {status:response.status,body:value};
 }catch{throw fault('privacy_email_unconfirmed');}finally{clearTimeout(timer);}
}

// These are presentation checks on the current managed Auth response. Every
// request/status operation still verifies the bearer and principal on the server.
function managedPortalSession(value,phone,at){
 let claims;try{if(typeof value?.access_token!=='string'||value.access_token.length>4096||value.access_token.split('.').length!==3)throw fault('protocol_unavailable');const encoded=value.access_token.split('.')[1].replace(/-/g,'+').replace(/_/g,'/');claims=JSON.parse(atob(encoded));}catch{throw fault('protocol_unavailable');}
 const user=value?.user,canonicalPhone=typeof user?.phone==='string'?(user.phone.startsWith('+')?user.phone:'+'+user.phone):null;
 if(!user||!UUID.test(user.id)||!UUID.test(user.auth_user_id)||canonicalPhone!==phone||user.is_anonymous===true||typeof user.phone_confirmed_at!=='string'||!Number.isFinite(Date.parse(user.phone_confirmed_at))||value.token_type!=='bearer'||claims.sub!==user.auth_user_id||!UUID.test(claims.session_id)||claims.role!=='authenticated'||!(claims.aud==='authenticated'||Array.isArray(claims.aud)&&claims.aud.includes('authenticated'))||!Number.isSafeInteger(claims.exp)||claims.exp<=at+15||value.expires_at!==undefined&&value.expires_at!==claims.exp||value.expires_in!==undefined&&(!Number.isSafeInteger(value.expires_in)||value.expires_in<1)||!Number.isSafeInteger(claims.iat)||claims.iat<0||claims.iat>at+30||!Array.isArray(claims.amr)||claims.amr.length<1||claims.amr.length>16||!claims.amr.every(item=>item&&typeof item.method==='string'&&Number.isSafeInteger(item.timestamp)&&item.timestamp>=0&&item.timestamp<=at+30)||!claims.amr.some(item=>item.method==='otp'))throw fault('protocol_unavailable');
 // Match projectSession's earliest AMR/iat freshness; a new token must never
 // make an old authentication appear fresh. The legacy principal remains the
 // checkpoint identity, distinct from the managed JWT subject.
 const authAt=Math.min(claims.iat,...claims.amr.map(item=>item.timestamp));
 if(at-authAt>300)throw fault('protocol_unavailable');
 return {token:value.access_token,userId:user.id,sessionId:claims.session_id,expiresAt:claims.exp,authAt};
}

export function createPrivacyPortalController({request,challenge,randomUUID,now=Date.now,checkpoint={read:()=>null,write:()=>{},clear:()=>{}},changed=()=>{},phoneAvailable=true,emailAvailable=false,emailRequest=portalEmailRequest,emailRandomContext=emailContext}){
 const initialMode=!phoneAvailable&&emailAvailable?'email':'phone';
 let state={step:initialMode,verification:initialMode,busy:false,message:'',error:'',receipt:null,review:null,unknown:false,canRetry:false,cooldownUntil:0,signedIn:false};
 let session=null,phone='',challengeId=null,pending=null,generation=0;
 const emailFlow=createPrivacyEmailVerification({request:emailRequest,challenge,randomUUID,randomContext:emailRandomContext,now});
 const view=()=>Object.freeze({...state});
 const publish=()=>changed(view());
 function saved(){try{const p=checkpoint.read();return p&&Object.keys(p).length===3&&p.version===1&&UUID.test(p.subject_id)&&UUID.test(p.submission_id)?p:null;}catch{return null;}}
 function remember(){try{if(pending)checkpoint.write({version:1,subject_id:session.userId,submission_id:pending});}catch{/* Status remains recoverable after identity verification. */}}
 function clearLocal({keepCheckpoint=false,cancelEmail=true}={}){generation++;if(cancelEmail)void emailFlow.cancel();session=null;phone='';challengeId=null;pending=null;state={...state,step:initialMode,verification:initialMode,busy:false,receipt:null,review:null,unknown:false,canRetry:false,signedIn:false};if(!keepCheckpoint)try{checkpoint.clear();}catch{}publish();}
 function fence(expected){if(expected!==generation)throw fault('cancelled');}
 function live({fresh=false}={}){if(!session||session.expiresAt<=Math.floor(now()/1000)+15)throw fault('session_changed');if(fresh&&Math.floor(now()/1000)-session.authAt>300)throw fault('fresh_auth_required');return session;}
 async function call(path,body,epoch,token=null){const result=await request(path,body,token);fence(epoch);if(token){if(session?.token!==token)throw fault('session_changed');live();}return result;}
 function message(error){const code=error?.code;return ({invalid_email:'Enter the email registered with Collect.',privacy_email_unconfirmed:'Email verification is unconfirmed. Check the original verification. Status cannot recover a lost sign-in session.',invalid_phone:'Enter your registered Rwanda number in +250 format.',invalid_code:'The code is invalid or expired. Check it and try again.',otp_expired:'The code has expired. Request a new code.',captcha_cancelled:'Verification was cancelled. Try again when you are ready.',captcha_unavailable:'Security verification could not finish. Try again or contact support.',captcha_required:'Complete security verification before continuing.',captcha_failed:'Security verification expired. Try again.',rate_limited:'Wait before trying again.',privacy_request_conflict:'A request with different details already exists. Check status or contact support.',privacy_request_submission_limit:'A request limit was reached. Check status or contact support.',session_changed:'Verify your identity again to continue. Your earlier request may still have been received.',fresh_auth_required:'Verify your identity again before submitting.',protocol_unavailable:'The service returned an unconfirmed result. Check status or contact support.',otp_delivery_unknown:'Code delivery could not be confirmed. If a code arrives, enter it before requesting another.',otp_delivery_unavailable:'Code delivery is unavailable. Contact support to request deletion.',auth_configuration_missing:'Verification is unavailable. Contact support to request deletion.',invalid_token:'Your sign-in has expired. Verify your identity again.',access_revoked:'Your sign-in is unavailable. Contact support for identity verification.'})[code]||'The service is unavailable. Check your connection or contact support.';}
 async function work(action){if(state.busy)throw fault('busy');const epoch=generation;state={...state,busy:true,error:'',message:''};publish();try{return await action(epoch);}catch(error){if(epoch===generation){if(['session_changed','fresh_auth_required','invalid_token','access_revoked'].includes(error?.code))clearLocal({keepCheckpoint:true});state={...state,error:message(error)};publish();}throw error;}finally{if(epoch===generation){state={...state,busy:false};publish();}}}
 async function freshChallenge(epoch){const value=await challenge();fence(epoch);if(typeof value!=='string'||!value||value.length>2048||/[\x00-\x20\x7f]/.test(value))throw fault('captcha_unavailable');return value;}
 async function check(epoch){
  const active=live(),token=active.token;state={...state,canRetry:false,review:null};let value=null;
  if(pending){try{value=await call('/v1/rpc/get_account_deletion_request_status_v1',{p_request_id:pending},epoch,token);}catch(error){if(error?.status!==404||error?.code!=='privacy_request_unavailable')throw error;}}
  if(value===null)value=await call('/v1/rpc/get_current_account_deletion_request_status_v1',{},epoch,token);
  if(value===null){if(state.receipt)throw fault('protocol_unavailable');state={...state,step:state.unknown?'unknown':'request',canRetry:state.unknown,message:state.unknown?'No receipt was confirmed. You may explicitly retry the same request.':'Identity verified. You can request deletion for review.'};return;}
  const accepted=receipt(value);if(state.receipt&&state.receipt.requestId!==accepted.requestId)throw fault('protocol_unavailable');
  state={...state,step:'received',receipt:accepted,unknown:false,canRetry:false,message:'Request received for review. Your account and records have not been erased.'};try{checkpoint.clear();}catch{}
  try{const observed=await call('/v1/rpc/get_account_deletion_review_status_v1',{p_request_id:accepted.requestId},epoch,token);state={...state,review:review(observed,accepted.requestId)};}catch(error){fence(epoch);if(['invalid_token','access_revoked','session_changed'].includes(error?.code))throw error;state={...state,error:'Your request was received, but its review status could not be confirmed. Check status again.'};}
 }
 return {
  get state(){return view();},
  chooseEmail(){if(!emailAvailable||state.busy||session)throw fault('unavailable');generation++;phone='';challengeId=null;state={...state,step:'email',verification:'email',message:'Use your registered email. This does not create an account.',error:''};publish();},
  choosePhone(){if(!phoneAvailable||state.busy||session)throw fault('unavailable');generation++;void emailFlow.cancel();state={...state,step:'phone',verification:'phone',message:'',error:''};publish();},
  async requestEmailCode(address){return work(async epoch=>{
   if(!emailAvailable||session)throw fault('unavailable');
   try{await emailFlow.start(address);fence(epoch);state={...state,step:'email-code',verification:'email',message:'If the account can be verified, an email code may arrive. Delivery is not disclosed.'};}
   finally{if(epoch===generation){const e=emailFlow.state;state={...state,cooldownUntil:e.cooldownUntil,emailCanStart:e.canStart};if(e.unknown)state={...state,step:'email-unknown'};}}
  });},
  async verifyEmailCode(code){return work(async epoch=>{
   try{
    await emailFlow.verify(code,(candidate,markInstalled)=>{fence(epoch);if(session)throw fault('session_changed');session=candidate;markInstalled();});
    fence(epoch);phone='';challengeId=null;
    const previous=saved();if(previous&&previous.subject_id===session.userId){pending=previous.submission_id;state={...state,unknown:true};}else{try{checkpoint.clear();}catch{}pending=null;}
    state={...state,signedIn:true};await check(epoch);
   }finally{if(epoch===generation&&!session){const e=emailFlow.state;state={...state,step:e.ready?'email-code':'email-unknown',emailCanStart:e.canStart};}}
  });},
  async checkEmailVerification(){return work(async epoch=>{
   await emailFlow.status();fence(epoch);const e=emailFlow.state;state={...state,step:e.ready?'email-code':'email-unknown',emailCanStart:e.canStart,cooldownUntil:e.cooldownUntil,message:e.ready?'If a code arrives, enter it here. Delivery is not disclosed.':'The verification result is unconfirmed. Status cannot recover a lost sign-in session.'};
  });},
  async requestCode(number){return work(async epoch=>{
   if(!phoneAvailable)throw fault('unavailable');
   if(typeof number!=='string'||!/^\+2507[2389][0-9]{7}$/.test(number))throw fault('invalid_phone');
   if(now()<state.cooldownUntil)throw fault('rate_limited');
   if(session)throw fault('session_changed');
   phone=number;challengeId=null;
   const captcha=await freshChallenge(epoch);state={...state,cooldownUntil:now()+60000};
   let value;try{value=await call('/v1/auth/otp',{phone,surface:'member',channel:'whatsapp',allow_registration:false,should_create_user:false,captcha_token:captcha},epoch);}catch(error){if(error?.code==='otp_delivery_unknown'||!error?.status||error.status>=500){state={...state,step:'phone',message:'Code delivery could not be confirmed. Wait before requesting a new code, or contact support.'};return;}throw error;}
   const keys=['challenge_id','retry_after','expires_in','channel','delivery_status'];
   if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).length!==keys.length||keys.some(key=>!Object.hasOwn(value,key))||!UUID.test(value.challenge_id)||value.channel!=='whatsapp'||!['accepted','unknown'].includes(value.delivery_status)||!Number.isSafeInteger(value.retry_after)||value.retry_after<1||value.retry_after>3600||!Number.isSafeInteger(value.expires_in)||value.expires_in<1||value.expires_in>3600)throw fault('protocol_unavailable');
   challengeId=value.challenge_id;
   state={...state,step:'code',cooldownUntil:now()+value.retry_after*1000,message:value.delivery_status==='unknown'?'Delivery could not be confirmed. If a code arrives, enter it before requesting another.':'If this account can be verified, a code will be sent. Enter it here.'};
  });},
  async verifyCode(code){return work(async epoch=>{
   if(!phoneAvailable)throw fault('unavailable');
   if(!challengeId||typeof code!=='string'||!/^\d{6}$/.test(code))throw fault('invalid_code');
   const captcha=await freshChallenge(epoch),value=await call('/v1/auth/verify',{phone,surface:'member',challenge_id:challengeId,code,captcha_token:captcha},epoch);
   session=managedPortalSession(value,phone,Math.floor(now()/1000));phone='';challengeId=null;
   const previous=saved();if(previous&&previous.subject_id===session.userId){pending=previous.submission_id;state={...state,unknown:true};}else{try{checkpoint.clear();}catch{}pending=null;}
   state={...state,signedIn:true};await check(epoch);
  });},
  async checkStatus(){return work(check);},
  async reviewRequest(){return work(async()=>{live({fresh:true});if(state.receipt||state.unknown||state.step!=='request')throw fault('unavailable');state={...state,step:'confirm',error:''};});},
  back(){if(state.busy)return;if(state.step==='confirm'){state={...state,step:'request'};publish();}},
  async submit({retry=false}={}){return work(async epoch=>{
   const active=live({fresh:true});if(state.receipt||(retry?(!state.unknown||!state.canRetry):state.step!=='confirm'))throw fault('unavailable');
   pending??=randomUUID();remember();state={...state,step:'unknown',unknown:true,canRetry:false};publish();
   const value=await call('/v1/rpc/request_account_deletion_v1',{p_request_id:pending,p_reason:null},epoch,active.token);
   const accepted=receipt(value,pending);state={...state,receipt:accepted,unknown:false,canRetry:false,step:'received',message:'Request received for review. Your account and records have not been erased.'};try{checkpoint.clear();}catch{}
   await check(epoch);
  });},
  tick(){state={...state,emailCanStart:emailFlow.state.canStart};if(session&&session.expiresAt<=Math.floor(now()/1000)+15){clearLocal({keepCheckpoint:true});state={...state,error:message(fault('session_changed'))};}publish();},
  async clear(){const token=session?.token,cleanup=emailFlow.cancel();clearLocal({cancelEmail:false});const epoch=generation;state={...state,error:'',message:'This page has been cleared.'};publish();const cleanupState=await cleanup;if(cleanupState==='unconfirmed'&&epoch===generation&&state.step===initialMode&&!state.busy&&!state.signedIn){state={...state,message:'This page has been cleared. Candidate sign-out could not be confirmed.'};publish();}if(token)try{await request('/v1/auth/logout',{},token);}catch{if(epoch!==generation||state.step!==initialMode||state.busy||state.signedIn)return;state={...state,message:'This page has been cleared. Server sign-out could not be confirmed; close the page and contact support if needed.'};publish();}},
  destroy(){clearLocal({keepCheckpoint:true});},
 };
}

export async function portalRequest(path,body,token){
 const paths=['/v1/auth/otp','/v1/auth/verify','/v1/auth/logout','/v1/rpc/request_account_deletion_v1','/v1/rpc/get_account_deletion_request_status_v1','/v1/rpc/get_current_account_deletion_request_status_v1','/v1/rpc/get_account_deletion_review_status_v1'];
 if(!paths.includes(path))throw fault('unavailable');
 const abort=new AbortController(),timeout=setTimeout(()=>abort.abort(),20000);
 try{const response=await fetch(path,{method:'POST',credentials:'omit',cache:'no-store',redirect:'error',referrerPolicy:'no-referrer',headers:{'Content-Type':'application/json','Accept':'application/json',...(token?{Authorization:'Bearer '+token}:{})},body:JSON.stringify(body),signal:abort.signal});
  const text=await response.text();if(text.length>32768)throw fault('protocol_unavailable');let value;try{value=JSON.parse(text);}catch{throw fault('protocol_unavailable');}
  if(!response.ok){const error=fault(typeof value?.error?.code==='string'?value.error.code:typeof value?.code==='string'?value.code:'unavailable');error.status=response.status;if(UUID.test(value?.challenge_id))error.challengeId=value.challenge_id;throw error;}return value;
 }finally{clearTimeout(timeout);}
}

export function mountPrivacyPortal(){
 const phoneAvailable=document.body.dataset.verificationAvailable!=='false',emailAvailable=document.body.dataset.emailVerificationAvailable==='true';
 if(!phoneAvailable&&!emailAvailable)return;
 const $=id=>document.getElementById(id),page=$('page'),dialog=$('verification');let activeChallenge=null,returnFocus=null;const text=(id,value)=>{if($(id).textContent!==value)$(id).textContent=value;};
 function cancelChallenge(){activeChallenge?.cancel();}
 function acquireChallenge(){
  if(activeChallenge)return Promise.reject(fault('captcha_unavailable'));
  return new Promise((resolve,reject)=>{
   const attempt=crypto.randomUUID(),previous=document.activeElement,frame=document.createElement('iframe');frame.title='Collect security verification';frame.referrerPolicy='no-referrer';frame.setAttribute('sandbox','allow-scripts allow-same-origin');
   const url=new URL('/v1/security/challenge',location.origin);url.search=new URLSearchParams({attempt_id:attempt,parent_origin:location.origin,theme:'auto'}).toString();frame.src=url.href;
   let done=false;const cleanup=()=>{clearTimeout(timer);window.removeEventListener('message',receive);dialog.removeEventListener('cancel',cancel);$('cancel-verification').removeEventListener('click',cancel);frame.remove();if(dialog.open&&dialog.close)dialog.close();dialog.removeAttribute('open');dialog.removeAttribute('data-fallback');page.inert=false;page.removeAttribute('aria-hidden');dialog.hidden=true;activeChallenge=null;if(previous?.isConnected){returnFocus=previous;if(!previous.disabled)previous.focus();}};
   function finish(error,value){if(done)return;done=true;cleanup();error?reject(error):resolve(value);}
   function cancel(event){event?.preventDefault();finish(fault('captcha_cancelled'));}
   function receive(event){if(done||activeChallenge?.attempt!==attempt)return;try{const token=captchaEnvelope(event,{origin:location.origin,source:frame.contentWindow,attempt});if(token!==null)finish(null,token);}catch(error){finish(error);}}
   const timer=setTimeout(()=>finish(fault('captcha_unavailable')),120000);activeChallenge={attempt,cancel};window.addEventListener('message',receive);dialog.addEventListener('cancel',cancel);$('cancel-verification').addEventListener('click',cancel);dialog.insertBefore(frame,$('cancel-verification'));dialog.hidden=false;
   try{if(typeof dialog.showModal==='function')dialog.showModal();else{dialog.setAttribute('open','');dialog.setAttribute('data-fallback','');page.inert=true;page.setAttribute('aria-hidden','true');}$('cancel-verification').focus();}catch{finish(fault('captcha_unavailable'));}
  });
 }
 const checkpoint={read(){const raw=sessionStorage.getItem('collect.privacy.portal.v1');if(raw&&raw.length>512)return null;return raw?JSON.parse(raw):null;},write(value){sessionStorage.setItem('collect.privacy.portal.v1',JSON.stringify(value));},clear(){sessionStorage.removeItem('collect.privacy.portal.v1');}};
 let lastStep='phone';
 const controller=createPrivacyPortalController({request:portalRequest,challenge:acquireChallenge,randomUUID:()=>crypto.randomUUID(),checkpoint,phoneAvailable,emailAvailable,changed(state){
  for(const step of ['phone','code','email','email-code','email-unknown','request','confirm','unknown','received'])$('step-'+step).hidden=state.step!==step;
  $('use-email').hidden=!emailAvailable||state.signedIn||state.verification==='email';text('status',state.message);text('error',state.error);if(state.signedIn){$('phone').value='';$('code').value='';$('email').value='';$('email-code').value='';}$('error').hidden=!state.error;page.setAttribute('aria-busy',String(state.busy));
  for(const element of page.querySelectorAll('button,input'))element.disabled=state.busy;
  $('clear').disabled=false;$('retry-request').disabled=state.busy||!state.canRetry;$('clear').hidden=!state.signedIn&&['phone','email'].includes(state.step);
  const seconds=Math.max(0,Math.ceil((state.cooldownUntil-Date.now())/1000));$('resend-code').disabled=state.busy||seconds>0;text('resend-code',seconds?'Send new code in '+seconds+'s':'Send new code');$('email-resend').disabled=state.busy||seconds>0||!state.emailCanStart;text('email-resend',seconds?'Send new code in '+seconds+'s':'Send new code');
  if(state.receipt){$('reference').textContent=state.receipt.requestId;$('accepted-at').textContent=new Date(state.receipt.acceptedAt).toLocaleString();$('review-state').textContent=state.review?({not_started:'Review has not started',awaiting_review:'Awaiting review',claim_active:'A review is in progress',claim_expired:'Review needs to resume',blocked:'Waiting for approved retention policy'})[state.review.state]:'Review status not confirmed';}
  if(!state.busy&&state.step!==lastStep){lastStep=state.step;const heading=$('step-'+state.step).querySelector('h2');returnFocus=null;heading?.focus();}else if(!state.busy&&returnFocus?.isConnected&&!returnFocus.disabled&&returnFocus.offsetParent!==null){returnFocus.focus();returnFocus=null;}
 }});
 const handle=action=>{Promise.resolve().then(action).catch(()=>{});};
 $('use-email').hidden=!emailAvailable;$('use-phone').hidden=!phoneAvailable;
 $('use-email').addEventListener('click',()=>handle(()=>controller.chooseEmail()));
 $('use-phone').addEventListener('click',()=>handle(()=>controller.choosePhone()));
 $('email-form').addEventListener('submit',event=>{event.preventDefault();handle(()=>controller.requestEmailCode($('email').value));});
 $('email-code-form').addEventListener('submit',event=>{event.preventDefault();const code=$('email-code').value.trim();$('email-code').value='';handle(()=>controller.verifyEmailCode(code));});
 $('email-resend').addEventListener('click',()=>handle(()=>controller.requestEmailCode()));
 $('email-check').addEventListener('click',()=>handle(()=>controller.checkEmailVerification()));
 $('email-cancel').addEventListener('click',()=>{cancelChallenge();$('email-code').value='';handle(()=>controller.clear());});
 if(!phoneAvailable&&emailAvailable)controller.chooseEmail();
 $('phone-form').addEventListener('submit',event=>{event.preventDefault();handle(()=>controller.requestCode($('phone').value.trim()));});
 $('code-form').addEventListener('submit',event=>{event.preventDefault();const code=$('code').value.trim();$('code').value='';handle(()=>controller.verifyCode(code));});
 $('resend-code').addEventListener('click',()=>handle(()=>controller.requestCode($('phone').value.trim(),{newAttempt:true})));
 $('review-request').addEventListener('click',()=>handle(()=>controller.reviewRequest()));$('back-request').addEventListener('click',()=>controller.back());
 $('submit-request').addEventListener('click',()=>handle(()=>controller.submit()));$('retry-request').addEventListener('click',()=>handle(()=>controller.submit({retry:true})));
 for(const id of ['check-status','check-received'])$(id).addEventListener('click',()=>handle(()=>controller.checkStatus()));
 $('clear').addEventListener('click',()=>{cancelChallenge();$('phone').value='';$('code').value='';$('email').value='';$('email-code').value='';handle(()=>controller.clear());});
 const timer=setInterval(()=>controller.tick(),1000);window.addEventListener('pagehide',()=>{cancelChallenge();clearInterval(timer);$('phone').value='';$('code').value='';$('email').value='';$('email-code').value='';controller.destroy();},{once:true});
 window.addEventListener('pageshow',event=>{if(event.persisted)location.reload();});
}
if(typeof document!=='undefined')mountPrivacyPortal();
`;
