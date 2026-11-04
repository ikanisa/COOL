import {applicationWork} from './application-fence.js';
const sender='info@ikanisa.com';
const controls=/[\u0000-\u001f\u007f-\u009f]/;
const bodyControls=/[\u0000-\u0009\u000b-\u001f\u007f-\u009f]/;
const record=value=>value!==null&&typeof value==='object'&&!Array.isArray(value)&&
 (Object.getPrototypeOf(value)===Object.prototype||Object.getPrototypeOf(value)===null);

/** Safe errors carry no provider reply, message, address or credential. */
export class WorkspaceSmtpError extends Error {
 constructor(code='workspace_smtp_unknown') {
  const safeCode=['workspace_smtp_unavailable','workspace_smtp_invalid_message'].includes(code)?code:'workspace_smtp_unknown';
  super(safeCode==='workspace_smtp_unavailable'?'The email transport is unavailable.':'Email acceptance could not be confirmed.');
  this.name='WorkspaceSmtpError';this.code=safeCode;
  this.outcome=safeCode==='workspace_smtp_unavailable'?'unavailable':'unknown';
 }
}
const unavailable=()=>new WorkspaceSmtpError('workspace_smtp_unavailable');
const invalid=()=>new WorkspaceSmtpError('workspace_smtp_invalid_message');
function closed(value,allowed,required=allowed) {
 if(!record(value)||Reflect.ownKeys(value).some(key=>typeof key!=='string'||!allowed.includes(key)||
  !Object.hasOwn(Object.getOwnPropertyDescriptor(value,key),'value'))||required.some(key=>!Object.hasOwn(value,key)))throw invalid();
 return value;
}
function mailbox(value) {
 if(typeof value!=='string'||value.length>254||value!==value.toLowerCase()||controls.test(value))throw invalid();
 const parts=value.split('@');if(parts.length!==2)throw invalid();
 const [local,domain]=parts,labels=domain.split('.');
 if(!local||local.length>64||local.startsWith('.')||local.endsWith('.')||local.includes('..')||
  !/^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+$/.test(local)||labels.length<2||
  labels.some(label=>!/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(label)))throw invalid();
 return value;
}
function messageData(message) {
 closed(message,['from','to','subject','text','html'],['from','to','subject','text']);
 closed(message.from,['email','name']);
 if(message.from.email!==sender||message.from.name!=='Collect')throw invalid();
 const to=mailbox(message.to);
 if(typeof message.subject!=='string'||message.subject.length<1||message.subject.length>200||controls.test(message.subject)||
  typeof message.text!=='string'||message.text.length<1||message.text.length>20000||bodyControls.test(message.text)||
  message.html!==undefined&&(typeof message.html!=='string'||message.html.length>100000||bodyControls.test(message.html)))throw invalid();
 // Build a new object. No arbitrary headers/envelope, attachment, URL/file
 // content object, per-message auth or caller transport option is forwarded.
 return {from:{name:'Collect',address:sender},to:{address:to},subject:message.subject,text:message.text,
  ...(message.html===undefined?{}:{html:message.html}),envelope:{from:sender,to:[to]},
  disableFileAccess:true,disableUrlAccess:true};
}
function configuredPassword(env) {
 const password=env.COLLECT_NOTICE_SMTP_PASSWORD;
 if(typeof password!=='string'||!password||password.length>1024||password!==password.trim()||controls.test(password)||
  env.TRANSACTIONAL_EMAIL_URL!==undefined&&env.TRANSACTIONAL_EMAIL_URL!==null&&env.TRANSACTIONAL_EMAIL_URL!==''||
  env.TRANSACTIONAL_EMAIL_TOKEN!==undefined&&env.TRANSACTIONAL_EMAIL_TOKEN!==null&&env.TRANSACTIONAL_EMAIL_TOKEN!==''||
  env.AUTH_EMAIL_FROM!==undefined&&env.AUTH_EMAIL_FROM!==null&&env.AUTH_EMAIL_FROM!==sender)throw unavailable();
 return password;
}
function accepted(info,to) {
 if(!record(info)||typeof info.response!=='string'||info.response.length>4096||!/^250(?: [\x20-\x7e]+)?$/.test(info.response)||
  !Array.isArray(info.accepted)||info.accepted.length!==1||info.accepted[0]!==to||
  !Array.isArray(info.rejected)||info.rejected.length!==0||
  info.rejectedErrors!==undefined&&(!Array.isArray(info.rejectedErrors)||info.rejectedErrors.length!==0)||
  info.errors!==undefined&&(!Array.isArray(info.errors)||info.errors.length!==0)||
  info.pending!==undefined&&(!Array.isArray(info.pending)||info.pending.length!==0)||
  info.error!==undefined&&info.error!==null||!record(info.envelope)||info.envelope.from!==sender||
  !Array.isArray(info.envelope.to)||info.envelope.to.length!==1||info.envelope.to[0]!==to||
  typeof info.messageId!=='string'||!/^[\x21-\x7e]{1,256}$/.test(info.messageId))throw new WorkspaceSmtpError();
 return {messageId:info.messageId};
}

/** No SMTP connection is opened by configuration or factory construction. */
export function createWorkspaceSmtpEmail(env,{createTransport}={}) {
 let password;
 try{if(!record(env))throw unavailable();password=configuredPassword(env);}catch{throw unavailable();}
 if(typeof createTransport!=='function')throw unavailable();
 return Object.freeze({provider:'workspace_smtp_v1',async send(message) {
  let mail,transport;try{mail=messageData(message);}catch{throw invalid();}
  try {
   transport=createTransport({host:'smtp.gmail.com',port:465,secure:true,name:'collect.ikanisa.com',
    pool:false,logger:false,debug:false,transactionLog:false,
    connectionTimeout:3000,greetingTimeout:3000,socketTimeout:5000,dnsTimeout:3000,maxResponseSize:16384,
    requireTLS:true,ignoreTLS:false,opportunisticTLS:false,
    tls:{servername:'smtp.gmail.com',rejectUnauthorized:true,minVersion:'TLSv1.2'},
    auth:{type:'login',user:sender,pass:password},authMethod:'LOGIN',disableFileAccess:true,disableUrlAccess:true});
   if(!transport||typeof transport.sendMail!=='function')throw new WorkspaceSmtpError();
   // The pinned non-pooled transport resolves only after DATA's final response.
   // Generated Message-ID or envelope acceptance alone is never sufficient.
   const info=await applicationWork(env).dispatch('smtp',()=>transport.sendMail(mail));return accepted(info,mail.envelope.to[0]);
  }catch{throw new WorkspaceSmtpError();}
  finally {
   // close() releases local transport resources; it is NOT active-send abort.
   // The caller's existing 10s race can time out while this one send continues.
   // Its late resolution has no receipt authority and must never cause retry.
   try{if(typeof transport?.close==='function')transport.close();}catch{}
  }
 }});
}
