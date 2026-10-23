import {ACTIONS,WRITES,MARKER,OperatorError,need,keys,uuid,hash,request,receipt,sha,canonical,same,sanitized,hasFreshEmailVerification} from './contract.mjs';

const noPermit=value=>({...value,replay:true,may_send:false,acknowledgement:'client_receipt_permit_not_reissued'});
function storedReceipt(action,value) {
  if(action==='record_send_start') {
    const {may_send,acknowledgement,replay,...stored}=value;
    receipt(action,stored,{stored:true});return noPermit(stored);
  }
  return {...receipt(action,value),replay:true};
}
function inferReceipt(value) {
  if(value?.state==='send_started')return ['record_send_start',storedReceipt('record_send_start',value)];
  if(Object.hasOwn(value??{},'worker_id'))return ['claim',receipt('claim',value)];
  if(Object.hasOwn(value??{},'confirmation_id'))return ['confirm',receipt('confirm',value)];
  if(Object.hasOwn(value??{},'observation'))return ['record_outcome',receipt('record_outcome',value)];
  if(value?.state==='queued')return ['release_claim',receipt('release_claim',value)];
  throw new OperatorError('unknown_operation_receipt');
}

export class OperatorClient {
  #http;#journal;#clock;#serial=Promise.resolve();#epoch=null;#authority=null;#originSession=null;
  #claims=new Map();#contents=new Map();#confirmations=new Map();
  constructor({http,journal,clock=Date.now}) {this.#http=http;this.#journal=journal;this.#clock=clock;}
  metadata(){return {...this.#http.metadata(),contract_version:1,transport:'supabase_same_origin_admin_cookie',messages_automation:false,delivery_confirmed:false,provider_confirmation:false,settlement_status:'not_asserted'};}
  call(action,input,options={}) {
    const result=this.#serial.then(()=>this.#call(action,input,options));
    this.#serial=result.catch(()=>{});return result;
  }
  #current(before) {
    const current=this.#http.snapshot(),now=this.#clock();
    need(current?.epoch===before.epoch&&current?.authority===before.authority&&current?.emailVerifiedAt===before.emailVerifiedAt,'session_changed_during_operation');
    need(hasFreshEmailVerification(before,now)&&hasFreshEmailVerification(current,now),'fresh_verified_email_required');
  }
  #sync(before) {
    if(this.#epoch!==before.epoch||this.#authority!==before.authority) {
      this.#claims.clear();this.#contents.clear();this.#confirmations.clear();this.#originSession=null;
      this.#epoch=before.epoch;this.#authority=before.authority;
    }
  }
  #live(value,key) {need(value&&Date.parse(value[key])>this.#clock(),'current_unexpired_claim_required');return value;}
  #claim(args) {
    const claim=this.#live(this.#claims.get(args.job_id),'claim_expires_at');
    need(claim.claim_token===args.claim_token&&claim.fence_version===args.fence_version,'original_claim_required');return claim;
  }
  #pair(value,before) {
    need(value.public_session_id===before.user.sessionId,'original_public_session_required');
    if(this.#originSession!==null)need(value.originating_session_id===this.#originSession,'original_server_session_required');
    this.#originSession=value.originating_session_id;
  }
  #match(action,value,args,before) {
    for(const key of ['job_id','claim_token','confirmation_id','attempt_id','body_sha256','destination_sha256','destination_revision','worker_id','observation','evidence_reference_sha256'])
      if(Object.hasOwn(args,key)&&!(action==='release_claim'&&key==='claim_token'))need(value[key]===args[key],'operation_receipt_mismatch');
    if(Object.hasOwn(args,'fence_version'))need(value.fence_version===args.fence_version+(action==='release_claim'?1:0),'operation_fence_mismatch');
    if(action==='claim')need(value.fence_version===args.expected_fence+1,'claim_fence_mismatch');
    if(['claim','confirm','record_send_start'].includes(action))this.#pair(value,before);
  }
  #adopt(action,value) {
    if(action==='claim')this.#claims.set(value.job_id,value);
    if(action==='get_claimed')this.#contents.set(value.job_id,value);
    if(action==='confirm')this.#confirmations.set(value.job_id,value);
    if(['record_send_start','release_claim'].includes(action)) {
      this.#claims.delete(value.job_id);this.#contents.delete(value.job_id);this.#confirmations.delete(value.job_id);
    }
  }
  #validateBefore(action,args) {
    if(['get_claimed','confirm','record_send_start','release_claim'].includes(action))this.#claim(args);
    if(action==='confirm') {
      const content=this.#live(this.#contents.get(args.job_id),'claim_expires_at');
      for(const key of ['body_sha256','destination_sha256','destination_revision'])need(content[key]===args[key],'review_exact_content_before_confirmation');
    }
    if(action==='record_send_start') {
      const confirmation=this.#live(this.#confirmations.get(args.job_id),'expires_at');
      const content=this.#live(this.#contents.get(args.job_id),'claim_expires_at');
      need(confirmation.confirmation_id===args.confirmation_id,'original_confirmation_required');
      for(const key of ['body_sha256','destination_sha256','destination_revision'])need(content[key]===confirmation[key],'confirmed_content_changed');
    }
  }
  #localInput(action,input) {
    need(ACTIONS.includes(action),'unsupported_action');
    need(input&&typeof input==='object','invalid_input');
    const {operator_session,resume_original_request,manual_authorization,...untrustedArgs}=input;
    uuid(operator_session);
    need(resume_original_request===undefined||WRITES.has(action)&&typeof resume_original_request==='boolean','unsupported_resume');
    if(action==='record_send_start') {
      keys(manual_authorization,['user_authorized','authorization_reference_sha256']);
      need(manual_authorization.user_authorized===true,'per_message_human_authorization_required');hash(manual_authorization.authorization_reference_sha256);
    } else need(manual_authorization===undefined,'unsupported_manual_authorization');
    return {operator_session,resume:resume_original_request===true,manual_authorization,args:request(action,untrustedArgs)};
  }
  async #resolve(args,before,{signal}={}) {
    const raw=await this.#http.operator('get_operation',args,before,{signal}),result=receipt('get_operation',raw);
    need(result.request_id===args.request_id,'operation_receipt_mismatch');
    const record=await this.#journal.load(args.request_id);
    if(record) {
      need(record.intent.operator_session===before.user.sessionId&&record.intent.authority_sha256===sha(before.authority),'original_operation_authority_required');
      if(result.observed) {
        const action=record.intent.action,value=storedReceipt(action,result.receipt);
        this.#match(action,value,record.intent.args,before);this.#current(before);
        await this.#journal.append(args.request_id,{phase:'resolved',receipt:value});
        this.#adopt(action,value);result.receipt=value;
      } else {
        need(record.last.phase!=='resolved','recorded_operation_disappeared');
        await this.#journal.append(args.request_id,{phase:'not_observed'});
      }
    } else if(result.observed)result.receipt=inferReceipt(result.receipt)[1];
    this.#current(before);return result;
  }
  async #call(action,input,{signal}={}) {
    const {operator_session,resume,manual_authorization,args}=this.#localInput(action,input);
    need(!signal?.aborted,'request_cancelled');
    const before=await this.#http.ensure(operator_session,action==='list_pending'?'assisted_sms.read':'assisted_sms.manage',{signal});
    this.#sync(before);
    if(action==='get_operation')return this.#resolve(args,before,{signal});
    if(!WRITES.has(action)) {
      this.#validateBefore(action,args);
      const value=receipt(action,await this.#http.operator(action,args,before,{signal}));
      this.#match(action,value,args,before);this.#current(before);
      if(action==='get_claimed')need(value.claim_expires_at===this.#claims.get(args.job_id).claim_expires_at,'claim_expiry_mismatch');
      this.#adopt(action,value);return value;
    }
    let existing=await this.#journal.load(args.request_id);
    const checkIntent=record=>{
      need(record.intent.action===action&&record.intent.args_sha256===sha(canonical(args))&&same(record.intent.args,args),'original_operation_payload_required');
      need(record.intent.operator_session===operator_session&&record.intent.authority_sha256===sha(before.authority),'original_operation_authority_required');
    };
    if(existing) {
      checkIntent(existing);
      if(existing.last.phase==='resolved')return storedReceipt(action,existing.last.receipt);
      need(existing.last.phase==='not_observed'&&resume,'resolve_original_operation_before_explicit_retry');
    }
    this.#validateBefore(action,args);this.#current(before);
    if(!existing) {
      const started=await this.#journal.begin({action,args,session:operator_session,authority:before.authority});
      if(!started.created){checkIntent(started.record);throw new OperatorError('resolve_original_operation_before_explicit_retry');}
    }
    // Every attempt is durable before HTTP dispatch; a crash or lost acknowledgement is unknown.
    await this.#journal.append(args.request_id,{phase:'unknown'});
    let value;
    const content=action==='record_send_start'?structuredClone(this.#contents.get(args.job_id)):null;
    // The proof captured before dispatch is part of the original authority. A
    // later verification cannot renew this operation or its one-use handoff.
    const validUntil=action==='record_send_start'?Math.min(Date.parse(content.claim_expires_at),Date.parse(this.#confirmations.get(args.job_id).expires_at),Date.parse(before.user.expiresAt),Date.parse(before.emailVerifiedAt)+300000):null;
    try {
      need(!signal?.aborted,'request_cancelled');this.#current(before);
      value=receipt(action,await this.#http.operator(action,args,before,{signal}));
      this.#match(action,value,args,before);this.#current(before);
      if(action==='claim')this.#live(value,'claim_expires_at');
      if(action==='confirm')this.#live(value,'expires_at');
      const persisted=action==='record_send_start'?noPermit(value):value;
      await this.#journal.append(args.request_id,{phase:'resolved',receipt:persisted});
      this.#current(before);this.#adopt(action,value);
      if(action==='record_send_start'&&value.may_send) {
        need(!signal?.aborted,'request_cancelled');this.#live(content,'claim_expires_at');need(validUntil>this.#clock(),'handoff_expired');
        return {...value,manual_handoff:{mode:'manual_mac_messages',authorization_reference_sha256:manual_authorization.authorization_reference_sha256,
          operator_session,originating_session_id:value.originating_session_id,attempt_id:value.attempt_id,confirmation_id:value.confirmation_id,
          destination_e164:content.destination_e164,message_body:content.message_body,destination_sha256:content.destination_sha256,body_sha256:content.body_sha256,
          valid_until:new Date(validUntil).toISOString(),one_use:true,delivery_confirmed:false,provider_confirmation:false,settlement_status:'not_asserted',
          instruction:'Use supported Mac Computer Use to inspect Messages. Only with the recorded explicit authorization for this exact recipient and text, send once before valid_until. Inspect the exact conversation after the action. Record observed_sent only for an observed send action; uncertainty remains uncertain. Clipboard, composer population, handoff and this permit are not send or delivery proof.'}};
      }
      return action==='record_send_start'?noPermit(value):value;
    } catch(error) {
      // Do not reissue, adopt, or automatically retry a possibly committed write.
      let recorded=true;
      try{await this.#journal.append(args.request_id,{phase:'unknown',error_code:error instanceof OperatorError?error.code:'operation_outcome_unknown'});}catch{recorded=false;}
      throw new OperatorError(recorded?'operation_outcome_unknown':'operation_outcome_unknown_journal_unavailable',{unknown:true});
    }
  }
}
