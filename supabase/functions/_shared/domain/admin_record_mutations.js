import {first,uuid,text,integer,now,id,digest} from './core.js';
import {permission,fail,unavailable} from './admin_records.js';
import {mutation,retainedResponse} from './mutations.js';
import {assertMemberManagementTarget,memberManagementGuard} from './user_access.js';
import {personInsertStatement,membershipWriteStatement} from './canonical_people.js';
import {encrypt} from './encryption.js';
import {accountDatabase} from './admin_accounts.js';
import {keys,optionalText} from './admin_operation_fields.js';
import {domainGuard,receipt} from './admin_request_aliases.js';

function memberMomoCode(value,previous=''){
 // An omitted PATCH field preserves retained history, including legacy data.
 if(value===undefined)return previous;
 const code=optionalText(value,'MoMo code',40)??'';
 if(code&&!/^[0-9]{4,9}$/.test(code))fail(400,'invalid_momo_code','Use 4–9 digits and preserve leading zeros.');
 return code;
}
function expected(data,current){const value=integer(data.expected_version,'expected_version',1);if(value!==current)fail(409,'stale_state','The record changed. Refresh before continuing.');return value;}
function rwPhone(value,{optional=false}={}){if(optional&&(value==null||value===''))return null;if(typeof value!=='string')fail(400,'invalid_phone','Enter a Rwanda phone number.');const digits=value.replace(/^\+/,'');
 const normalized=/^07[2389]\d{7}$/.test(digits)?'250'+digits.slice(1):digits;if(!/^2507[2389]\d{7}$/.test(normalized))fail(400,'invalid_phone','Enter a Rwanda phone number.');return '+'+normalized;}
function validReceiver(receiver,{allowCode=false,allowLegacyPublicCode=false}={}){if(!receiver||typeof receiver!=='object'||Array.isArray(receiver))fail(400,'invalid_receiver','Record the group receiver.');keys(receiver,['label','network','momo_number_or_code']);
 if(!['mtn_momo','airtel_money'].includes(receiver.network))fail(400,'invalid_receiver','Choose a Rwanda MoMo network.');
 const route=receiver.momo_number_or_code;
 // New public destinations must be registrable by the receiving-account API.
 // The negative lookahead requires the actual end, including after newlines.
 if(allowCode&&!allowLegacyPublicCode&&(typeof route!=='string'||!/^(?:[0-9]{4,9}|07[2389][0-9]{7}|\+?2507[2389][0-9]{7})(?![\s\S])/.test(route)))
  fail(400,'invalid_receiver','Enter a Rwanda MoMo number or a 4–9 digit merchant code.');
 const code=allowCode&&typeof route==='string'&&/^[0-9]{4,12}$/.test(route)&&!/^07[2389][0-9]{7}$/.test(route);
 return {label:text(receiver.label,'receiver label',120),network:receiver.network,number:code?route:rwPhone(route).slice(1)};}

const writeRecord={
 groups:writeGroup,
 users:writePerson,
 memberships:writeMembership,
 payees:writePayee,
};

export async function genericMutation(request,env,account,actor,parts,data,rid,source){
 const type=parts[0],create=request.method==='POST'&&parts.length===1,patch=request.method==='PATCH'&&parts.length>=2,
  operation=`admin.bridge.${type}.${request.method.toLowerCase()}.${parts.slice(1).join('.')}`;
 if(!Object.hasOwn(writeRecord,type))unavailable();
 const capability=type==='groups'&&create?'collections.create':`${permission[type]??(type==='memberships'?'collections':'')}.manage`;
 if(!actor.permissions.has(capability))fail(403,'permission_required','This operating action is unavailable.');
 const publicCreate=type==='groups'&&create&&(data.visibility==='public_approved'||data.is_platform_sponsored===true);
 // An owner-less public submission is the existing platform-sponsored form,
 // not a customer creation or permission to select an arbitrary operator.
 const platformCreate=publicCreate&&!Object.hasOwn(data,'owner_user_id');
 const publicationRequest=publicCreate||(type==='groups'&&patch&&(data.visibility!==undefined||data.is_platform_sponsored!==undefined));
 if(publicationRequest){
  if(!['owner','admin'].includes(account.role)||!actor.permissions.has('collections.manage')||!actor.permissions.has('receivers.manage'))fail(403,'permission_required','Only an administrator can publish a public group.');
  // Every publication permission and the current cookie/MFA proof are checked
  // in the same D1 batch as the alias, receipt, group, owner membership and audit.
  if(platformCreate&&account.role!=='owner')fail(403,'owner_required','The current Collect owner creates platform-sponsored groups.');
  env=accountDatabase(accountDatabase(env,account,'collections.manage',{owner:platformCreate,mfa:true,fresh:true}),account,'receivers.manage',{owner:platformCreate,mfa:true,fresh:true});
 }
 const options={permission:capability,minimumAssurance:2,freshSeconds:300,auditDetails:{reason:text(data.reason,'reason',500)}};
 const replay=await retainedResponse(env,actor,operation,rid,source,options);if(replay.found)return replay.value;
 if(!create&&!patch)unavailable();
 const resourceId=create?id():uuid(parts[1]),timestamp=now();
 const {writes,version,receiptId,entityType,entityId}=await writeRecord[type](env,{account,actor,parts,data,create,resourceId,timestamp,platformCreate,publicCreate});
 return mutation(env,actor,operation,rid,source,receipt(rid,type,receiptId,version),writes,{...options,entityType,entityId});
}

async function writeGroup(env,{account,actor,data,create,resourceId,timestamp,platformCreate,publicCreate}){
 const writes=[];let version=1;
  keys(data,['title','slug','description','collection_type','purpose_label','status','visibility','is_platform_sponsored','owner_user_id','receiver','reason','expected_version',...(platformCreate?['category_subtype']:[])]);
  if(create){if(data.expected_version!==undefined)fail(400,'invalid_request','New groups do not accept an expected version.');
   const visibility=data.visibility??'private',sponsored=data.is_platform_sponsored??false;
    if(!['private','public_approved'].includes(visibility)||typeof sponsored!=='boolean'||(visibility==='public_approved')!==sponsored)fail(400,'invalid_publication','Choose a private group or a public Collect-sponsored group.');
    const title=text(data.title,'title',160),slug=text(data.slug??(platformCreate?`collect-${resourceId}`:undefined),'slug',100),owner=platformCreate?actor.userId:uuid(data.owner_user_id,'owner_user_id'),receiver=validReceiver(data.receiver,{allowCode:publicCreate}),kind=text(data.collection_type,'collection_type',64);
   // users.id is text: normalizing a different spelling could select another
   // row. Exact retained responses have already been checked above.
   if(!platformCreate&&data.owner_user_id!==owner)fail(400,'invalid_owner','The selected owner cannot be verified. Refresh the member record.');
   if(!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug)||!['ikimina','sport','church','wedding','other'].includes(kind))fail(400,'invalid_group','Choose a supported group type and slug.');
   if(data.status&&data.status!=='active')unavailable();
   const description=data.description??'';if(typeof description!=='string'||description.length>2000)fail(400,'invalid_group','The group description is too long.');
   const guard=domainGuard(env,platformCreate?
    "EXISTS(SELECT 1 FROM users u JOIN admin_principal_links l ON l.user_id=u.id JOIN admin_users a ON a.id=l.admin_user_id WHERE u.id=? AND u.access_status='active' AND a.id=? AND a.role='owner' AND a.status='active')":
    "EXISTS(SELECT 1 FROM users WHERE id=? AND access_status='active' AND member_type!='operator')",platformCreate?[owner,account.id]:[owner]);
   const code=id(),cipher=await encrypt(env,new TextEncoder().encode(code),`group-invite:${resourceId}`);
   const stored={purpose_label:optionalText(data.purpose_label,'purpose label',120)};
   if(platformCreate)stored.category_subtype=optionalText(data.category_subtype,'category key',120);
   writes.push(guard[0],env.DB.prepare(`INSERT INTO collections(id,slug,creator_user_id,title,description,collection_type,receiver_momo_number,receiver_network,receiver_display_label,visibility_status,is_platform_sponsored,share_code_hash,share_code_ciphertext,data_json,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`).bind(resourceId,slug,owner,title,description,kind,receiver.number,receiver.network,receiver.label,visibility,Number(sponsored),await digest(code),cipher,JSON.stringify(stored),timestamp,timestamp));
   // A sponsor's accountable creator is not a financial member/beneficiary.
   // Ordinary private/person-owned groups retain their existing owner member.
   if(!platformCreate)writes.push(env.DB.prepare(`INSERT INTO memberships(id,collection_id,user_id,role,active,joined_at) VALUES(?,?,?,'owner',1,?)`).bind(id(),resourceId,owner,timestamp));
   writes.push(guard[1]);
  }else{
   const row=await first(env,'SELECT * FROM collections WHERE id=?',resourceId);if(!row)fail(404,'not_found','The group was not found.');version=expected(data,row.revision)+1;
   if(row.status==='archived')fail(409,'group_archived','Archived groups cannot be changed.');
   if(data.receiver!==undefined&&(row.is_platform_sponsored===1||row.visibility_status==='public_approved'))fail(409,'receiver_locked','The public group receiver is permanently locked.');
   if(data.owner_user_id!==undefined||data.receiver!==undefined)unavailable();const status=data.status??row.status;
   if(!['active','suspended','archived'].includes(status))unavailable();const visibility=data.visibility??row.visibility_status;
   if(data.visibility!==undefined&&!['private','public_approved'].includes(visibility))fail(400,'invalid_publication','Choose private or public visibility.');
   const sponsored=row.is_platform_sponsored===1||row.visibility_status==='public_approved'||visibility==='public_approved';
   if(data.is_platform_sponsored!==undefined&&(typeof data.is_platform_sponsored!=='boolean'||data.is_platform_sponsored!==sponsored))fail(409,'publication_locked','A public group stays Collect-sponsored and its receiver stays locked.');
   if(visibility==='public_approved')validReceiver({label:row.receiver_display_label,network:row.receiver_network,momo_number_or_code:row.receiver_momo_number},{allowCode:true,allowLegacyPublicCode:row.visibility_status==='public_approved'});
   const kind=data.collection_type??row.collection_type;if(!['ikimina','sport','church','wedding','other'].includes(kind))fail(400,'invalid_group','Choose a supported group type.');
   const stored=JSON.parse(row.data_json);if(data.purpose_label!==undefined)stored.purpose_label=optionalText(data.purpose_label,'purpose label',120);
   const description=data.description??row.description;if(typeof description!=='string'||description.length>2000)fail(400,'invalid_group','The group description is too long.');
   const guard=domainGuard(env,'EXISTS(SELECT 1 FROM collections WHERE id=? AND revision=? AND visibility_status=? AND is_platform_sponsored=? AND receiver_momo_number IS ? AND receiver_network IS ? AND receiver_display_label IS ?)',[resourceId,row.revision,row.visibility_status,row.is_platform_sponsored,row.receiver_momo_number,row.receiver_network,row.receiver_display_label]);
   writes.push(guard[0],env.DB.prepare(`UPDATE collections SET title=?,description=?,collection_type=?,status=?,visibility_status=?,is_platform_sponsored=?,revision=revision+1,data_json=?,updated_at=? WHERE id=?`).bind(data.title===undefined?row.title:text(data.title,'title',160),description,kind,status,visibility,Number(sponsored),JSON.stringify(stored),timestamp,resourceId));
   if(status!=='active'||visibility!==row.visibility_status||Number(sponsored)!==row.is_platform_sponsored)writes.push(env.DB.prepare(`UPDATE payment_intents SET status='cancelled' WHERE collection_id=? AND status='pending'`).bind(resourceId));writes.push(guard[1]);
  }
 return {writes,version,receiptId:resourceId,entityType:'collection',entityId:resourceId};
}

async function writePerson(env,{actor,data,create,resourceId,timestamp}){
 const writes=[];let version=1;
  keys(data,['display_name','email','phone_e164','member_type','momo_provider','momo_number','momo_pay_code','status','reason','expected_version']);
  const row=create?null:await first(env,'SELECT * FROM users WHERE id=?',resourceId);if(!create&&!row)fail(404,'not_found','The person was not found.');
  if(row)await assertMemberManagementTarget(env,row);const memberType=data.member_type??row?.member_type??'app';if(!['app','direct'].includes(memberType)||(!create&&memberType!==row.member_type))unavailable();
  const fullName=data.display_name===undefined?row?.full_name:text(data.display_name,'display name',120);if(!fullName)fail(400,'invalid_name','Record the full name.');
  const phone=data.phone_e164===undefined?row?.phone??null:rwPhone(data.phone_e164,{optional:true}),email=data.email===undefined?row?.email??null:optionalText(data.email,'email',254);
  if(email&&!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))fail(400,'invalid_email','Enter a valid email address.');
  const momo=data.momo_number===undefined?row?.momo_number??'':rwPhone(data.momo_number,{optional:true})?.replace(/^\+250/,'0')??'',provider=data.momo_provider??row?.momo_provider??'';
  if(provider&&!['mtn_momo','airtel_money'].includes(provider))fail(400,'invalid_network','Choose a Rwanda MoMo network.');
  if(memberType==='direct'&&!momo)fail(400,'invalid_profile','Record the Direct member MoMo number.');
  if(memberType==='app'&&!phone&&!email)fail(400,'invalid_profile','Record a phone number or email address.');
  const code=memberMomoCode(data.momo_pay_code,row?.momo_pay_code??''),status=data.status??row?.access_status??'active';if(!['active','suspended'].includes(status))unavailable();
  if(!create&&(data.phone_e164!==undefined||data.email!==undefined))unavailable(); // Credential changes require their own verified workflow.
  if(resourceId===actor.userId&&status==='suspended')fail(409,'self_suspend','Ask another administrator to suspend this person.');
  if(create){writes.push(personInsertStatement(env.DB,{id:resourceId,name:fullName,phone,email,memberType,provider,momo,code,status,timestamp}));
  }else{version=expected(data,row.revision)+1;const guards=memberManagementGuard(env,row,status);
   writes.push(guards[0],env.DB.prepare(`UPDATE users SET full_name=?,momo_provider=?,momo_number=?,momo_pay_code=?,access_status=?,revision=revision+1,updated_at=? WHERE id=?`).bind(fullName,provider,momo,code,status,timestamp,resourceId));
   if(status==='suspended')writes.push(env.DB.prepare(`UPDATE auth_sessions SET revoked_at=?,revocation_reason='account_suspended' WHERE user_id=? AND revoked_at IS NULL`).bind(Math.floor(Date.now()/1000),resourceId));writes.push(guards[1]);}
 return {writes,version,receiptId:resourceId,entityType:'user',entityId:resourceId};
}

async function writeMembership(env,{parts,data,create,timestamp}){
 let version=1;
  keys(data,['group_id','user_id','role','status','reason','expected_version']);
  // A partial PATCH must not silently demote an administrator or reactivate a
  // removed member. Existing exact request receipts were checked above.
  if(!create&&(data.role==null||data.status==null))fail(400,'invalid_request','Provide both group role and membership status.');
  const groupId=uuid(create?data.group_id:parts[1]),userId=uuid(create?data.user_id:parts[2]),role=data.role??'member',active=(data.status??'active')==='active'?1:0;
  if(!['member','admin'].includes(role)||!['active','removed','left'].includes(data.status??'active'))unavailable();
  const existing=await first(env,'SELECT * FROM memberships WHERE collection_id=? AND user_id=?',groupId,userId);if(existing?.role==='owner')unavailable();
  if(!create){if(!existing)fail(404,'not_found','The membership was not found.');version=expected(data,existing.revision)+1;}
  const guard=domainGuard(env,`EXISTS(SELECT 1 FROM collections WHERE id=? AND status='active') AND EXISTS(SELECT 1 FROM users WHERE id=? AND access_status='active' AND member_type!='operator')
   AND (?=1 OR EXISTS(SELECT 1 FROM memberships WHERE collection_id=? AND user_id=? AND revision=? AND role!='owner'))`,[groupId,userId,Number(create),groupId,userId,existing?.revision??0]);
  const writes=[guard[0],membershipWriteStatement(env.DB,{create,id:create?id():null,groupId,userId,role,active,timestamp}),guard[1]];
 return {writes,version,receiptId:`${groupId}/${userId}`,entityType:'membership',entityId:groupId};
}

async function writePayee(env,{data,create,resourceId,timestamp}){
  keys(data,['group_id','label','network','momo_number_or_code','status','reason','expected_version']);
  const groupId=uuid(create?data.group_id:resourceId),row=await first(env,'SELECT * FROM collections WHERE id=?',groupId);if(!row)fail(404,'not_found','The group was not found.');
   if(row.is_platform_sponsored===1||row.visibility_status==='public_approved')fail(409,'receiver_locked','The public group receiver is permanently locked.');
  if(row.status!=='active'||data.status&&data.status!=='active')unavailable();const version=expected(data,row.revision)+1;
  const receiver=validReceiver({label:data.label??row.receiver_display_label,network:data.network??row.receiver_network,momo_number_or_code:data.momo_number_or_code??row.receiver_momo_number});
  const guard=domainGuard(env,"EXISTS(SELECT 1 FROM collections WHERE id=? AND revision=? AND status='active' AND is_platform_sponsored=0 AND visibility_status!='public_approved')",[groupId,row.revision]);
  const writes=[guard[0],env.DB.prepare(`UPDATE collections SET receiver_display_label=?,receiver_network=?,receiver_momo_number=?,revision=revision+1,updated_at=? WHERE id=?`).bind(receiver.label,receiver.network,receiver.number,timestamp,groupId),env.DB.prepare(`UPDATE payment_intents SET status='cancelled' WHERE collection_id=? AND status='pending'`).bind(groupId),guard[1]];
 return {writes,version,receiptId:groupId,entityType:'collection',entityId:groupId};
}
