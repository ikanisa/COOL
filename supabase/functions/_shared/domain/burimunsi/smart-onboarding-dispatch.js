import {applicationWork,guardedFetch,noteUnknownEffect} from '../../application-fence.js';
import {BuriError,requirePort,requireThat} from './errors.js';
import {identifySmartImport,previewSmartOnboardingImport} from './smart-onboarding-import.js';
import {defs} from './wire/burimunsi.generated.mjs';
import {validateSchema} from './wire/runtime.mjs';
import {isNativeRosterJpegDecoder,NATIVE_JPEG_IDENTITY} from '../../roster_native_jpeg_decoder.mjs';

const SHA=/^[a-f0-9]{64}$/;
const UUID=/^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
const TOKEN=/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/;
const XLSX='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
const kindOf=mime=>mime===XLSX?'xlsx':mime==='application/pdf'?'pdf':'image';
function validatePreview(preview,mime){
  try {validateSchema(defs,'onboardingPreview.data',preview);}
  catch {throw new BuriError('smart_import_recovery_invalid',503);}
  requireThat(preview.sourceKind===kindOf(mime),'smart_import_recovery_invalid',503);
}
const sha256=async bytes=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),
  value=>value.toString(16).padStart(2,'0')).join('');

/**
 * Server-only, explicitly enabled orchestration. This module does not supply
 * either missing production port:
 *
 * - policy.read/assertCurrent must validate the existing Collect processor
 *   approval and return its current immutable binding; a key is not approval.
 * - journal.reserve/advance/complete must transactionally reauthorize the
 *   current native actor and scope, use durable source-fingerprint uniqueness,
 *   leave uncertain phases non-retryable, and encrypt stored preview rows.
 *   Only complete original outcomes may be returned from reserve as recovered.
 *
 * The Supabase runtime must inject the explicitly qualified ROSTER_DECODER adapter
 * and a genuine admitted COLLECT_FENCE_WORK. No ambient network fallback exists.
 */
export function createGuardedSmartOnboardingImport({env,groupId,policy,journal,budgetMs=15000,clock=()=>performance.now()}={}) {
  requireThat(typeof groupId==='string'&&groupId.length>0&&Number.isSafeInteger(budgetMs)&&
    budgetMs>=1000&&budgetMs<=18000&&typeof clock==='function','smart_import_unavailable',503);
  requirePort(policy,['read','assertCurrent']);requirePort(journal,['reserve','advance','complete']);
  const work=applicationWork(env);
  const observe=promise=>work.waitUntil(promise);
  const match=(receipt,base,state)=>receipt&&receipt.state===state&&
    receipt.groupId===base.groupId&&receipt.actorId===base.actorId&&receipt.sourceSha256===base.sourceSha256&&
    receipt.mimeType===base.mimeType&&receipt.policySha256===base.policySha256&&
    receipt.decoderBuildSha256===base.decoderBuildSha256&&
    typeof receipt.requestId==='string'&&UUID.test(receipt.requestId)&&
    typeof receipt.reservationId==='string'&&UUID.test(receipt.reservationId);
  const authorizeActor=async(authorize,actor)=>{
    const fresh=await authorize();
    requireThat(fresh&&fresh.id===actor.id&&fresh.sessionId===actor.sessionId&&fresh.groupId===groupId,
      'session_unavailable',401);
    return fresh;
  };
  return Object.freeze({async preview({actor,groupId:requestedGroup,bytes,mimeType,externalOcrConsent,authorize}){
    requireThat(requestedGroup===groupId&&typeof actor?.id==='string'&&typeof actor?.sessionId==='string'&&
      typeof authorize==='function','smart_import_unavailable',503);
    const started=clock();requireThat(Number.isFinite(started),'smart_import_unavailable',503);
    const remaining=()=>{const left=Math.floor(started+budgetMs-clock());
      requireThat(Number.isSafeInteger(left)&&left>0&&left<=budgetMs,'smart_import_timeout',503);return left;};
    await authorizeActor(authorize,actor);
    const mime=identifySmartImport(bytes,mimeType);
    if(mime==='text/csv')return previewSmartOnboardingImport({bytes,mimeType:mime});
    if(mime!==XLSX)requireThat(externalOcrConsent===true,'smart_import_consent_required',403);
    const snapshot=await policy.read({groupId,actorId:actor.id,mimeType:mime});
    const nativeJpeg=snapshot?.mode==='native_static_jpeg';
    const optional=value=>value===undefined||value===''?undefined:value;
    requireThat(snapshot&&snapshot.decoder===env.ROSTER_DECODER&&typeof snapshot.decoder?.fetch==='function'&&
      SHA.test(snapshot.policySha256??'')&&snapshot.policySha256===env.ROSTER_AI_APPROVAL_SHA256&&
      SHA.test(snapshot.decoderBuildSha256??'')&&snapshot.decoderBuildSha256===env.ROSTER_DECODER_BUILD_SHA256&&
      typeof snapshot.apiKey==='string'&&snapshot.apiKey.length>=20&&snapshot.apiKey===env.OPENAI_API_KEY&&
      TOKEN.test(snapshot.model??'')&&snapshot.model===env.ROSTER_AI_MODEL&&
      (nativeJpeg?mime==='image/jpeg'&&isNativeRosterJpegDecoder(snapshot.decoder)&&
        snapshot.decoder.identity===NATIVE_JPEG_IDENTITY&&snapshot.sourceSha256===env.BUILD_SOURCE_ID&&
        snapshot.organizationId===optional(env.OPENAI_ORGANIZATION_ID)&&snapshot.projectId===optional(env.OPENAI_PROJECT_ID):
       TOKEN.test(snapshot.organizationId??'')&&snapshot.organizationId===env.OPENAI_ORGANIZATION_ID&&
       TOKEN.test(snapshot.projectId??'')&&snapshot.projectId===env.OPENAI_PROJECT_ID),
      'smart_import_ocr_unavailable',503);
    const assertPolicy=async()=>requireThat(await policy.assertCurrent(snapshot)===true,'smart_import_ocr_unavailable',503);
    await assertPolicy();
    const base=Object.freeze({groupId,actorId:actor.id,sourceSha256:await sha256(bytes),mimeType:mime,
      policySha256:snapshot.policySha256,decoderBuildSha256:snapshot.decoderBuildSha256});
    await authorizeActor(authorize,actor);
    const proposedRequest=crypto.randomUUID(),proposedReservation=crypto.randomUUID();
    remaining();
    const receipt=await journal.reserve({...base,sessionId:actor.sessionId,
      proposedRequestId:proposedRequest,proposedReservationId:proposedReservation});
    if(match(receipt,base,'completed')){
      await authorizeActor(authorize,actor);
      validatePreview(receipt.preview,mime);
      return receipt.preview;
    }
    requireThat(match(receipt,base,'reserved')&&receipt.requestId===proposedRequest&&
      receipt.reservationId===proposedReservation,'smart_import_pending',503);
    let phase='reserved';
    const advance=async next=>{
      requireThat(next==='decode'&&phase==='reserved'||next==='extract'&&phase==='decode',
        'smart_import_pending',503);
      await authorizeActor(authorize,actor);await assertPolicy();remaining();
      const nextReceipt=await journal.advance({receipt,sessionId:actor.sessionId,phase:next});
      requireThat(match(nextReceipt,base,next)&&nextReceipt.requestId===receipt.requestId&&
        nextReceipt.reservationId===receipt.reservationId,'smart_import_pending',503);
      phase=next;remaining();
    };
    const decoder={buildSha256:snapshot.decoderBuildSha256,requestId:receipt.requestId,reservationId:receipt.reservationId,
      port:{async fetch(request,context){await advance('decode');
        const bounded=new Request(request,{signal:AbortSignal.any([request.signal,AbortSignal.timeout(remaining())])});
        return snapshot.decoder.fetch(bounded,context);}}};
    const ocr={consent:externalOcrConsent,apiKey:snapshot.apiKey,model:snapshot.model,
      organizationId:snapshot.organizationId,projectId:snapshot.projectId,get timeoutMs(){return remaining();},trackPromise:observe,
      onUncertain:()=>noteUnknownEffect(env,'roster_ai'),
      async fetchImpl(...args){await advance('extract');remaining();return guardedFetch(env,'roster_ai',...args);}};
    // An interrupted phase remains in the original journal state. Never issue a
    // second write or dispatch merely because a response/commit was unconfirmed.
    const preview=await previewSmartOnboardingImport({bytes,mimeType:mime,decoder,ocr});
    validatePreview(preview,mime);
    await authorizeActor(authorize,actor);await assertPolicy();
    const done=await journal.complete({receipt,sessionId:actor.sessionId,phase,preview});
    requireThat(match(done,base,'completed')&&done.requestId===receipt.requestId&&
      done.reservationId===receipt.reservationId,'smart_import_pending',503);
    await authorizeActor(authorize,actor);validatePreview(preview,mime);
    return preview;
  }});
}
