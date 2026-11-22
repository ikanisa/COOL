import {ApiError,digest,first,id,now,text,uuid} from '../core.js';
import {encrypt} from '../encryption.js';
import {mutation,retainedResponse} from '../mutations.js';
import {canonicalRwandaPhone,consumeNativeCapability} from '../native_integrity.js';

// Keep this allow-list aligned with the maintained Collect cover catalog.
const metadataCoverRefs=new Set(["collect-cover:rw-01-neighbourhood-ikimina:v1","collect-cover:rw-02-women-savings-circle:v1","collect-cover:rw-03-young-professionals-goal:v1","collect-cover:rw-04-market-traders-stock:v1","collect-cover:rw-05-moto-riders-shared-goal:v1","collect-cover:rw-06-farmers-season-inputs:v1","collect-cover:rw-07-family-home-goal:v1","collect-cover:rw-08-craft-cooperative-tools:v1","collect-cover:rw-09-wedding-committee:v2","collect-cover:rw-10-gusaba-gukwa-gathering:v2","collect-cover:rw-11-wedding-attire-preparation:v2","collect-cover:rw-12-wedding-reception-table:v2","collect-cover:rw-13-new-home-wedding-gift:v2","collect-cover:rw-14-wedding-day-family:v2","collect-cover:rw-15-church-community-offering:v1","collect-cover:rw-16-church-building-project:v1","collect-cover:rw-17-choir-shared-equipment:v1","collect-cover:rw-18-muslim-community-giving:v1","collect-cover:rw-19-ramadan-community-meal:v1","collect-cover:rw-20-community-giving-parcels:v1","collect-cover:rw-21-bereavement-support:v1","collect-cover:rw-22-medical-care-support:v1","collect-cover:rw-23-health-cover-contribution:v1","collect-cover:rw-24-neighbours-recovery-support:v1","collect-cover:rw-25-family-everyday-support:v1","collect-cover:rw-26-welcoming-new-baby:v1","collect-cover:rw-27-school-supplies:v1","collect-cover:rw-28-school-meal-support:v1","collect-cover:rw-29-higher-study-support:v1","collect-cover:rw-30-youth-skills-training:v1","collect-cover:rw-31-umuganda-project-tools:v1","collect-cover:rw-32-shared-water-point:v1","collect-cover:rw-33-community-hall-improvement:v1","collect-cover:rw-34-tree-planting-neighbours:v1","collect-cover:rw-35-football-fan-community:v1","collect-cover:rw-36-local-team-equipment:v1","collect-cover:rw-37-away-match-travel:v1","collect-cover:rw-38-cultural-troupe-rehearsal:v1","collect-cover:rw-41-buri-munsi:v1","collect-cover:rw-42-gikundiro:v1","collect-cover:rw-43-church-congregation:v1","collect-cover:rw-44-football-fans-matchday:v1"]);

// Product audience is every current signed-in account. Financial/profile and
// Android attestation requirements belong to their corresponding operations.
const metadataAuthority=`EXISTS(SELECT 1 FROM auth_sessions s JOIN users u ON u.id=s.user_id WHERE s.id=? AND s.user_id=? AND s.revoked_at IS NULL AND s.expires_at>unixepoch() AND u.access_status='active')`;
const metadataBudget=`(SELECT count(*) FROM request_receipts WHERE user_id=? AND operation='create_private_group_metadata_v1' AND request_id!=? AND created_at>=strftime('%Y-%m-%dT%H:%M:%fZ','now','-1 hour'))<3 AND (SELECT count(*) FROM request_receipts WHERE user_id=? AND operation='create_private_group_metadata_v1' AND request_id!=? AND created_at>=strftime('%Y-%m-%dT%H:%M:%fZ','now','-1 day'))<10`;
async function metadataAccess(env,actor,requestId,{budget=false}={}) {
 if(!(await first(env,'SELECT '+metadataAuthority+' AS allowed',actor.sessionId,actor.userId))?.allowed)throw new ApiError(403,'group_creation_unavailable','Use your current active sign-in to create a group.');
 if(budget&&!(await first(env,'SELECT '+metadataBudget+' AS allowed',actor.userId,requestId,actor.userId,requestId))?.allowed)throw new ApiError(429,'group_creation_limited','Group creation is temporarily limited. Try again later.');
}
function metadataGuard(env,actor,requestId){const key=id();return [env.DB.prepare('INSERT INTO admin_bridge_guards(id,passed) SELECT ?,CASE WHEN '+metadataAuthority+' AND '+metadataBudget+' THEN 1 ELSE 0 END').bind(key,actor.sessionId,actor.userId,actor.userId,requestId,actor.userId,requestId),env.DB.prepare('DELETE FROM admin_bridge_guards WHERE id=?').bind(key)];}
function metadataText(value,field,max){
 if(typeof value==='string'&&/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(value))throw new ApiError(400,'invalid_parameter',`Invalid ${field}.`);
 return text(typeof value==='string'?value.trim():value,field,max);
}
export function metadataImage(value){
 if(value===null)return;
 if(typeof value!=='string'||value.length>2048||/[\s\u0000-\u001f]/.test(value))throw new ApiError(400,'invalid_image','Choose a supported group image.');
 if(metadataCoverRefs.has(value))return;
 try{const url=new URL(value);if(url.protocol==='https:'&&url.hostname&&!url.username&&!url.password)return;}catch{}
 throw new ApiError(400,'invalid_image','Choose a supported group image.');
}

export async function createPrivateGroup(operation,body,env,actor) {
 switch(operation) {
 case 'create_private_group_metadata_v1': {
  const allowed=['p_request_id','build_channel','group_name','group_description','group_collection_type','group_category_subtype','group_purpose_label','group_image_url','group_accent_color_hex','group_is_public'];
  if(Object.keys(body).some(key=>!allowed.includes(key))||body.build_channel!=='android_group_metadata'||body.group_is_public!==false)throw new ApiError(400,'invalid_group_metadata','Use the private group metadata request.');
  const requestId=uuid(body.p_request_id,'request_id');await metadataAccess(env,actor,requestId);
  const previous=await retainedResponse(env,actor,operation,requestId,body);if(previous.found)return {handled:true,value:previous.value};
  const kind=metadataText(body.group_collection_type,'group type',64);if(!['ikimina','sport','church','wedding','other'].includes(kind))throw new ApiError(400,'invalid_group_type','Choose a supported group type.');
  const title=metadataText(body.group_name,'group name',100),description=body.group_description??'';
  if(typeof description!=='string'||description.trim().length>2000||/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(description))throw new ApiError(400,'invalid_group_description','The group description is invalid.');
  const optional=(value,field,max)=>value==null||value===''?null:metadataText(value,field,max);
  const image=optional(body.group_image_url,'group image',2048),accent=optional(body.group_accent_color_hex,'group colour',7);metadataImage(image);
  if(accent!==null&&!/^#[a-f0-9]{6}$/i.test(accent))throw new ApiError(400,'invalid_accent','Choose a valid group colour.');
  const data={category_subtype:optional(body.group_category_subtype,'group category',128),purpose_label:optional(body.group_purpose_label,'group purpose',128),image_url:image,accent_color_hex:accent,is_recurring:true,recurring_cadence:'monthly'};
  await metadataAccess(env,actor,requestId,{budget:true});
  const groupId=id(),code=id(),at=now(),slug=(title.toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'')||'group')+'-'+groupId.slice(0,8),cipher=await encrypt(env,new TextEncoder().encode(code),`group-invite:${groupId}`),guard=metadataGuard(env,actor,requestId);
  // The lock and COUNT are separate statements in the SAME transaction: under
  // READ COMMITTED the count observes the previous owner's committed receipt
  // after a lock wait. Exclude this receipt, which mutation() inserts first.
  const writes=[env.DB.prepare('SELECT pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(?,734636924058502::bigint))').bind(actor.userId),guard[0],
   env.DB.prepare(`INSERT INTO collections(id,slug,creator_user_id,title,description,collection_type,receiver_momo_number,receiver_display_label,receiver_network,visibility_status,share_code_hash,share_code_ciphertext,data_json,created_at,updated_at) VALUES(?,?,?,?,?,?,NULL,NULL,NULL,'private',?,?,?,?,?)`).bind(groupId,slug,actor.userId,title,description.trim(),kind,await digest(code),cipher,JSON.stringify(data),at,at),
   env.DB.prepare(`INSERT INTO memberships(id,collection_id,user_id,role,active,joined_at) VALUES(?,?,?,'owner',1,?)`).bind(id(),groupId,actor.userId,at),guard[1]];
  try{return {handled:true,value:await mutation(env,actor,operation,requestId,body,groupId,writes,{entityType:'collection',entityId:groupId,auditDetails:{capability:'private_group_metadata_v1',payment_route:'unavailable',financial_effects:0}})};}catch(error){if(error instanceof ApiError&&error.code==='request_conflict')throw error;await metadataAccess(env,actor,requestId,{budget:true});throw error;}
 }
 case 'create_private_group_with_owner_media_attested': {
  const requestId=uuid(body.p_request_id,'request_id');
  const previous=await retainedResponse(env,actor,operation,requestId,body);
  if(previous.found)return {handled:true,value:previous.value};
  const claim=await consumeNativeCapability(env,actor,body.native_capability,'group.create',body);
  const phone=canonicalRwandaPhone(body.receiver_momo_number);
  const owner=await first(env,'SELECT phone,momo_provider FROM users WHERE id=? AND access_status=\'active\'',actor.userId);
  if(!owner?.phone||canonicalRwandaPhone(owner.phone)!==phone)throw new ApiError(403,'receiver_verification_required','Verify the group receiver before creating a group.');
  if(!['mtn_momo','airtel_money'].includes(owner.momo_provider))throw new ApiError(400,'invalid_receiver','Complete the verified MoMo profile first.');
  const kind=text(body.group_collection_type,'group type',64);
  if(!['ikimina','sport','church','wedding','other'].includes(kind))throw new ApiError(400,'invalid_group_type','Choose a supported group type.');
  const title=text(body.group_name,'group name',100),label=text(body.receiver_label,'receiver label',80);
  const description=body.group_description??'';
  if(typeof description!=='string'||description.length>2000)throw new ApiError(400,'invalid_group_description','The group description is too long.');
  const image=body.group_image_url??null,accent=body.group_accent_color_hex??null;
  if(image!==null&&(typeof image!=='string'||image.length>2048||!/^https:\/\/[^\s]+$/.test(image)))throw new ApiError(400,'invalid_image','Choose a valid group image.');
  if(accent!==null&&(typeof accent!=='string'||!/^#[a-f0-9]{6}$/i.test(accent)))throw new ApiError(400,'invalid_accent','Choose a valid group colour.');
  const groupId=id(),code=id(),at=now();
  const slug=(title.toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'')||'group')+'-'+groupId.slice(0,8);
  const data={category_subtype:body.group_category_subtype??null,purpose_label:body.group_purpose_label??null,image_url:image,accent_color_hex:accent,is_recurring:true,recurring_cadence:'monthly'};
  const cipher=await encrypt(env,new TextEncoder().encode(code),`group-invite:${groupId}`);
  const writes=[claim,
   env.DB.prepare(`INSERT INTO collections(id,slug,creator_user_id,title,description,collection_type,receiver_momo_number,receiver_display_label,receiver_network,visibility_status,share_code_hash,share_code_ciphertext,data_json,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,'private',?,?,?,?,?)`).bind(groupId,slug,actor.userId,title,description,kind,phone.replace(/^\+/,''),label,owner.momo_provider,await digest(code),cipher,JSON.stringify(data),at,at),
   env.DB.prepare(`INSERT INTO memberships(id,collection_id,user_id,role,active,joined_at) VALUES(?,?,?,'owner',1,?)`).bind(id(),groupId,actor.userId,at)];
  return {handled:true,value:await mutation(env,actor,operation,requestId,body,groupId,writes,{entityType:'collection',entityId:groupId})};
 }
 default:return {handled:false};
 }
}
