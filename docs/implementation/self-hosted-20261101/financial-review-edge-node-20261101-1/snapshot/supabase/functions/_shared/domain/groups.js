import {ApiError,rows,first,decode,text,uuid,integer,now,id,digest} from './core.js';
import {mutation,retainedResponse} from './mutations.js';
import {encrypt,decrypt} from './encryption.js';
import {consumeNativeCapability,canonicalRwandaPhone} from './native_integrity.js';
const boolean = value => value===1;
// Keep this allow-list aligned with the maintained Collect cover catalog.
const metadataCoverRefs=new Set(["collect-cover:rw-01-neighbourhood-ikimina:v1","collect-cover:rw-02-women-savings-circle:v1","collect-cover:rw-03-young-professionals-goal:v1","collect-cover:rw-04-market-traders-stock:v1","collect-cover:rw-05-moto-riders-shared-goal:v1","collect-cover:rw-06-farmers-season-inputs:v1","collect-cover:rw-07-family-home-goal:v1","collect-cover:rw-08-craft-cooperative-tools:v1","collect-cover:rw-09-wedding-committee:v2","collect-cover:rw-10-gusaba-gukwa-gathering:v2","collect-cover:rw-11-wedding-attire-preparation:v2","collect-cover:rw-12-wedding-reception-table:v2","collect-cover:rw-13-new-home-wedding-gift:v2","collect-cover:rw-14-wedding-day-family:v2","collect-cover:rw-15-church-community-offering:v1","collect-cover:rw-16-church-building-project:v1","collect-cover:rw-17-choir-shared-equipment:v1","collect-cover:rw-18-muslim-community-giving:v1","collect-cover:rw-19-ramadan-community-meal:v1","collect-cover:rw-20-community-giving-parcels:v1","collect-cover:rw-21-bereavement-support:v1","collect-cover:rw-22-medical-care-support:v1","collect-cover:rw-23-health-cover-contribution:v1","collect-cover:rw-24-neighbours-recovery-support:v1","collect-cover:rw-25-family-everyday-support:v1","collect-cover:rw-26-welcoming-new-baby:v1","collect-cover:rw-27-school-supplies:v1","collect-cover:rw-28-school-meal-support:v1","collect-cover:rw-29-higher-study-support:v1","collect-cover:rw-30-youth-skills-training:v1","collect-cover:rw-31-umuganda-project-tools:v1","collect-cover:rw-32-shared-water-point:v1","collect-cover:rw-33-community-hall-improvement:v1","collect-cover:rw-34-tree-planting-neighbours:v1","collect-cover:rw-35-football-fan-community:v1","collect-cover:rw-36-local-team-equipment:v1","collect-cover:rw-37-away-match-travel:v1","collect-cover:rw-38-cultural-troupe-rehearsal:v1","collect-cover:rw-41-buri-munsi:v1","collect-cover:rw-42-gikundiro:v1","collect-cover:rw-43-church-congregation:v1","collect-cover:rw-44-football-fans-matchday:v1"]);
const groupPaymentRail=row=>typeof row.receiver_momo_number==='string'&&row.receiver_momo_number.trim()&&['mtn_momo','airtel_money'].includes(row.receiver_network)?'rwanda_momo':'unavailable';
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
function metadataImage(value){
 if(value===null)return;
 if(typeof value!=='string'||value.length>2048||/[\s\u0000-\u001f]/.test(value))throw new ApiError(400,'invalid_image','Choose a supported group image.');
 if(metadataCoverRefs.has(value))return;
 try{const url=new URL(value);if(url.protocol==='https:'&&url.hostname&&!url.username&&!url.password)return;}catch{}
 throw new ApiError(400,'invalid_image','Choose a supported group image.');
}

function groupJson(row) {
 const data=decode(row); delete data.share_code_hash;delete data.share_code_ciphertext;
 return {...data,is_member:boolean(row.is_member),is_public:row.visibility_status==='public_approved',is_platform_sponsored:boolean(row.is_platform_sponsored),payment_rail:groupPaymentRail(row),settlement_currency:'RWF',moderation_status:row.status==='archived'?'archived':'not_requested',receiver_label:row.receiver_display_label};
}
export async function groupFor(env,actor,collectionId,{role=null}={}) {
 const row=await first(env,`SELECT c.*,m.role AS actor_role,1 AS is_member FROM collections c JOIN memberships m ON m.collection_id=c.id WHERE c.id=? AND m.user_id=? AND m.active=1 AND c.status='active'`,uuid(collectionId,'collection_id'),actor.userId);
 if(!row || (role && row.actor_role!==role && !(role==='admin'&&row.actor_role==='owner'))) throw new ApiError(403,'42501','This group is unavailable.');
 return row;
}
export async function publicGroups(env) {
 const list=await rows(env,`SELECT id,slug,title,description,collection_type,receiver_momo_number,receiver_display_label,receiver_network,visibility_status,is_platform_sponsored,data_json,created_at FROM collections WHERE status='active' AND visibility_status='public_approved' ORDER BY created_at DESC,id LIMIT 100`);
 return list.map(row=>{
  const data=JSON.parse(row.data_json);
  return {id:row.id,slug:row.slug,title:row.title,description:row.description,
   collection_type:row.collection_type,receiver_display_label:row.receiver_display_label,
   receiver_network:row.receiver_network,payment_rail:groupPaymentRail(row),settlement_currency:'RWF',
   visibility_status:row.visibility_status,is_public:true,is_member:false,
   is_platform_sponsored:boolean(row.is_platform_sponsored),moderation_status:'not_requested',
   category_subtype:typeof data.category_subtype==='string'?data.category_subtype:null,
   purpose_label:typeof data.purpose_label==='string'?data.purpose_label:null,
   image_url:typeof data.image_url==='string'?data.image_url:null,
   accent_color_hex:typeof data.accent_color_hex==='string'?data.accent_color_hex:null,
   is_recurring:typeof data.is_recurring==='boolean'?data.is_recurring:true,
   recurring_cadence:typeof data.recurring_cadence==='string'?data.recurring_cadence:'monthly',
   suggested_amount_rwf:Number.isSafeInteger(data.suggested_amount_rwf)&&data.suggested_amount_rwf>0?data.suggested_amount_rwf:null,
   created_at:row.created_at};
 });
}
export async function groupRpc(operation,body,env,actor) {
 const collectionId=body.p_collection_id??body.collection;
 switch(operation) {
 case 'get_current_member_profile': {
  const row=await first(env,`SELECT id,public_id,phone AS whatsapp_phone,country_code,currency_code,momo_provider,momo_number,momo_pay_code FROM users WHERE id=? AND access_status='active'`,actor.userId);return {handled:true,value:row};
 }
 case 'ensure_current_member_profile': {
  const row=await first(env,'SELECT * FROM users WHERE id=?',actor.userId);
  if(body.p_whatsapp_phone && body.p_whatsapp_phone!==row.phone) throw new ApiError(403,'42501','Profile verification does not match this sign-in.');
  return {handled:true,value:{id:row.id,public_id:row.public_id,whatsapp_phone:row.phone??'',country_code:row.country_code,currency_code:row.currency_code,momo_provider:row.momo_provider,momo_number:row.momo_number,momo_pay_code:row.momo_pay_code}};
 }
 case 'update_current_member_profile': {
  const requestId=uuid(body.p_request_id??body.request_id??id(),'request_id');
  const number=body.p_momo_number??body.momo_number;
  if(number && !/^\+?2507[2389]\d{7}$/.test(number))throw new ApiError(400,'22023','Enter a Rwanda MoMo number.');
  const phone=actor.user.phone;
  if(number && number.replace(/^\+/,'')!==phone.replace(/^\+/,''))throw new ApiError(403,'42501','Verify the MoMo number before changing it.');
  const provider=body.p_momo_provider??body.momo_provider??'mtn_momo';
  if(!['mtn_momo','airtel_money'].includes(provider))throw new ApiError(400,'22023','Invalid MoMo network.');
  await mutation(env,actor,operation,requestId,body,null,[env.DB.prepare(`UPDATE users SET momo_provider=?,momo_number=?,momo_pay_code=?,updated_at=? WHERE id=?`).bind(provider,number??phone,text(body.p_momo_pay_code??body.momo_pay_code??'not-set','pay_code',40),now(),actor.userId)]);
  return {handled:true,value:null};
 }
 case 'list_current_user_collections': {
  const requested=body.p_collection_id==null?null:uuid(body.p_collection_id,'collection_id');
  const result=await rows(env,`SELECT c.*,1 AS is_member FROM collections c JOIN memberships m ON m.collection_id=c.id WHERE m.user_id=? AND m.active=1 AND c.status!='suspended' AND (? IS NULL OR c.id=?) ORDER BY c.created_at DESC LIMIT 100`,actor.userId,requested,requested);
  return {handled:true,value:result.map(groupJson)};
 }
 case 'list_current_member_group_roster': {
  const group=await groupFor(env,actor,collectionId);
  const list=await rows(env,`SELECT m.user_id AS member_id,u.public_id,m.role,m.active,m.joined_at,(SELECT coalesce(sum(l.amount_minor),0) FROM ledger_entries l WHERE l.collection_id=m.collection_id AND l.member_id=m.user_id) AS total FROM memberships m JOIN users u ON u.id=m.user_id WHERE m.collection_id=? AND m.active=1 ORDER BY m.joined_at,m.id LIMIT 500`,group.id);
  const current=await groupFor(env,actor,group.id);
  if(current.actor_role!==group.actor_role)throw new ApiError(403,'group_access_changed','Your group access changed. Reopen the group.');
  if(list.some(row=>!Number.isSafeInteger(row.total)||row.total<0))throw new ApiError(503,'balance_unavailable','Contribution totals are unavailable.');
  return {handled:true,value:list.map(r=>{
   const own=r.member_id===actor.userId,shared=!own&&group.actor_role==='owner'&&r.total>0;
   return {public_id:r.public_id,role:r.role,status:'active',joined_at:r.joined_at,
    amount_scope:own?'own':shared?'shared':'hidden',
    contributions:(own||shared)&&r.total>0?[{currency:'RWF',amount_minor:r.total}]:[]};
  })};
 }
 case 'get_group_share_code': {
  const g=await groupFor(env,actor,collectionId);
  if(!g.share_code_ciphertext)throw new ApiError(503,'invite_unavailable','The group invitation is unavailable.');
  const code=new TextDecoder().decode(await decrypt(env,g.share_code_ciphertext,`group-invite:${g.id}`));
  return {handled:true,value:code};
 }
 case 'rotate_group_share_code_v2': {
  const g=await groupFor(env,actor,collectionId,{role:'owner'});const requestId=uuid(body.p_request_id,'request_id');const code=id();
  const value={contract_version:1,ok:true,collection_id:g.id,request_id:requestId,share_code:code};
  const cipher=await encrypt(env,new TextEncoder().encode(code),`group-invite:${g.id}`);
  return {handled:true,value:await mutation(env,actor,operation,requestId,body,value,[env.DB.prepare(`UPDATE collections SET share_code_hash=?,share_code_ciphertext=?,share_code_version=share_code_version+1,revision=revision+1,updated_at=? WHERE id=?`).bind(await digest(code),cipher,now(),g.id)],{collectionId:g.id,role:'owner',expectedCollectionRevision:g.revision})};
 }
 case 'join_group_by_share_code': {
  const code=uuid(body.p_group_code,'group_code');
  const g=await first(env,`SELECT * FROM collections WHERE share_code_hash=? AND status='active'`,await digest(code));
  if(!g)throw new ApiError(404,'group_unavailable','This invitation is unavailable.');
  await mutation(env,actor,operation,uuid(body.p_request_id??id(),'request_id'),body,g.id,[env.DB.prepare(`INSERT INTO memberships(id,collection_id,user_id,role,active,joined_at) VALUES(?,?,?,'member',1,?) ON CONFLICT(collection_id,user_id) DO UPDATE SET active=1 WHERE memberships.active=0`).bind(id(),g.id,actor.userId,now())],{inviteCollectionId:g.id,expectedShareHash:g.share_code_hash,expectedShareVersion:g.share_code_version});
  return {handled:true,value:g.id};
 }
 case 'archive_group': {
  const g=await groupFor(env,actor,collectionId,{role:'owner'});
  if(g.is_platform_sponsored || g.visibility_status==='public_approved')throw new ApiError(403,'42501','Manage this group in Admin.');
  await mutation(env,actor,operation,uuid(body.p_request_id??id(),'request_id'),body,null,[env.DB.prepare(`UPDATE collections SET status='archived',revision=revision+1,updated_at=? WHERE id=?`).bind(now(),g.id)],{collectionId:g.id,role:'owner',expectedCollectionRevision:g.revision});return {handled:true,value:null};
 }
 case 'add_group_admin': case 'transfer_group_ownership': {
  const g=await groupFor(env,actor,collectionId,{role:'owner'});
  const publicId=text(body.member_public_id??body.new_owner_public_id,'Collect ID',6);
  if(!/^\d{6}$/.test(publicId))throw new ApiError(400,'22023','Enter a six digit Collect ID.');
  const member=await first(env,`SELECT u.id FROM memberships m JOIN users u ON u.id=m.user_id WHERE m.collection_id=? AND u.public_id=? AND m.active=1 AND u.access_status='active'`,g.id,publicId);
  if(!member || member.id===actor.userId)throw new ApiError(400,'22023','Choose another active group member.');
  const writes=[];
  if(operation==='transfer_group_ownership')writes.push(env.DB.prepare(`UPDATE memberships SET role='admin' WHERE collection_id=? AND user_id=? AND role='owner'`).bind(g.id,actor.userId),env.DB.prepare(`UPDATE collections SET creator_user_id=?,revision=revision+1,updated_at=? WHERE id=?`).bind(member.id,now(),g.id));
  writes.push(env.DB.prepare('UPDATE memberships SET role=? WHERE collection_id=? AND user_id=? AND active=1').bind(operation==='add_group_admin'?'admin':'owner',g.id,member.id));
  const value=operation==='add_group_admin'?{collection_id:g.id,public_id:publicId,role:'admin',status:'active'}:null;
  return {handled:true,value:await mutation(env,actor,operation,uuid(body.p_request_id??id(),'request_id'),body,value,writes,{collectionId:g.id,role:'owner',freshSeconds:operation==='transfer_group_ownership'?300:null,expectedCollectionRevision:g.revision,recipientUserId:member.id,recipientCollectionId:g.id})};
 }
 case 'update_rwanda_momo_group_profile': {
  const g=await groupFor(env,actor,collectionId,{role:'owner'});
  if(g.is_platform_sponsored===1||g.visibility_status==='public_approved')throw new ApiError(403,'admin_managed_group','Manage this Collect-sponsored group in Admin.');
  const data=JSON.parse(g.data_json);Object.assign(data,{image_url:body.p_group_image_url===''?null:body.p_group_image_url??data.image_url,accent_color_hex:body.p_group_accent_color_hex??data.accent_color_hex,is_recurring:body.p_group_is_recurring??data.is_recurring,recurring_cadence:body.p_group_recurring_cadence??data.recurring_cadence,category_subtype:body.p_group_category_subtype,purpose_label:body.p_group_purpose_label});
  if(data.image_url)metadataImage(data.image_url);
  await mutation(env,actor,operation,uuid(body.p_request_id??id(),'request_id'),body,null,[env.DB.prepare('UPDATE collections SET title=?,description=?,collection_type=?,data_json=?,visibility_status=?,revision=revision+1,updated_at=? WHERE id=?').bind(text(body.p_group_name,'group_name',100),body.p_group_description??'',body.p_group_collection_type??g.collection_type,JSON.stringify(data),body.p_group_is_public?'public_pending':'private',now(),g.id)],{collectionId:g.id,role:'owner',expectedCollectionRevision:g.revision});
  return {handled:true,value:null};
 }
 case 'get_owner_group_health': {
  const g=await groupFor(env,actor,collectionId,{role:'owner'});
  const pending=await first(env,`SELECT count(*) AS n FROM payment_intents WHERE collection_id=? AND status='pending' AND expires_at>?`,g.id,now());
  return {handled:true,value:{collection_id:g.id,sms_access_enabled:false,receiver_configured:!!g.receiver_momo_number,pending_payment_intents:pending.n,needs_review_events:0,last_synced_at:null}};
 }
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
