import {json,readJson,uuid,text,integer} from './core.js';
import {permission,lists,list,filters,operatingDetail,iso,fail,unavailable} from './admin_records.js';
import {adminAccountSession,adminCanonicalActor,adminInternalRequest,accountDatabase,accountReadDatabase} from './admin_accounts.js';
import {recordOperatorNote,listOperatorNotes,operatorNotePermission} from './operator_notes.js';
import {evidenceRoute,compensationRpc} from './evidence.js';
import {keys,optionalText} from './admin_operation_fields.js';
import {receipt,requestId,requestEnvironment} from './admin_request_aliases.js';
import {adminRequestHistory,cancelOriginalRequest} from './admin_request_history.js';
import {genericMutation} from './admin_record_mutations.js';

export async function operatingRead(request,env,account,parts,url){
 if(parts.length===3&&parts[2]==='notes'&&['groups','users'].includes(parts[0])){
  const entityType=parts[0]==='groups'?'collection':'profile',cap=operatorNotePermission(entityType),f=filters(url,['limit','offset']);
  const scoped=accountDatabase(env,account,cap),actor=await adminCanonicalActor(request,scoped,account,cap);
  const result=await listOperatorNotes(scoped,actor,entityType,parts[1],f);
  // Decryption can await key work: recheck authority before releasing content.
  const latest=await adminAccountSession(request,env);if(!latest.permissions.includes(cap))fail(403,'permission_required','These notes are unavailable.');
  return result;
 }
 if(parts[0]==='requests')return adminRequestHistory(env,account,parts,url);
 if(parts[0]==='lookups'){
  const kind=url.searchParams.get('kind');if(!lists[kind])unavailable();if(!account.permissions.includes(`${permission[kind]}.read`))fail(403,'permission_required','This lookup is unavailable.');
  const projection=new URL(url);projection.searchParams.delete('kind');const groupId=projection.searchParams.get('group_id');projection.searchParams.delete('group_id');
  if(groupId&&kind!=='members'&&kind!=='payees')fail(400,'invalid_filter','This lookup filter is unavailable.');
  if((kind==='members'||kind==='payees')&&!groupId)fail(400,'invalid_filter','Choose a group before choosing its records.');
  const scoped=accountReadDatabase(env,account,`${permission[kind]}.read`);
  const result=await list(scoped,kind,projection,{activeOnly:true,eligiblePeople:kind==='users'||kind==='members',groupId});
  return {...result,kind,group_id:groupId??null,rows:result.rows.map(r=>({...r,label:r.display_name||r.title,name:r.display_name||r.title}))};
 }
 if(parts.length!==2||!lists[parts[0]])unavailable();const type=parts[0];if(!account.permissions.includes(`${permission[type]}.read`))fail(403,'permission_required','This view is unavailable.');
 return operatingDetail(accountDatabase(env,account,`${permission[type]}.read`),account,type,uuid(parts[1]),url);
}

export async function adminOperationWrite(request,env,base,account,actor,parts,url){
  if(parts.length===3&&parts[2]==='notes'&&request.method!=='POST')fail(405,'method_not_allowed','Support notes must be recorded with POST.');
  if(url.search)fail(400,'invalid_request','This action does not accept filters.');const data=await readJson(request,2097152),key=request.headers.get('Idempotency-Key'),rid=await requestId(account,key),source={method:request.method,path:url.pathname,body:data};
  if(parts.length===3&&parts[0]==='requests'&&parts[2]==='cancel'&&request.method==='POST')return json(await cancelOriginalRequest(base,account,actor,parts[1],data,rid,source));
  const scoped=requestEnvironment(base,account,key,rid,`operations.${parts.join('.')}.${request.method}`,source);
  if(parts.length===3&&parts[2]==='notes'&&['groups','users'].includes(parts[0])&&request.method==='POST'){
   keys(data,['body']);const entityType=parts[0]==='groups'?'collection':'profile',cap=operatorNotePermission(entityType);
   const noteEnv=requestEnvironment(accountDatabase(env,account,cap),account,key,rid,`operations.${parts.join('.')}.POST`,source);
   return json(await recordOperatorNote(noteEnv,actor,{entityType,entityId:parts[1],body:data.body,requestId:rid,requestBody:source,
    operation:'admin.operator_note.recorded',receipt:noteId=>receipt(rid,'operator_notes',noteId,1)}));
  }
  if(parts[0]==='transactions'&&request.method==='POST'&&parts.length===1){
   keys(data,['group_id','payee_id','network','provider_reference','amount_rwf','observed_at','evidence','payer_name','verification_status','reason']);
   if(data.verification_status&&data.verification_status!=='pending')unavailable();text(data.reason??request.headers.get('X-Collect-Review-Reason'),'reason',500);
   if(typeof data.evidence!=='string')unavailable();const groupId=uuid(data.group_id),amount=integer(data.amount_rwf,'amount_rwf',1);
   if(data.payee_id&&uuid(data.payee_id)!==groupId)fail(400,'invalid_receiver','Select this group recorded receiver.');
   if(data.observed_at===undefined)fail(400,'observed_at_required','Record when this evidence was observed.');
   const value={collection_id:groupId,amount_minor:amount,external_reference:optionalText(data.provider_reference,'reference',200),observed_at:iso(data.observed_at),
    evidence:data.evidence,payer_display_name:data.payer_name??'',reason:text(data.reason,'reason',500),request_id:rid,admin_bridge_request:source};
   const reply=await evidenceRoute(await adminInternalRequest(request,scoped,account,'/v1/evidence','POST',value),scoped,actor);if(!reply)unavailable();
   const result=await reply.json();await adminAccountSession(request,env);return json(receipt(rid,'transactions',result.id,1));
  }
  if(parts[0]==='transactions'&&parts[2]==='reverse'&&request.method==='POST'){
   const result=await compensationRpc('admin_reverse_payment_v1',{p_payment_id:uuid(parts[1]),p_expected_revision:integer(data.expected_version,'expected_version',1),p_request_id:rid,p_reason:text(data.reason,'reason',500),admin_bridge_request:source},scoped,actor);
   return json(receipt(rid,'transactions',result.value.payment_id,result.value.revision));
  }
  return json(await genericMutation(request,scoped,account,actor,parts,data,rid,source));
}
