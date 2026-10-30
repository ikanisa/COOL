import {loadCredential,SafeError,UUID,object,unavailable} from './config.mjs';
import {parseSession,requestJson} from './api.mjs';
import {READ_RPC,WRITE_RPC,authorityBinding,assertBinding,instant} from './retention_contract.mjs';

function owns(credential,user){if(credential.accountId!==user.id||credential.sessionId!==user.sessionId||credential.principalId!==user.principalId)throw new SafeError('session_unavailable','The original local Admin session is unavailable. No operation was retried.');}
export function parseEmailProof(value,user,{fresh=true}={}){
 if(!object(value)||Object.keys(value).sort().join(',')!=='contractVersion,emailVerifiedAt,sessionId'||value.contractVersion!==1||value.sessionId!==user.sessionId||value.emailVerifiedAt!==null&&!instant(value.emailVerifiedAt))unavailable();
 const at=value.emailVerifiedAt===null?null:Date.parse(value.emailVerifiedAt),now=Date.now();
 if(at!==null&&at>now)unavailable();
 if(fresh&&(at===null||now-at>300000))throw new SafeError('recent_email_sign_in_required','Run npm run verify-email in a terminal to verify this same Admin session. Do not sign in again while an operation is unresolved.');
 return value;
}
export class RetentionApi {
 constructor(config){this.config=config;}
 async withSession(action,{fresh=true,privacy=true}={}){
  const credential=await loadCredential(this.config),beforeReply=await requestJson(this.config,'/api/admin/auth/session',{cookie:credential.cookie}),user=parseSession(beforeReply.value);
  owns(credential,user);
  if(privacy&&!user.permissions.includes('privacy.review'))throw new SafeError('permission_denied','The current Admin account lacks privacy.review.');
  const csrfToken=beforeReply.value.csrfToken;if(typeof csrfToken!=='string'||!/^[a-f0-9]{64}$/.test(csrfToken))unavailable();
  const proof=()=>requestJson(this.config,'/api/admin/auth/email-verification',{cookie:credential.cookie}).then(reply=>parseEmailProof(reply.value,user,{fresh}));
  const initialProof=await proof(),binding=authorityBinding(user,this.config.origin);
  const rpc=async(operation,body,allowed)=>{
   if(!allowed.includes(operation)||!object(body)||Buffer.byteLength(JSON.stringify(body))>16384)unavailable();
   return(await requestJson(this.config,'/api/admin/privacy/'+operation,{cookie:credential.cookie,csrfToken,method:'POST',body})).value;
  };
  const value=await action({binding,user,initialProof,
   read:(name,body={})=>{if(!privacy||!fresh)unavailable();return rpc(READ_RPC[name],body,Object.values(READ_RPC));},
   write:(name,body)=>{if(!privacy||!fresh)unavailable();return rpc(WRITE_RPC[name],body,Object.values(WRITE_RPC));},
   email:async(name,body)=>{
    if(privacy||fresh||!['request','verify'].includes(name))unavailable();
    return(await requestJson(this.config,'/api/admin/auth/email/'+name,{cookie:credential.cookie,csrfToken,method:'POST',body})).value;
   },
  });
  const latest=await loadCredential(this.config);if(latest.fingerprint!==credential.fingerprint)throw new SafeError('retention_session_changed','The local Admin credential changed. Keep the original operation references.');
  const after=parseSession((await requestJson(this.config,'/api/admin/auth/session',{cookie:credential.cookie})).value);owns(credential,after);assertBinding(authorityBinding(after,this.config.origin),binding);await proof();
  return value;
 }
 async verificationStatus(){return this.withSession(async({initialProof})=>initialProof,{fresh:false,privacy:false});}
 async requestVerification(captchaToken){
  if(typeof captchaToken!=='string'||captchaToken.length<1||captchaToken.length>2048||/[\u0000-\u0020\u007f]/.test(captchaToken))unavailable();
  return this.withSession(async({email})=>{
   const value=await email('request',{captcha_token:captchaToken});
   if(!object(value)||Object.keys(value).sort().join(',')!=='challenge_id,delivery_status,expires_in,retry_after'||!UUID.test(value.challenge_id??'')||!['accepted','unknown'].includes(value.delivery_status)||value.retry_after!==60||!Number.isInteger(value.expires_in)||value.expires_in<1||value.expires_in>300)unavailable();return value;
  },{fresh:false,privacy:false});
 }
 async verifyEmail(challengeId,code){
  if(!UUID.test(challengeId??'')||typeof code!=='string'||!/^\d{6}$/.test(code))throw new SafeError('invalid_arguments','Use the current six-digit email verification code.');
  return this.withSession(async({email,user})=>parseEmailProof(await email('verify',{challenge_id:challengeId,code}),user),{fresh:false,privacy:false});
 }
}
