// Read-only local status and authenticated archive verification. No network.
import {resolve} from 'node:path';
import {privateDirectory,readPrivateFile} from '../current-archive/bundle.mjs';
import {assertUniqueJson} from '../managed-component-refresh/capture-json.mjs';
import {canonicalPlan,planDigest} from './core.mjs';
import {verifyPinnedSources} from './source-pins.mjs';
import {PROJECT,MAX_ARCHIVE,inspectSealedFunctionBodies} from './seal.mjs';
const HASH=/^[0-9a-f]{64}$/;
const exact=(v,keys)=>v&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).sort().join('\0')===[...keys].sort().join('\0');
const fail=()=>{throw Error('OFFLINE_VERIFICATION_UNAVAILABLE');};
async function json(path){let b;try{b=await readPrivateFile(path,65536);const raw=new TextDecoder('utf-8',{fatal:true}).decode(b);assertUniqueJson(raw,65536);return JSON.parse(raw);}finally{b?.fill(0);}}
function unknown(p,pin){return {status:'capture_unconfirmed',scope:p.scope,project_ref:PROJECT,operation_id:p.operation_id,plan_sha256:pin,retryAuthorized:false};}
async function validatedPlan(plan,pin){if(!HASH.test(pin??'')||planDigest(plan)!==pin)fail();const p=JSON.parse(canonicalPlan(plan));await verifyPinnedSources(p.source_pins_sha256);await privateDirectory(p.archive_dir);return p;}
async function records(p,pin){
 let claim,outcome;try{claim=await json(resolve(p.archive_dir,'EDGE-CAPTURE-CLAIM.json'));}catch{return null;}
 if(!exact(claim,['format','scope','project_ref','operation_id','plan_sha256','automatic_retry','claim_scope'])||claim.format!=='collect.edge-capture.claim.v2'||
  claim.scope!==p.scope||claim.project_ref!==PROJECT||claim.operation_id!==p.operation_id||claim.plan_sha256!==pin||claim.automatic_retry!==false||claim.claim_scope!=='archive_directory')return null;
 try{outcome=await json(resolve(p.archive_dir,'EDGE-CAPTURE-OUTCOME.json'));}catch{return null;}
 if(!exact(outcome,['format','scope','operation_id','plan_sha256','provider_read_attempted','outcome','automatic_retry'])||outcome.format!=='collect.edge-capture.outcome.v2'||
  outcome.scope!==p.scope||outcome.operation_id!==p.operation_id||outcome.plan_sha256!==pin||outcome.provider_read_attempted!==(p.scope==='managed')||outcome.automatic_retry!==false||outcome.outcome!=='COMPLETED')return null;
 return {claim,outcome};
}
export async function captureStatus({plan,expectedPlanSha256}={}){
 const p=await validatedPlan(plan,expectedPlanSha256),r=await records(p,expectedPlanSha256);if(!r)return unknown(p,expectedPlanSha256);
 return {status:'capture_recorded_unverified',scope:p.scope,project_ref:PROJECT,operation_id:p.operation_id,plan_sha256:expectedPlanSha256,retryAuthorized:false};
}
export async function verifyCapture({plan,expectedPlanSha256}={}){
 const p=await validatedPlan(plan,expectedPlanSha256);if(!await records(p,expectedPlanSha256))return unknown(p,expectedPlanSha256);
 await privateDirectory(p.key_dir);let receipt,key,archive;
 try{
  receipt=await json(resolve(p.archive_dir,'EDGE-CAPTURE-RESULT.json'));
  if(!exact(receipt,['format','scope','project_ref','operation_id','plan_sha256','archive_sha256','archive_bytes','functions','authenticated_readback','key_custody_independent','provider_settings_included','provider_secret_configuration_included','source_may_contain_sensitive_material','metadata_response_compared','recognized_multipart_envelope','source_content_extracted','deployability_proven','coordinated_snapshot'])||
   receipt.format!=='collect.edge-capture.receipt.v2'||receipt.scope!==p.scope||receipt.project_ref!==PROJECT||receipt.operation_id!==p.operation_id||receipt.plan_sha256!==expectedPlanSha256||
   !HASH.test(receipt.archive_sha256??'')||!Number.isSafeInteger(receipt.archive_bytes)||receipt.archive_bytes<1||receipt.archive_bytes>MAX_ARCHIVE||!Array.isArray(receipt.functions)||
   receipt.authenticated_readback!==true||receipt.key_custody_independent!==false||receipt.provider_settings_included!==false||receipt.provider_secret_configuration_included!==false||
   receipt.source_may_contain_sensitive_material!==true||receipt.metadata_response_compared!==true||receipt.recognized_multipart_envelope!==true||receipt.source_content_extracted!==false||receipt.deployability_proven!==false||receipt.coordinated_snapshot!==false)fail();
  archive=await readPrivateFile(resolve(p.archive_dir,p.operation_id+'.edge.gcm'),MAX_ARCHIVE);key=await readPrivateFile(resolve(p.key_dir,p.operation_id+'.key'),32);if(key.length!==32||archive.length!==receipt.archive_bytes)fail();
  const checked=inspectSealedFunctionBodies({archive,key,operationId:p.operation_id,scope:p.scope,planSha256:expectedPlanSha256});
  const functions=checked.functions.map(({body_content_type,...safe})=>safe);if(checked.archive_sha256!==receipt.archive_sha256||JSON.stringify(functions)!==JSON.stringify(receipt.functions))fail();
  return {status:'capture_verified_point_in_time',scope:p.scope,project_ref:PROJECT,operation_id:p.operation_id,plan_sha256:expectedPlanSha256,archive_sha256:checked.archive_sha256,functions,retryAuthorized:false};
 }catch{fail();}finally{key?.fill(0);archive?.fill(0);}
}
