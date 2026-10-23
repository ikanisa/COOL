import {consumeEmailProof,consumePasswordProof} from './human_login.mjs';
import {ORIGINS,OperatorError,need,plain,keys,uuid,publicSession,authorityKey,sensitiveAuthorityKey,emailVerification,hasFreshEmailVerification,sha} from './contract.mjs';

const AUTH = Object.freeze({
  session:['GET','/api/admin/auth/session'], login:['POST','/api/admin/auth/login'],
  otp:['POST','/api/admin/auth/otp'], signInVerify:['POST','/api/admin/auth/verify'],
  emailStatus:['GET','/api/admin/auth/email-verification'],
  emailRequest:['POST','/api/admin/auth/email/request'], emailVerify:['POST','/api/admin/auth/email/verify'],
  logout:['POST','/api/admin/auth/logout'],
});
const COOKIE='__Host-collect_admin';
function cookieFrom(headers,{deletion=false}={}) {
  const lines=typeof headers.getSetCookie==='function'?headers.getSetCookie():[];
  const matching=lines.filter(line=>line.startsWith(COOKIE+'='));
  need(matching.length===1,'auth_cookie_missing_or_ambiguous');
  const parts=matching[0].split(';').map(part=>part.trim()),token=parts.shift().slice(COOKIE.length+1);
  const attrs=new Map(parts.map(part=>{const i=part.indexOf('=');return [part.slice(0,i<0?undefined:i).toLowerCase(),i<0?'':part.slice(i+1)];}));
  need((deletion?token===''&&attrs.get('max-age')==='0':/^[a-f0-9]{64}$/.test(token)&&/^[1-9][0-9]{0,5}$/.test(attrs.get('max-age')??''))&&attrs.has('secure')&&attrs.has('httponly')&&attrs.get('path')==='/'&&attrs.get('samesite')?.toLowerCase()==='strict'&&!attrs.has('domain'),'auth_cookie_constraints_invalid');
  return token;
}
function challengeReceipt(value,initial) {
  keys(value,['challenge_id','retry_after','expires_in','delivery_status'],initial?['channel']:[]);uuid(value.challenge_id);
  need(value.retry_after===60&&Number.isSafeInteger(value.expires_in)&&value.expires_in>=0&&value.expires_in<=300&&['accepted','unknown'].includes(value.delivery_status),'invalid_email_challenge');
  if(initial)need(value.channel==='email','invalid_email_challenge');return structuredClone(value);
}
export class AdminHttp {
  #cookie=null;#csrf=null;#challenges=new Map();#user=null;#epoch=0;#emailVerifiedAt=null;#proofState='unavailable';#unknownVerification=null;#sendAttempt=0;#fetch;#origin;#onFence;#clock;#timeout;
  constructor({origin,fetchImpl=fetch,onFence=()=>{},clock=Date.now,timeoutMs=15000}) {
    need(ORIGINS.includes(origin),'independently_approved_frontend_origin_required');
    need(typeof fetchImpl==='function'&&Number.isSafeInteger(timeoutMs)&&timeoutMs>=100&&timeoutMs<=30000,'invalid_transport_configuration');
    this.#origin=origin;this.#fetch=fetchImpl;this.#onFence=onFence;this.#clock=clock;this.#timeout=timeoutMs;
  }
  get origin(){return this.#origin;}
  snapshot(){return this.#user?{epoch:this.#epoch,user:structuredClone(this.#user),authority:sensitiveAuthorityKey(this.#user,this.#emailVerifiedAt),emailVerifiedAt:this.#emailVerifiedAt,proofState:this.#proofState}:null;}
  metadata(){
    const snapshot=this.snapshot();
    return {authentication_state:!snapshot?'unconfigured_or_unavailable':snapshot.proofState!=='available'?'email_verification_unavailable':hasFreshEmailVerification(snapshot,this.#clock())?'verified_email_session':'email_verification_required',authority_evidence:'last_successful_readback; every action rechecks',origin:this.#origin,operator_session:snapshot?.user.sessionId??null,role:snapshot?.user.role??null,assurance_level:snapshot?.user.assuranceLevel??null,expires_at:snapshot?.user.expiresAt??null,credentials_persisted:false,browser_cookie_extraction:false};
  }
  #fence({clear=false}={}) {this.#epoch++;this.#sendAttempt++;this.#challenges.clear();this.#onFence();if(clear){this.#cookie=null;this.#csrf=null;this.#user=null;this.#emailVerifiedAt=null;this.#proofState='unavailable';this.#unknownVerification=null;}}
  #unavailable(){if(this.#user){this.#fence();this.#proofState='unavailable';}}
  #bound(before){const current=this.snapshot();need(current&&current.epoch===before.epoch&&current.authority===before.authority,'session_changed_during_request');}
  #proof(value,sessionId,{forceFence=false}={}) {
    const parsed=emailVerification(value,sessionId,this.#clock());
    if(this.#unknownVerification){
      const old=this.#unknownVerification;
      const newer=old.sessionId===sessionId&&old.user===authorityKey(this.#user)&&parsed.emailVerifiedAt!==null&&Date.parse(parsed.emailVerifiedAt)>(old.emailVerifiedAt===null?-Infinity:Date.parse(old.emailVerifiedAt));
      if(!newer){this.#proofState='unavailable';return this.snapshot();}
      this.#unknownVerification=null;
    }
    // A read failure already fenced custody. Restoring the exact same proof does
    // not manufacture a new event or add another in-call epoch transition.
    if(forceFence||parsed.emailVerifiedAt!==this.#emailVerifiedAt)this.#fence();
    this.#emailVerifiedAt=parsed.emailVerifiedAt;this.#proofState='available';return this.snapshot();
  }
  clear(){this.#fence({clear:true});}
  async #request(path,method,body,{signal,acceptCookie=false,deleteCookie=false,noCookie=false,expectedStatus}={}) {
    const epoch=this.#epoch,cookie=this.#cookie;
    const headers={Accept:'application/json',Origin:this.#origin,'X-Collect-Admin':'1','X-Collect-Requested-With':'collect-admin','Sec-Fetch-Site':'same-origin'};
    if(body!==undefined)headers['Content-Type']='application/json';
    if(cookie){headers.Cookie=COOKIE+'='+cookie;if(method==='POST'){need(this.#csrf===sha('collect-admin-csrf:'+cookie),'current_csrf_required');headers['X-Collect-CSRF']=this.#csrf;}}
    need(!signal?.aborted,'request_cancelled_before_dispatch');
    let response,dispatched=false,authoritativeRefusal=false;
    try {
      dispatched=true;response=await this.#fetch(this.#origin+path,{method,headers,redirect:'manual',cache:'no-store',...(body===undefined?{}:{body:JSON.stringify(body)}),signal:AbortSignal.any([AbortSignal.timeout(this.#timeout),...signal?[signal]:[]])});
      need(epoch===this.#epoch,'session_changed_during_request');
      need(response.status!==0&&response.status<300&&response.status>=200||response.status>=400,'redirect_refused');
      need((response.headers.get('content-type')??'').toLowerCase().startsWith('application/json'),'non_json_response');
      const chunks=[];let bytes=0;
      for await(const chunk of response.body??[]){bytes+=chunk.length;need(bytes<=262144,'response_too_large');chunks.push(chunk);}
      const raw=Buffer.concat(chunks);let value;
      try{value=JSON.parse(new TextDecoder('utf8',{fatal:true}).decode(raw));}catch{throw new OperatorError('invalid_json_response');}
      need(epoch===this.#epoch,'session_changed_during_request');
      if(!response.ok) {
        authoritativeRefusal=true;
        const code=plain(value.error)&&typeof value.error.code==='string'&&/^[a-z_]{1,80}$/.test(value.error.code)?value.error.code:'request_rejected';
        if(response.status===401)this.#fence({clear:true});else if(response.status===403)this.#unavailable();
        throw new OperatorError(code,{unknown:response.status>=500});
      }
      need(expectedStatus===undefined||response.status===expectedStatus,'unexpected_response_status');
      need(plain(value),'invalid_response_envelope');
      if(acceptCookie){
        const nextCookie=cookieFrom(response.headers);
        keys(value,['user','expiresAt','csrfToken']);
        const user=publicSession(value.user,this.#clock());
        need(acceptCookie!=='login'||value.expiresAt===user.expiresAt,'session_expiry_mismatch');
        need(value.csrfToken===sha('collect-admin-csrf:'+nextCookie),'csrf_cookie_binding_invalid');
        this.#cookie=nextCookie;this.#csrf=value.csrfToken;
      }
      else if(deleteCookie){keys(value,['ok']);need(value.ok===true,'invalid_logout_envelope');cookieFrom(response.headers,{deletion:true});this.#cookie=null;this.#csrf=null;}
      else need(!(response.headers.getSetCookie?.()??[]).some(line=>noCookie||line.startsWith(COOKIE+'=')),'unexpected_auth_rotation');
      return value;
    } catch(error) {
      if(error instanceof OperatorError){if(method==='POST'&&dispatched&&!authoritativeRefusal)throw new OperatorError(error.code,{unknown:true});throw error;}
      throw new OperatorError('transport_outcome_unknown',{unknown:method==='POST'});
    }
  }
  async refresh({signal}={}) {
    const startingEpoch=this.#epoch;let phase='session',parsed=false;
    try {
      let body;
      // A refresh-lease409 authorizes one additional GET only, never a POST replay.
      for(let attempt=0;attempt<2;attempt++){
        try{body=await this.#request(AUTH.session[1],AUTH.session[0],undefined,{signal});break;}
        catch(error){if(error.code!=='session_refresh_pending'||attempt===1)throw error;}
      }
      need(startingEpoch===this.#epoch,'session_changed_during_request');
      parsed=true;keys(body,['user','expiresAt','ownerEmail','csrfToken']);
      if(body.user===null){this.clear();throw new OperatorError('authentication_required');}
      const user=publicSession(body.user,this.#clock());
      need(body.expiresAt===user.expiresAt&&typeof body.ownerEmail==='string'&&body.ownerEmail.length<=254,'invalid_session_metadata');
      need(this.#cookie&&body.csrfToken===sha('collect-admin-csrf:'+this.#cookie),'csrf_cookie_binding_invalid');
      if(this.#user&&authorityKey(this.#user)!==authorityKey(user))this.#fence();
      this.#csrf=body.csrfToken;this.#user=user;phase='proof';const before=this.snapshot();
      const sidecar=await this.#request(AUTH.emailStatus[1],AUTH.emailStatus[0],undefined,{signal,noCookie:true,expectedStatus:200});
      this.#bound(before);return this.#proof(sidecar,user.sessionId);
    } catch(error) {
      if(phase==='session'&&(parsed||error.code==='unexpected_auth_rotation'))this.clear();else this.#unavailable();throw error;
    }
  }
  async #loginResult(body,{signal}={}) {
    this.#user=publicSession(body.user,this.#clock());this.#fence();const current=await this.refresh({signal});
    need(authorityKey(publicSession(body.user,this.#clock()))===authorityKey(current.user),'login_session_readback_mismatch');return current;
  }
  async signIn(email,password,proof,{signal}={}) {
    need(typeof email==='string'&&email.length<=254&&!/[\r\n\x00]/.test(email)&&typeof password==='string'&&password.length>0&&password.length<=512,'invalid_credentials_input');
    this.clear();let accepted=false;
    try {
      const captcha_token=consumePasswordProof(proof,this.#origin);
      const body=await this.#request(AUTH.login[1],AUTH.login[0],{email,password,captcha_token},{acceptCookie:'login',signal,expectedStatus:200});accepted=true;
      return await this.#loginResult(body,{signal});
    } catch(error){if(!accepted)this.clear();else this.#unavailable();if(accepted)throw new OperatorError(error.code??'login_readback_unknown',{unknown:true});throw error;}
  }
  async requestEmailSignIn(email,proof,{signal}={}) {
    need(typeof email==='string'&&email.length<=254&&/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email),'invalid_email_input');
    this.clear();const captcha_token=consumeEmailProof(proof,this.#origin,'sign_in'),epoch=this.#epoch,attempt=++this.#sendAttempt;let replied=false;
    try {
      const body=await this.#request(AUTH.otp[1],AUTH.otp[0],{email,captcha_token},{signal,noCookie:true,expectedStatus:200});replied=true;
      const value=challengeReceipt(body,true);need(epoch===this.#epoch&&attempt===this.#sendAttempt,'email_attempt_changed');
      this.#challenges.set(value.challenge_id,{purpose:'sign_in',epoch,attempt,expiresAt:this.#clock()+value.expires_in*1000,busy:false});return value;
    }catch(error){if(replied&&!error.outcomeUnknown)throw new OperatorError(error.code,{unknown:true});throw error;}
  }
  async verifyEmailSignIn(challengeId,code,{signal}={}) {
    uuid(challengeId);need(typeof code==='string'&&/^[0-9]{6}$/.test(code),'invalid_email_code');
    const challenge=this.#challenges.get(challengeId);
    need(challenge?.purpose==='sign_in'&&challenge.epoch===this.#epoch&&challenge.expiresAt>this.#clock()&&!challenge.busy,'current_bound_email_challenge_required');
    challenge.busy=true;let accepted=false;
    try {
      const body=await this.#request(AUTH.signInVerify[1],AUTH.signInVerify[0],{challenge_id:challengeId,code},{acceptCookie:'login',signal,expectedStatus:200});accepted=true;
      this.#challenges.delete(challengeId);const current=await this.#loginResult(body,{signal});
      need(hasFreshEmailVerification(current,this.#clock()),'recent_email_sign_in_required');return current;
    } catch(error){
      if(!error.outcomeUnknown&&!accepted&&this.#challenges.get(challengeId)===challenge)challenge.busy=false;else this.#challenges.delete(challengeId);
      if(accepted){this.#unavailable();throw new OperatorError(error.code??'login_readback_unknown',{unknown:true});}throw error;
    }
  }
  async requestEmailVerification(proof,{signal}={}) {
    const before=await this.refresh({signal});
    if(this.#unknownVerification)throw new OperatorError('admin_email_operation_unknown',{unknown:true});
    const captcha_token=consumeEmailProof(proof,this.#origin,'sensitive'),attempt=++this.#sendAttempt;this.#challenges.clear();let replied=false;
    try{
      const body=await this.#request(AUTH.emailRequest[1],AUTH.emailRequest[0],{captcha_token},{signal,noCookie:true,expectedStatus:202});replied=true;
      const value=challengeReceipt(body,false);this.#bound(before);need(attempt===this.#sendAttempt,'email_attempt_changed');
      this.#challenges.set(value.challenge_id,{purpose:'sensitive',epoch:before.epoch,attempt,authority:before.authority,expiresAt:this.#clock()+value.expires_in*1000,busy:false});return value;
    }catch(error){if(replied&&!error.outcomeUnknown)throw new OperatorError(error.code,{unknown:true});throw error;}
  }
  async verifyEmail(challengeId,code,{signal}={}) {
    uuid(challengeId);need(typeof code==='string'&&/^[0-9]{6}$/.test(code),'invalid_email_code');
    const challenge=this.#challenges.get(challengeId);need(challenge?.purpose==='sensitive'&&!challenge.busy,'current_bound_email_challenge_required');
    const before=await this.refresh({signal});
    need(challenge===this.#challenges.get(challengeId)&&!challenge.busy&&challenge.epoch===before.epoch&&challenge.authority===before.authority&&challenge.expiresAt>this.#clock(),'current_bound_email_challenge_required');
    challenge.busy=true;let accepted=false;
    try {
      const value=await this.#request(AUTH.emailVerify[1],AUTH.emailVerify[0],{challenge_id:challengeId,code},{signal,noCookie:true,expectedStatus:200});accepted=true;
      this.#bound(before);need(challenge===this.#challenges.get(challengeId)&&challenge.attempt===this.#sendAttempt,'email_attempt_changed');const parsed=emailVerification(value,before.user.sessionId,this.#clock());
      need(hasFreshEmailVerification({user:before.user,emailVerifiedAt:parsed.emailVerifiedAt,proofState:'available'},this.#clock()),'recent_email_sign_in_required');
      return this.#proof(parsed,before.user.sessionId,{forceFence:true});
    } catch(error){
      if(!error.outcomeUnknown&&!accepted&&error.code==='invalid_credentials'&&this.#challenges.get(challengeId)===challenge)challenge.busy=false;
      else{this.#challenges.delete(challengeId);if((accepted||error.outcomeUnknown)&&this.#user)this.#unknownVerification={sessionId:before.user.sessionId,user:authorityKey(before.user),emailVerifiedAt:before.emailVerifiedAt};this.#unavailable();}
      if(accepted&&!error.outcomeUnknown)throw new OperatorError(error.code,{unknown:true});throw error;
    }
  }
  async ensure(operatorSession,permission,{signal}={}) {
    uuid(operatorSession);const before=await this.refresh({signal});need(before.user.sessionId===operatorSession,'original_public_session_required');
    need(hasFreshEmailVerification(before,this.#clock()),'recent_email_sign_in_required');need(before.user.permissions.includes(permission),'permission_required');return before;
  }
  async operator(action,args,before,{signal}={}) {
    need(before&&this.snapshot()?.epoch===before.epoch&&this.snapshot()?.authority===before.authority,'session_changed_before_dispatch');
    const result=await this.#request('/api/admin/notification-operator','POST',{action,...args},{signal});
    need(result.ok===true&&Object.keys(result).sort().join(',')==='ok,result','invalid_operator_envelope');
    this.#bound(before);await this.refresh({signal});this.#bound(before);return result.result;
  }
  async logout(){this.#fence();try{await this.#request(AUTH.logout[1],AUTH.logout[0],{},{deleteCookie:true});}finally{this.clear();}}

}

// Historical source compatibility; active callers use the provider-neutral class.
export {AdminHttp as CloudflareAdminHttp};
