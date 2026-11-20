import {digest} from '../core.js';
import {BuriError,requireThat} from './errors.js';
import {requireRequestId} from './values.js';
import {isNativeRosterJpegDecoder,NATIVE_JPEG_IDENTITY,NATIVE_JPEG_PROTOCOL} from '../../roster_native_jpeg_decoder.mjs';

const SHA=/^[a-f0-9]{64}$/,TOKEN=/^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$/;
const unavailable=()=>new BuriError('smart_import_ocr_unavailable',503);
const optional=value=>value===undefined||value===''?undefined:value;
const nativeKeys=['schema_version','status','enabled','purpose','provider','responses_endpoint','decoder_protocol',
 'decoder_identity','decoder_build_sha256','model','collection_id','source_sha256','authorization_evidence_sha256',
 'technical_checks_sha256','authorized_at','valid_until','request_consent_required','preview_only'];
function nativeSnapshot(env,p,raw,hash,clock,{groupId,mimeType}={}){
 const keys=Object.keys(p),allowed=new Set([...nativeKeys,'project_id','organization_id']);
 if(nativeKeys.some(key=>!Object.hasOwn(p,key))||keys.some(key=>!allowed.has(key))||
   p.schema_version!==2||env.BURIMUNSI_SMART_ONBOARDING_ADVANCED_ENABLED!=='true'||
   p.status!=='owner_authorized'||p.enabled!==true||p.purpose!=='collect_roster_static_jpeg_preview'||
   p.provider!=='openai'||p.responses_endpoint!=='https://api.openai.com/v1/responses'||
   p.decoder_protocol!==NATIVE_JPEG_PROTOCOL||p.decoder_identity!==NATIVE_JPEG_IDENTITY||
   env.ROSTER_DECODER_PROTOCOL!==NATIVE_JPEG_PROTOCOL||env.ROSTER_DECODER_URL!==NATIVE_JPEG_IDENTITY||
   optional(env.ROSTER_DECODER_SECRET)!==undefined||!isNativeRosterJpegDecoder(env.ROSTER_DECODER)||
   env.ROSTER_DECODER.buildSha256!==p.decoder_build_sha256||
   p.decoder_build_sha256!==env.ROSTER_DECODER_BUILD_SHA256||!SHA.test(p.decoder_build_sha256??'')||
   p.model!==env.ROSTER_AI_MODEL||p.model!==env.MOMO_AI_MODEL||!TOKEN.test(p.model??'')||
   !SHA.test(p.source_sha256??'')||p.source_sha256!==env.BUILD_SOURCE_ID||
   !SHA.test(p.authorization_evidence_sha256??'')||!SHA.test(p.technical_checks_sha256??'')||
   p.collection_id!==groupId||!TOKEN.test(groupId??'')||mimeType!=='image/jpeg'||
   p.request_consent_required!==true||p.preview_only!==true||
   typeof env.OPENAI_API_KEY!=='string'||env.OPENAI_API_KEY.length<20)throw unavailable();
 const projectId=optional(env.OPENAI_PROJECT_ID),organizationId=optional(env.OPENAI_ORGANIZATION_ID);
 if(p.project_id!==projectId||p.organization_id!==organizationId||
   projectId!==undefined&&!TOKEN.test(projectId)||organizationId!==undefined&&!TOKEN.test(organizationId))throw unavailable();
 if(typeof p.authorized_at!=='string'||p.valid_until!==null&&typeof p.valid_until!=='string')throw unavailable();
 const start=Date.parse(p.authorized_at),end=p.valid_until===null?Infinity:Date.parse(p.valid_until),now=clock();
 if(!Number.isFinite(start)||p.valid_until!==null&&!Number.isFinite(end)||!Number.isFinite(now)||start>now||now>=end||start>=end)throw unavailable();
 return Object.freeze({mode:'native_static_jpeg',raw,policySha256:hash,decoderBuildSha256:p.decoder_build_sha256,
   projectId,organizationId,model:p.model,apiKey:env.OPENAI_API_KEY,decoder:env.ROSTER_DECODER,
   sourceSha256:p.source_sha256,collectionId:groupId,mimeType,startsAt:start,endsAt:end});
}

/** Validate the existing Collect roster processor approval. This is not an
 * approval generator, a model selector, a credential source or a policy bypass.
 * The same raw policy and runtime bindings are rechecked at dispatch boundaries.
 */
export function createSmartOnboardingPolicy({env,clock=()=>Date.now()}={}){
 requireThat(env&&typeof env==='object'&&typeof clock==='function','smart_import_ocr_unavailable',503);
 return Object.freeze({
   async read(context){
   try{
    const raw=env.ROSTER_AI_APPROVAL_JSON,hash=env.ROSTER_AI_APPROVAL_SHA256;
    if(typeof raw!=='string'||raw.length>16384||!SHA.test(hash??'')||await digest(raw)!==hash)throw unavailable();
    const p=JSON.parse(raw);
     if(JSON.stringify(p)!==raw.trim())throw unavailable();
     if(p.schema_version===2)return nativeSnapshot(env,p,raw,hash,clock,context);
    if(JSON.stringify(p)!==raw.trim()||p.schema_version!==1||p.status!=='approved'||p.enabled!==true||
      p.purpose!=='collect_roster_pdf_image_extraction'||p.provider!=='openai'||
      p.responses_endpoint!=='https://api.openai.com/v1/responses'||p.decoder_url!=='https://roster-decoder.internal/decode')throw unavailable();
    requireRequestId(p.approval_id);
    if(!SHA.test(p.approval_evidence_sha256??'')||!SHA.test(p.decoder_build_sha256??'')||
      p.decoder_build_sha256!==env.ROSTER_DECODER_BUILD_SHA256||p.project_id!==env.OPENAI_PROJECT_ID||
      p.organization_id!==env.OPENAI_ORGANIZATION_ID||p.model!==env.ROSTER_AI_MODEL||
      typeof env.OPENAI_API_KEY!=='string'||env.OPENAI_API_KEY.length<20||typeof env.ROSTER_DECODER?.fetch!=='function')throw unavailable();
    for(const key of ['processing_region_evidence_ref','retention_evidence_ref','decoder_processor_evidence_ref',
      'decoder_region_evidence_ref','decoder_retention_evidence_ref','project_id','organization_id','model'])
      if(typeof p[key]!=='string'||!TOKEN.test(p[key]))throw unavailable();
    const start=Date.parse(p.approved_at),end=Date.parse(p.valid_until),now=clock();
    if(!Number.isFinite(start)||!Number.isFinite(end)||!Number.isFinite(now)||start>now||end<=now||start>=end)throw unavailable();
    return Object.freeze({raw,policySha256:hash,decoderBuildSha256:p.decoder_build_sha256,
      projectId:p.project_id,organizationId:p.organization_id,model:p.model,apiKey:env.OPENAI_API_KEY,
      decoder:env.ROSTER_DECODER,startsAt:start,endsAt:end});
   }catch{throw unavailable();}
  },
  async assertCurrent(snapshot){
   const now=clock();
    if(snapshot?.mode==='native_static_jpeg'){
     try{
      const raw=env.ROSTER_AI_APPROVAL_JSON;
      if(raw!==snapshot.raw||await digest(raw)!==snapshot.policySha256||env.ROSTER_AI_APPROVAL_SHA256!==snapshot.policySha256)return false;
      const current=nativeSnapshot(env,JSON.parse(raw),raw,snapshot.policySha256,clock,
        {groupId:snapshot.collectionId,mimeType:snapshot.mimeType});
      return current.apiKey===snapshot.apiKey&&current.decoder===snapshot.decoder&&current.model===snapshot.model&&
       current.projectId===snapshot.projectId&&current.organizationId===snapshot.organizationId&&current.sourceSha256===snapshot.sourceSha256;
     }catch{return false;}
    }
   return !!snapshot&&typeof snapshot.raw==='string'&&snapshot.raw===env.ROSTER_AI_APPROVAL_JSON&&
    snapshot.policySha256===env.ROSTER_AI_APPROVAL_SHA256&&snapshot.apiKey===env.OPENAI_API_KEY&&
    snapshot.decoder===env.ROSTER_DECODER&&snapshot.decoderBuildSha256===env.ROSTER_DECODER_BUILD_SHA256&&
    snapshot.projectId===env.OPENAI_PROJECT_ID&&snapshot.organizationId===env.OPENAI_ORGANIZATION_ID&&
    snapshot.model===env.ROSTER_AI_MODEL&&Number.isFinite(now)&&now>=snapshot.startsAt&&now<snapshot.endsAt;
  }
 });
}
