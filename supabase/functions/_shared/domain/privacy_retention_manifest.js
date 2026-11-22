import {integer,uuid} from './core.js';
import {authority,retentionBatch,retentionFail,retentionSha} from './privacy_retention_policy.js';

// Sealed descriptors are an inspection receipt. Neither endpoint creates a
// retention policy, approves an erasure, or calls a physical-object provider.
function exact(input,keys){
 if(!input||typeof input!=='object'||Array.isArray(input)||Object.keys(input).some(k=>!keys.includes(k)))
  retentionFail('privacy_retention_input_invalid',400);
}
async function execute(env,statement){
 try{
  const value=(await retentionBatch(env,[statement]))[0]?.results?.[0]?.inventory;
  if(value?.contract_version!==2||value.scope!=='sealed_metadata_inventory'||value.complete_capture!==true||
   !retentionSha.test(value.manifest_sha256??'')||!retentionSha.test(value.page_sha256??'')||
   !Array.isArray(value.descriptors)||value.descriptors.length<1||value.descriptors.length>100||
   value.approval_granted!==false||value.erasure_completed!==false||value.physical_objects_verified!==false)
   retentionFail('privacy_retention_manifest_invalid');
  return value;
 }catch(error){
  if(/^retention_manifest_/.test(String(error?.message??'')))
   retentionFail('privacy_'+error.message,error.message==='retention_manifest_capacity_exceeded'?413:409);
  throw error;
 }
}
export async function captureRetentionInventory(env,actor,input){
 exact(input,['operation_id','request_id','expected_review_revision','expected_source_id']);
 await authority(env,actor);
 const operation=uuid(input.operation_id,'operation_id'),request=uuid(input.request_id,'request_id');
 const revision=integer(input.expected_review_revision,'review_revision',0,1000000000);
 if(!retentionSha.test(env.BUILD_SOURCE_ID??'')||input.expected_source_id!==env.BUILD_SOURCE_ID)
  retentionFail('privacy_retention_source_changed');
 return execute(env,env.DB.prepare('SELECT private.retention_capture_inventory_v2(?::uuid,?::text,?::bigint,?::text,1000000) AS inventory')
  .bind(operation,request,revision,env.BUILD_SOURCE_ID));
}
export async function readRetentionInventoryPage(env,actor,input){
 exact(input,['manifest_id','manifest_sha256','page_number','verify_current']);
 await authority(env,actor);
 const manifest=uuid(input.manifest_id,'manifest_id'),page=integer(input.page_number,'page_number',0,9999);
 if(!retentionSha.test(input.manifest_sha256??'')||input.verify_current!==undefined&&typeof input.verify_current!=='boolean')
  retentionFail('privacy_retention_input_invalid',400);
 return execute(env,env.DB.prepare('SELECT private.retention_inventory_page_v2(?::uuid,?::text,?::integer,?::boolean) AS inventory')
  .bind(manifest,input.manifest_sha256,page,input.verify_current??false));
}
