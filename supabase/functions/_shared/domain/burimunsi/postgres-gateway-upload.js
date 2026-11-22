import {ApiError} from '../core.js';
import {nativeGatewayUploadsEnabled,gatewayUploadHeld} from '../../gateway-upload-hold.js';
import {classifyGatewayPair} from './postgres-gateway-classification.js';
import {PostgresNativeAuthority} from './postgres-authority.js';
import {validateProviderProfile} from '../momo_pipeline.js';
import {classifyCapture} from './receipt.js';
import {pgInteger} from './postgres-values.js';

const plans=new WeakMap();
const unavailable=()=>new ApiError(503,'gateway_capture_unavailable','Keep this capture pending and check the receiving setup.');
const denied=()=>new ApiError(403,'gateway_authority_changed','The receiving installation is no longer authorized for this capture.');
const need=(ok,error=unavailable)=>{if(!ok)throw error();};
const positive=value=>pgInteger(value,{minimum:1,code:'gateway_capture_unavailable'});
export const GATEWAY_UPLOAD_SNAPSHOT_FIELDS=Object.freeze(['collection_id','scope_version','receiving_account_id','binding_id','binding_version','owner_user_id',
 'subscription_evidence','binding_created_at','provider','public_code','recipient_name','currency','timezone','receiver_hash',
 'profile_status','profile_version','profile_json','credential_id','token_sha256','pairing_id','installation_id',
 'pairing_code_sha256','originating_session_id','grant_id','grant_version','grant_token_hash','custodian_account_id',
 'account_version','credential_version','phone','capabilities']);
const fields=GATEWAY_UPLOAD_SNAPSHOT_FIELDS;

// Every source is server-derived. No client group, supplied principal, alternate
// writer, PIN or native bearer session is created by this anonymous capture path.
export const GATEWAY_UPLOAD_AUTHORITY_SQL=`SELECT scope.collection_id,CAST(scope.version AS text) AS scope_version,
 scope.receiving_account_id,b.id AS binding_id,CAST(b.version AS text) AS binding_version,b.owner_user_id,
 b.subscription_evidence,b.created_at AS binding_created_at,w.provider,w.public_code,w.recipient_name,w.currency,w.timezone,w.receiver_hash,
 w.profile_status,w.profile_version,w.profile_json,c.id AS credential_id,c.token_sha256,c.pairing_id,c.installation_id,
 p.code_sha256 AS pairing_code_sha256,p.originating_session_id,
 d.id AS grant_id,CAST(d.version AS text) AS grant_version,d.token_hash AS grant_token_hash,d.custodian_account_id,
 CAST(a.version AS text) AS account_version,CAST(a.credential_version AS text) AS credential_version,a.phone,CAST(a.capabilities AS text) AS capabilities
 FROM private.burimunsi_scopes scope
 JOIN app.momo_gateway_bindings b ON b.id=scope.active_binding_id AND b.receiving_account_id=scope.receiving_account_id AND b.version=scope.binding_version
 JOIN app.momo_receiving_accounts w ON w.id=b.receiving_account_id
 JOIN app.momo_gateway_credentials c ON c.binding_id=b.id
 JOIN app.momo_gateway_pairings p ON p.id=c.pairing_id AND p.binding_id=b.id AND p.claimed_installation_id=c.installation_id
 JOIN private.burimunsi_device_grants d ON d.collection_id=scope.collection_id AND CAST(d.installation_id AS text)=c.installation_id
 JOIN private.burimunsi_accounts a ON a.id=d.custodian_account_id AND a.collection_id=d.collection_id AND a.principal_user_id=b.owner_user_id
 JOIN private.burimunsi_device_accounts da ON da.grant_id=d.id AND da.account_id=a.id AND da.collection_id=d.collection_id
 JOIN app.users u ON u.id=b.owner_user_id
 WHERE c.id=? AND c.token_sha256=? AND scope.collection_id=? AND scope.enabled AND c.revoked_at IS NULL
 AND b.status='active' AND w.status='active' AND u.access_status='active'
 AND d.active AND d.profile='internal_receiver' AND a.active AND NOT a.removed AND a.role='admin'
 AND EXISTS(SELECT 1 FROM app.admin_principal_links l JOIN app.admin_users owner ON owner.id=l.admin_user_id
  WHERE l.user_id=b.owner_user_id AND owner.status='active')
 AND private.burimunsi_operator_is_current(a.collection_id,a.principal_user_id,a.phone,a.role,a.capabilities)
 AND (SELECT count(*) FROM app.momo_gateway_bindings active WHERE active.receiving_account_id=w.id AND active.status='active')=1
 LIMIT 2`;
export const GATEWAY_UPLOAD_MATCH_SQL=`EXISTS(SELECT 1 FROM (${GATEWAY_UPLOAD_AUTHORITY_SQL}) current_upload
 WHERE ${fields.map(field=>`current_upload.${field} IS NOT DISTINCT FROM ?`).join(' AND ')})`;
export const GATEWAY_UPLOAD_SOURCE_SQL=`EXISTS(SELECT 1 FROM private.burimunsi_sms_source_scopes source
 JOIN app.momo_gateway_captures capture ON capture.raw_sms_id=source.source_id AND capture.credential_id=source.credential_id
 WHERE source.collection_id=? AND source.source_id=? AND source.owner_user_id=? AND source.receiving_account_id=?
 AND source.credential_id=? AND source.binding_id=? AND source.binding_version=? AND CAST(source.installation_id AS text)=?
 AND source.source_body_sha256=? AND source.object_sha256=? AND CAST(source.custodian_account_id AS text)=?
 AND CAST(source.grant_id AS text)=? AND source.grant_version=? AND source.provenance='gateway_capture' AND source.proof_id=source.source_id
 AND capture.subscription_id=? AND ((capture.completeness='complete' AND capture.source_mode='live')
  OR (capture.completeness='incomplete' AND capture.source_mode='catch_up')) AND capture.identity_sha256=?)`;
export const GATEWAY_UPLOAD_READ_SQL=`SELECT r.*,g.identity_sha256 FROM app.sms_receipts r
 JOIN app.momo_gateway_captures g ON g.raw_sms_id=r.id WHERE r.owner_user_id=? AND r.client_envelope_id=? LIMIT 2`;
export const GATEWAY_UPLOAD_GROUP_SQL="SELECT set_config('burimunsi.collection_id',?,true)";

function current(env,plan){
 const p=plans.get(plan);need(p&&p.env===env);
 need(nativeGatewayUploadsEnabled(env)&&env.DB===p.db&&p.db.applicationWork===p.work&&env.COLLECT_FENCE_WORK===p.envWork&&
  env.BURIMUNSI_COLLECTION_ID===p.configuredGroup&&env.BUILD_SOURCE_ID===p.source&&
  env.COLLECT_DEPLOYMENT_PROFILE===p.profile&&env.PRIVATE_MEDIA===p.media,denied);
 return p;
}
async function owned(env,plan){const p=current(env,plan);try{await p.work.assert();}catch{throw unavailable();}current(env,plan);return p;}
const matchValues=p=>[p.row.credential_id,p.row.token_sha256,p.group,...fields.map(field=>p.row[field])];
function sourceValues(p,source){
 need(source&&typeof source.id==='string'&&/^[a-f0-9]{64}$/.test(source.body_sha256??'')&&/^[a-f0-9]{64}$/.test(source.object_sha256??'')&&/^[a-f0-9]{64}$/.test(source.identity_sha256??''));
 const r=p.row;
 return [p.group,source.id,r.owner_user_id,r.receiving_account_id,r.credential_id,r.binding_id,r.binding_version,r.installation_id,
  source.body_sha256,source.object_sha256,r.custodian_account_id,r.grant_id,r.grant_version,p.binding.subscriptionId,source.identity_sha256];
}
function guard(p,source=null){
 const condition=GATEWAY_UPLOAD_MATCH_SQL+(source?' AND '+GATEWAY_UPLOAD_SOURCE_SQL:'');
 const values=[...matchValues(p),...(source?sourceValues(p,source):[])],key=crypto.randomUUID();
 return [p.db.prepare(`INSERT INTO app.momo_processing_guards(id,passed) SELECT ?,CASE WHEN ${condition} THEN 1 ELSE 0 END`).bind(key,...values),
  p.db.prepare('DELETE FROM app.momo_processing_guards WHERE id=?').bind(key)];
}

/** Opaque, invocation-local plan. This preflight precedes source-body reads and
 * media I/O. The ordinary DB.batch establishes the existing global mutation
 * lock, collect_runtime role and genuine application-work lease. */
export async function prepareNativeGatewayUpload(env,credential){
 if(!nativeGatewayUploadsEnabled(env))throw gatewayUploadHeld();
 const db=env?.DB,work=db?.applicationWork;
 need(db&&['prepare','batch','statement','transaction','context','readContext'].every(k=>typeof db[k]==='function')&&typeof work?.assert==='function');
 need(env.COLLECT_FENCE_WORK===work&&env.PRIVATE_MEDIA&&typeof env.PRIVATE_MEDIA.put==='function'&&typeof env.PRIVATE_MEDIA.get==='function');
 need(credential&&/^[a-f0-9]{64}$/.test(credential.pairing_code_sha256??'')&&/^[a-f0-9]{64}$/.test(credential.token_sha256??''));
 const plan=Object.freeze({}),p={env,db,work,envWork:env.COLLECT_FENCE_WORK,media:env.PRIVATE_MEDIA,
  configuredGroup:env.BURIMUNSI_COLLECTION_ID,source:env.BUILD_SOURCE_ID,profile:env.COLLECT_DEPLOYMENT_PROFILE};plans.set(plan,p);
 await owned(env,plan);
 let target;try{target=await classifyGatewayPair({env,codeHash:credential.pairing_code_sha256});}
 catch(error){if(error?.status===401||error?.status===403)throw denied();throw unavailable();}
 if(target.kind!=='burimunsi')throw gatewayUploadHeld();p.group=target.collectionId;
 let result;try{result=await db.batch([db.prepare(GATEWAY_UPLOAD_GROUP_SQL).bind(p.group),
  db.prepare(GATEWAY_UPLOAD_AUTHORITY_SQL).bind(credential.id,credential.token_sha256,p.group)]);}catch{await owned(env,plan);throw unavailable();}
 await owned(env,plan);
 const rows=result?.[1]?.results;need(result?.length===2&&result[0]?.success===true&&result[1]?.success===true&&Array.isArray(rows)&&rows.length===1,denied);
 const row=rows[0];need(Object.keys(row).length===fields.length&&fields.every(field=>Object.hasOwn(row,field))&&row.collection_id===p.group&&
  row.credential_id===credential.id&&row.token_sha256===credential.token_sha256&&row.binding_id===credential.binding_id&&
  row.installation_id===credential.installation_id&&row.owner_user_id===credential.owner_user_id&&row.pairing_code_sha256===credential.pairing_code_sha256,denied);
 for(const field of ['scope_version','binding_version','grant_version','account_version','credential_version'])positive(row[field]);
 need(/^[a-f0-9]{64}$/.test(row.receiver_hash??'')&&typeof row.binding_created_at==='string'&&row.binding_created_at.length<=40&&Number.isFinite(Date.parse(row.binding_created_at)));
 need(typeof row.profile_json==='string'&&row.profile_json.length<=65536);
 const profile=validateProviderProfile({...row,status:'active'});
 // Intake is profile-driven; supported date grammars are validated by the
 // downstream extraction pipeline, not guessed by this capture boundary.
 need(profile&&['mtn_momo','airtel_money'].includes(row.provider),denied);
 let evidence;try{evidence=JSON.parse(row.subscription_evidence);}catch{throw denied();}
 need(Number.isInteger(evidence?.subscription_id)&&evidence.subscription_id>=0&&evidence.subscription_id<=2147483647,denied);
 p.row=Object.freeze({...row});p.authority=new PostgresNativeAuthority({db,groupId:p.group});
 p.binding=Object.freeze({active:true,installationId:row.installation_id,version:positive(row.binding_version),subscriptionId:evidence.subscription_id});
 p.receiptProfile=Object.freeze({version:row.profile_version,offsetMinutes:profile.utc_offset_minutes,
  senders:Object.freeze([...profile.sender_allowlist]),incomingPrefixes:Object.freeze([...profile.incoming_prefixes]),
  currencyAliases:Object.freeze([...profile.currency_aliases]),transactionIdPrefixes:Object.freeze([...profile.transaction_id_prefixes])});
 await owned(env,plan);return plan;
}

export async function nativeGatewayUploadContext(env,plan){
 const p=await owned(env,plan);need(p.row&&p.binding&&p.receiptProfile);
 return Object.freeze({credential:p.row,binding:p.binding,profile:p.receiptProfile,collectionId:p.group});
}

/** Only the currently authorized receiver may obtain the approved local
 * classifier inputs. The second scoped read detects a changed grant, binding,
 * account or profile before returning the projection. No SMS body or secret is
 * included. An expiring snapshot bounds use while the phone is offline. */
export async function readNativeGatewayProfile(env,plan){
 const p=await owned(env,plan);need(p.row&&p.binding&&p.receiptProfile);
 const result=await p.authority.read(async tx=>{
  await owned(env,plan);
  const admission=await p.db.statement(tx,p.db.prepare('SELECT '+GATEWAY_UPLOAD_MATCH_SQL+' AS admitted').bind(...matchValues(p)));
  need(admission?.success===true&&admission.results?.length===1&&admission.results[0].admitted===true,denied);
  const now=Date.now();need(Number.isSafeInteger(now)&&now>0);
  const profile=p.receiptProfile;
  need(typeof profile.version==='string'&&profile.version.length<=80&&profile.version.trim()===profile.version&&
   profile.version.length>0&&!/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(profile.version));
  await owned(env,plan);
  return Object.freeze({contractVersion:1,collectionId:p.group,installationId:p.binding.installationId,
   bindingId:p.row.binding_id,bindingVersion:p.binding.version,receivingAccountId:p.row.receiving_account_id,
   profileVersion:profile.version,offsetMinutes:profile.offsetMinutes,senders:[...profile.senders],
   incomingPrefixes:[...profile.incomingPrefixes],currencyAliases:[...profile.currencyAliases],transactionIdPrefixes:[...profile.transactionIdPrefixes],
   issuedAt:now,expiresAt:now+24*60*60*1000});
 });
 await owned(env,plan);return result;
}
export async function assertNativeGatewayCapture(env,plan,source){
 const p=await owned(env,plan);
 // Inbox rows are retained as incomplete observations only. The timestamp and
 // exact SIM must belong to the current binding; no PDU completeness is claimed.
 const live=source?.sourceMode==='live'&&source.complete===true;
 const inbox=source?.sourceMode==='catch_up'&&source.complete===false&&
  typeof source.inboxReceivedAt==='string'&&Number.isFinite(Date.parse(source.inboxReceivedAt))&&
  Number.isFinite(Date.parse(p.row.binding_created_at))&&Date.parse(source.inboxReceivedAt)>=Date.parse(p.row.binding_created_at);
 if(!live&&!inbox)throw new ApiError(422,'gateway_message_not_supported','The incoming receipt source could not be verified.');
 const result=classifyCapture(source,p.receiptProfile,p.binding,{allowIncompleteInbox:inbox});
 if(!result.retain)throw new ApiError(422,'gateway_message_not_supported','This incoming receipt format is not supported.');
 await owned(env,plan);
}

/** Both gates are in the SAME capture transaction. Missing trigger association,
 * revoked custody, changed versions, SIM/profile changes or a flag/lease change
 * cannot produce a durable ACK. A caller cannot manufacture a WeakMap plan. */
export async function commitNativeGatewayCapture(env,plan,statements,source){
 const p=await owned(env,plan);need(Array.isArray(statements));
 const before=guard(p),after=guard(p,source);
 let result;try{result=await p.db.batch([p.db.prepare(GATEWAY_UPLOAD_GROUP_SQL).bind(p.group),
  before[0],...statements,after[0],after[1],before[1]]);
  need(Array.isArray(result)&&result.length===statements.length+5&&result.every(row=>row?.success===true));
 }catch{await owned(env,plan);throw unavailable();}
 await owned(env,plan);return result;
}

/** Read-only reconciliation never retries the original INSERT/COMMIT. Proof is
 * checked before retained media is read, then checked again by the ACK batch. */
export async function readNativeGatewayCapture(env,plan,envelope){
 const p=await owned(env,plan);
 let row;try{row=await p.authority.read(async tx=>{
  await owned(env,plan);
  const result=await p.db.statement(tx,p.db.prepare(GATEWAY_UPLOAD_READ_SQL).bind(p.row.owner_user_id,envelope));
  need(result?.success===true&&Array.isArray(result.results)&&result.results.length<=1);
  if(!result.results.length)return null;
  const admission=await p.db.statement(tx,p.db.prepare('SELECT '+GATEWAY_UPLOAD_MATCH_SQL+' AS admitted').bind(...matchValues(p)));
  need(admission?.success===true&&admission.results?.length===1&&admission.results[0].admitted===true,denied);
  const retained=result.results[0],proof=await p.db.statement(tx,p.db.prepare('SELECT '+GATEWAY_UPLOAD_SOURCE_SQL+' AS associated').bind(...sourceValues(p,retained)));
  need(proof?.success===true&&proof.results?.length===1&&proof.results[0].associated===true,denied);
  await owned(env,plan);return retained;
 });}catch(error){await owned(env,plan);if(error instanceof ApiError)throw error;throw unavailable();}
 await owned(env,plan);return row;
}
