import {ApiError,digest,uuid} from './core.js';
import {decrypt} from './encryption.js';
import {adminEmailProofId,adminEmailVerifiedAt} from './admin_email_policy.js';
import {openSmsReceiptConfiguration,createOpenSmsReceiptTransport} from '../opensms-receipts.js';
import {applicationWork} from '../application-fence.js';

const q=(ctx,sql,...values)=>ctx.env.DB.prepare(sql).bind(...values);
const failure=()=>new ApiError(503,'sms_gateway_unconfirmed','The gateway result is unconfirmed. Check this original attempt before continuing.');
const denied=()=>new ApiError(409,'sms_dispatch_unavailable','This original sending authority is unavailable.');
const marker={contract_version:1,scope:'assisted_sms_gateway_observation',delivery_confirmed:false,provider_confirmation:false,settlement_status:'not_asserted',may_send:false};

export async function prepareAssistedSmsDispatch(ctx,attempt,confirmation){
 const config=openSmsReceiptConfiguration(ctx.env);if(!config)return null;
 const token=Array.from(crypto.getRandomValues(new Uint8Array(32)),b=>b.toString(16).padStart(2,'0')).join('');
 const notAfter=new Date(confirmation.expires_seconds*1000).toISOString();
 return {token,statement:q(ctx,`INSERT INTO app.assisted_sms_dispatches(attempt_id,grant_sha256,expires_seconds,application_id,provider_message_id,not_after)
  VALUES(?,?,?,?,?,?)`,attempt.id,await digest(token),confirmation.expires_seconds,config.applicationId,
  config.applicationId+':collect-receipt:'+attempt.id,notAfter)};
}

async function original(ctx,attemptId){
 const [result]=await ctx.env.DB.batch([q(ctx,`SELECT d.*,j.body_ciphertext,j.destination_ciphertext,j.body_sha256,j.destination_sha256,j.collection_id,j.recipient_user_id,j.destination_revision,
   j.id AS job_id,j.payment_id,j.entry_id,a.originating_session_id,a.public_session_id
  FROM app.assisted_sms_dispatches d JOIN app.assisted_sms_send_starts a ON a.id=d.attempt_id JOIN app.assisted_sms_jobs j ON j.id=a.job_id
  WHERE d.attempt_id=? AND a.actor_admin_id=? AND a.actor_user_id=? AND a.originating_session_id=? AND a.public_session_id=?`,
  attemptId,ctx.account.id,ctx.actor.userId,ctx.actor.sessionId,ctx.account.public_id)]);
 if(result.results.length!==1)throw denied();return result.results[0];
}
async function message(ctx,row){
 const decoder=new TextDecoder('utf-8',{fatal:true});
 const text=decoder.decode(await decrypt(ctx.env,row.body_ciphertext,`assisted-sms-body:${row.job_id}:${row.payment_id}:${row.entry_id}`));
 const to=decoder.decode(await decrypt(ctx.env,row.destination_ciphertext,`assisted-sms-destination:${row.collection_id}:${row.recipient_user_id}:${row.destination_revision}`));
 if(await digest(text)!==row.body_sha256||await digest(to)!==row.destination_sha256)throw failure();
 return {messageId:row.provider_message_id,to,text,notAfter:row.not_after};
}
async function retain(ctx,row,result){
 const state=result?'accepted':'unknown';
 const evidence=result?.evidenceSha256??await digest(JSON.stringify({attempt_id:row.attempt_id,state:'unknown'}));
 const [saved]=await ctx.env.DB.batch([q(ctx,`UPDATE app.assisted_sms_dispatches SET state=?,provider_state=?,evidence_sha256=?,updated_seconds=app.unixepoch()
  WHERE attempt_id=? AND state IN('sending','accepted','unknown') RETURNING attempt_id`,state,result?.state??null,evidence,row.attempt_id)]);
 if(saved.results.length!==1)throw failure();
 return {...marker,attempt_id:row.attempt_id,gateway_state:result?.state??'unknown',provider_accepted:result?.providerAccepted===true,
  observation:result?.observation??null,evidence_reference_sha256:evidence};
}
export async function dispatchAssistedSms(ctx,body){
 if(!body||Object.keys(body).sort().join(',')!=='attempt_id,dispatch_token'||!/^[a-f0-9]{64}$/.test(body.dispatch_token??''))throw denied();
 const attemptId=uuid(body.attempt_id,'attempt_id'),config=openSmsReceiptConfiguration(ctx.env);if(!config)throw denied();
 const row=await original(ctx,attemptId);
 if(row.application_id!==config.applicationId||await digest(body.dispatch_token)!==row.grant_sha256||row.state!=='ready')throw denied();
 const payload=await message(ctx,row);
 // Last database boundary checks live policy/consent, original proof, session,
 // hashes and deadline after decryption. The single conditional update wins.
 const [result]=await ctx.env.DB.batch([q(ctx,`UPDATE app.assisted_sms_dispatches d SET state='sending',started_seconds=app.unixepoch(),updated_seconds=app.unixepoch()
  WHERE d.attempt_id=? AND d.state='ready' AND d.expires_seconds>app.unixepoch()
   AND EXISTS(SELECT 1 FROM app.assisted_sms_send_starts a JOIN app.assisted_sms_current_jobs j ON j.id=a.job_id
    JOIN app.assisted_sms_claims claim ON claim.id=a.claim_id
    WHERE a.id=d.attempt_id AND j.state='send_started' AND claim.actor_email_proof_id=? AND claim.actor_email_verified_at=?
     AND j.body_sha256=a.body_sha256 AND j.destination_sha256=a.destination_sha256
     AND NOT EXISTS(SELECT 1 FROM app.privacy_retention_barriers b WHERE b.subject_id=j.recipient_user_id))
  RETURNING attempt_id`,attemptId,adminEmailProofId(ctx.account),adminEmailVerifiedAt(ctx.account))]);
 if(result.results.length!==1)throw denied();
 let observation=null;
 try{observation=await applicationWork(ctx.env).dispatch('sms_gateway',()=>createOpenSmsReceiptTransport(config).submit(payload));}catch{}
 return retain(ctx,row,observation);
}
export async function inspectAssistedSms(ctx,body){
 if(!body||Object.keys(body).join(',')!=='attempt_id')throw denied();
 const config=openSmsReceiptConfiguration(ctx.env);if(!config)throw denied();
 const row=await original(ctx,uuid(body.attempt_id,'attempt_id'));
 if(row.application_id!==config.applicationId||row.state==='ready'||row.state==='suppressed')throw denied();
 const payload=await message(ctx,row);
 let observation=null;
 try{observation=await applicationWork(ctx.env).dispatch('sms_gateway_read',()=>createOpenSmsReceiptTransport(config).inspect(payload));}catch{}
 return retain(ctx,row,observation);
}
