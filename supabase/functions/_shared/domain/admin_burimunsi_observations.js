// Candidate-only managed Admin view. The SQL it requires is an unregistered
// draft; setting the flag is insufficient until that draft is qualified.
import {ApiError,json,uuid,text,digest,id,now,requirePermission} from './core.js';
import {accountDatabase,adminAccountSession,adminCanonicalActor} from './admin_accounts.js';
import {assertMutationAdmission} from './mutations.js';
import {decrypt} from './encryption.js';
import {ScopedCursor} from './burimunsi/cursor.js';
import {canonicalJson} from './burimunsi/values.js';
import {observationDisplayHints} from './burimunsi/observation-display-hints.js';

const HASH=/^[a-f0-9]{64}$/;
const ID=/^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
const GROUP=/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/;
const KEY=/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/;
const CONTROL=/[\u0000-\u001f\u007f\u202a-\u202e\u2066-\u2069]/;
const BODY_CONTROL=/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f\u202a-\u202e\u2066-\u2069]/;
const DISPLAY_CONTROL=/[\u0000-\u001f\u007f-\u009f\u202a-\u202e\u2066-\u2069]/;
export const managedAdminObservationsEnabled=env=>env?.BURIMUNSI_ADMIN_SMS_OBSERVATIONS_ENABLED==='true';
const bytes=new TextEncoder();
const fail=(status,code,message)=>{throw new ApiError(status,code,message);};
const bad=()=>fail(503,'observation_unavailable','Observation metadata could not be verified.');
const invalid=()=>fail(400,'invalid_filter','Choose a valid observation filter.');
const missing=()=>fail(404,'not_found','This observation is unavailable.');
const isObject=v=>v!==null&&typeof v==='object'&&!Array.isArray(v);
const num=(v,min,max)=>{if(typeof v!=='number'&&!(typeof v==='string'&&/^(0|[1-9][0-9]*)$/.test(v)))bad();const n=Number(v);if(!Number.isSafeInteger(n)||n<min||n>max)bad();return n;};
const stamp=v=>{const n=num(v,0,253402300799999);try{return new Date(n).toISOString();}catch{bad();}};
function filters(url,allowed){for(const key of url.searchParams.keys())if(!allowed.includes(key)||url.searchParams.getAll(key).length!==1)invalid();}
function group(value){if(typeof value!=='string'||!GROUP.test(value))invalid();return value;}
function requestCursorKey(env){
 const value=env.BURIMUNSI_CURSOR_KEY_BASE64;
 if(typeof value!=='string'||value.length!==44||!/^[A-Za-z0-9+/]{43}=$/.test(value))bad();
 let decoded;try{decoded=Uint8Array.from(atob(value),c=>c.charCodeAt(0));}catch{bad();}
 if(decoded.length!==32||btoa(String.fromCharCode(...decoded))!==value)bad();
 return new ScopedCursor(decoded);
}
async function select(scoped,sql,...args){
 const [answer]=await scoped.DB.batch([scoped.DB.prepare(sql).bind(...args)]);
 if(!answer||!Array.isArray(answer.results)||answer.results.length!==1||!Object.hasOwn(answer.results[0],'result'))bad();
 return answer.results[0].result;
}
async function reservationMatches(row){
 if(!row||!ID.test(row.sourceId??'')||typeof row.ownerUserId!=='string'||!row.ownerUserId||row.ownerUserId.length>128||
  row.objectKey!=='sms/'+row.sourceId||!HASH.test(row.objectSha256??'')||!HASH.test(row.fingerprint??'')||
  !KEY.test(row.keyId??'')||!HASH.test(row.sourceFingerprint??''))return false;
 const descriptor={scope:{ownerId:row.ownerUserId,purpose:'sms_receipt',entityId:row.sourceId},
  aad:`sms:${row.sourceId}:${row.objectSha256}`,keyId:row.keyId,plaintextSha256:row.objectSha256,
  requestDigest:row.fingerprint,httpMetadata:{contentType:'application/octet-stream'},
  customMetadata:{sha256:row.objectSha256,key_id:row.keyId}};
 return await digest(canonicalJson(descriptor))===row.sourceFingerprint;
}
async function collections(env,account,url){
 filters(url,[]);const scoped=accountDatabase(env,account,'sms.read');
 const result=await select(scoped,'SELECT private.burimunsi_observation_admin_collections() AS result');
 if(!Array.isArray(result)||result.length>500)bad();
 const ids=new Set(),items=result.map(v=>{
  if(!isObject(v)||Object.keys(v).length!==2||!GROUP.test(v.collectionId??'')||ids.has(v.collectionId)||
    typeof v.label!=='string'||!v.label.trim()||v.label.length>200||DISPLAY_CONTROL.test(v.label))bad();
  ids.add(v.collectionId);return {collectionId:v.collectionId,label:v.label};
 });
 return json({contractVersion:1,items,asOf:now()});
}
async function page(env,account,actor,url){
 filters(url,['collectionId','limit','cursor']);const collectionId=group(url.searchParams.get('collectionId'));
 const rawLimit=url.searchParams.get('limit')??'25';if(!/^(?:[1-9][0-9]?|100)$/.test(rawLimit))invalid();
 const limit=Number(rawLimit),token=url.searchParams.get('cursor');if(token!==null&&(!token||token.length>2048))invalid();
 const scoped=accountDatabase(env,account,'sms.read'),cursor=requestCursorKey(env);
 const get=offset=>select(scoped,'SELECT private.burimunsi_observation_admin_page(?,?,?) AS result',collectionId,limit,offset);
 const first=await get(0);if(!isObject(first)||first.collectionId!==collectionId||!HASH.test(first.revision??''))bad();
 const filterHash=await digest(canonicalJson({kind:'managed_admin_observation_v1',collectionId,limit,sessionId:actor.sessionId}));
 const scope={groupId:collectionId,actorId:actor.userId,snapshot:first.revision,filterHash,sort:'newest'};
 let after=null;
 if(token!==null){try{after=await cursor.read(token,scope,Date.now());}catch(error){
  if(error?.code==='cursor_scope_changed'||error?.code==='cursor_expired')fail(409,'cursor_changed','The observation list changed. Refresh and try again.');
  invalid();}}
 if(after!==null&&(!isObject(after)||Object.keys(after).length!==1||!Number.isSafeInteger(after.offset)||after.offset<1||after.offset>100000))invalid();
 const offset=after?.offset??0,result=offset===0?first:await get(offset);
 if(!isObject(result)||result.collectionId!==collectionId||result.revision!==scope.snapshot||!Array.isArray(result.items))
  fail(409,'cursor_changed','The observation list changed. Refresh and try again.');
 const total=num(result.totalCount,0,100000);if(result.items.length!==Math.max(0,Math.min(limit,total-offset)))bad();
 const seen=new Set(),items=[];
 for(const v of result.items){
  if(!isObject(v)||!ID.test(v.requestId??'')||!ID.test(v.sourceId??'')||seen.has(v.sourceId)||
    !['retained','unresolved'].includes(v.retentionState))bad();
  seen.add(v.sourceId);const at=stamp(v.admittedAt);
  const retained=v.retentionState==='retained'&&HASH.test(v.bodySha256??'')&&await reservationMatches(v);
  if(v.retentionState==='unresolved'&&v.bodySha256!==null)bad();
  items.push({requestId:v.requestId,sourceId:v.sourceId,admittedAt:at,
   retentionState:retained?'retained':'unresolved',bodySha256:retained?v.bodySha256:null});
 }
 const t=Date.now();if(!Number.isSafeInteger(t)||t<=0)bad();
 const nextCursor=offset+items.length<total?await cursor.create({...scope,after:{offset:offset+items.length},expiresAt:t+15*60*1000}):null;
 if(nextCursor!==null&&nextCursor.length>2048)bad();
 return json({contractVersion:1,collectionId,items,nextCursor,asOf:new Date(t).toISOString()});
}
async function content(request,env,account,actor,parts,url){
 filters(url,['collectionId','displayHintsVersion']);const collectionId=group(url.searchParams.get('collectionId'));
 const requested=url.searchParams.get('displayHintsVersion');if(requested!==null&&requested!=='1')invalid();
 const wantHints=requested==='1',hintsEnabled=wantHints&&env.BURIMUNSI_OBSERVATION_HINTS_ENABLED==='true';
 const sourceId=uuid(parts[1],'source_id');if(sourceId!==parts[1])invalid();
 requirePermission(actor,'sms.reveal');
 const reason=text(request.headers.get('X-Collect-Review-Reason'),'review reason',1000);
 if(reason.length<8||DISPLAY_CONTROL.test(reason))fail(400,'reason_required','Record a review reason of 8 to 1000 characters.');
 const scoped=accountDatabase(accountDatabase(env,account,'sms.read',{mfa:true,fresh:true}),account,'sms.reveal',{mfa:true,fresh:true});
 const source=await select(scoped,'SELECT private.burimunsi_observation_admin_source(?,?) AS result',collectionId,sourceId);
 if(source===null)missing();
 const initialHintProfile=hintsEnabled?await select(scoped,'SELECT private.burimunsi_observation_admin_hint_profile(?,?) AS result',collectionId,sourceId):null;
 if(!isObject(source)||source.collectionId!==collectionId||source.sourceId!==sourceId||!ID.test(source.requestId??'')||
  !HASH.test(source.bodySha256??'')||!HASH.test(source.cipherSha256??'')||!HASH.test(source.storageFingerprint??'')||
  typeof source.storageOperationId!=='string'||!source.storageOperationId||!await reservationMatches(source))bad();
 const plaintextSize=num(source.sizeBytes,1,131072),cipherSize=num(source.cipherSize,1,262144);
 const object=await scoped.PRIVATE_MEDIA?.get(source.objectKey);
 if(!object)fail(503,'source_unavailable','Retained SMS storage is unavailable.');
 if(object.key!==source.objectKey||object.size!==cipherSize||object.sha256!==source.cipherSha256||
  object.customMetadata?.sha256!==source.objectSha256||object.customMetadata?.key_id!==source.keyId||
  object.customMetadata?.source_fingerprint!==source.sourceFingerprint)bad();
 let payload,plain;
 try{
  plain=await decrypt(scoped,await object.text(),`sms:${sourceId}:${source.objectSha256}`);
  if(plain.length!==plaintextSize||await digest(plain)!==source.objectSha256)bad();
  payload=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(plain));
  if(!isObject(payload)||payload.provenance!=='native_observation_unverified'||typeof payload.raw_sender!=='string'||
   !payload.raw_sender.trim()||payload.raw_sender.length>96||DISPLAY_CONTROL.test(payload.raw_sender)||typeof payload.raw_body!=='string'||
   !payload.raw_body||bytes.encode(payload.raw_body).length>3000||BODY_CONTROL.test(payload.raw_body)||await digest(payload.raw_body)!==source.bodySha256)bad();
 }catch{bad();}finally{plain?.fill(0);}
 // Refresh the same managed session and actor after retrieval, then re-run the
 // scope/source/storage proof in the same transaction as the audit insert.
 const latest=await adminAccountSession(request,env);
 if(['id','principal_id','auth_session_id','token_hash','public_id','auth_version','role'].some(k=>latest[k]!==account[k]))
  fail(403,'admin_access_changed','Original SMS access changed.');
 const current=await adminCanonicalActor(request,env,latest);
 if(current.userId!==actor.userId||current.sessionId!==actor.sessionId||!current.permissions.has('sms.read')||!current.permissions.has('sms.reveal'))
  fail(403,'permission_required','Original SMS access changed.');
 const admitted=accountDatabase(accountDatabase(env,latest,'sms.read',{mfa:true,fresh:true}),latest,'sms.reveal',{mfa:true,fresh:true}),guardId=id();
 const currentHintProfile=hintsEnabled?await select(admitted,'SELECT private.burimunsi_observation_admin_hint_profile(?,?) AS result',collectionId,sourceId):null;
 const displayHints=hintsEnabled&&initialHintProfile&&currentHintProfile&&canonicalJson(initialHintProfile)===canonicalJson(currentHintProfile)
  ?await observationDisplayHints(payload,currentHintProfile,source.bodySha256):null;
 const sourceGuard=displayHints
  ?admitted.DB.prepare('INSERT INTO admin_bridge_guards(id,passed) SELECT ?,CASE WHEN private.burimunsi_observation_admin_source(?,?)=?::jsonb AND private.burimunsi_observation_admin_hint_profile(?,?)=?::jsonb THEN 1 ELSE 0 END').bind(guardId,collectionId,sourceId,source,collectionId,sourceId,currentHintProfile)
  :admitted.DB.prepare('INSERT INTO admin_bridge_guards(id,passed) SELECT ?,CASE WHEN private.burimunsi_observation_admin_source(?,?)=?::jsonb THEN 1 ELSE 0 END').bind(guardId,collectionId,sourceId,source);
 await assertMutationAdmission(admitted,current,[
  sourceGuard,
  admitted.DB.prepare("INSERT INTO audit_log(actor_user_id,actor_session_id,action,entity_type,entity_id,details_json,created_at) VALUES(?,?,'sms.observation.revealed','sms_observation',?,?,?)")
   .bind(current.userId,current.sessionId,sourceId,JSON.stringify({reason,collection_id:collectionId,request_id:source.requestId,body_sha256:source.bodySha256,object_sha256:source.objectSha256}),now()),
  admitted.DB.prepare('DELETE FROM admin_bridge_guards WHERE id=?').bind(guardId),
 ],{permission:'sms.reveal',minimumAssurance:2,freshSeconds:300});
 return json({contractVersion:1,collectionId,sourceId,sourceKind:'observation',retentionState:'retained',
  rawSender:payload.raw_sender,rawBody:payload.raw_body,bodySha256:source.bodySha256,...(wantHints?{displayHints}:{})});
}
export async function adminBuriMunsiObservationRoute(request,env,account,actor,parts,url){
 if(!managedAdminObservationsEnabled(env))fail(404,'not_found','This view is unavailable.');
 requirePermission(actor,'sms.read');
 if(request.method!=='GET')fail(405,'method_not_allowed','This view is read-only.');
 try{
  if(parts.length===2&&parts[1]==='collections')return await collections(env,account,url);
  if(parts.length===1)return await page(env,account,actor,url);
  if(parts.length===3&&parts[2]==='content')return await content(request,env,account,actor,parts,url);
  missing();
 }catch(error){
  if(error instanceof ApiError)throw error;
  if(error?.code==='42501')fail(403,'permission_required','Observation access is unavailable.');
  if(error?.code==='22023')invalid();
  if(error?.code==='54000')fail(503,'observation_limit','Observation metadata exceeds its safe limit.');
  throw error;
 }
}
