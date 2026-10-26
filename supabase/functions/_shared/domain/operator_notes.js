import {ApiError,uuid,text,id,now,digest,requirePermission} from './core.js';
import {encrypt,decrypt} from './encryption.js';
import {mutation} from './mutations.js';

const types={collection:{table:'collections',permission:'collections.read'},profile:{table:'users',permission:'users.read'}};
const scope=type=>{
 const value=Object.hasOwn(types,type)?types[type]:null;
 if(!value)throw new ApiError(400,'invalid_entity','Choose a group or profile for this note.');
 return value;
};
export const operatorNotePermission=type=>scope(type).permission;
const context=row=>`admin-operator-note:${row.id}:${row.entity_type}:${row.entity_id}`;

// Only the receipt and non-content audit metadata are retained in plaintext.
// Both callers use the same canonical mutation/session authority boundary.
export async function recordOperatorNote(env,actor,{entityType,entityId,body,requestId,requestBody,operation='admin_record_operator_note',receipt}){
 const {table,permission}=scope(entityType);requirePermission(actor,permission);
 const target=uuid(entityId,'entity_id'),rid=uuid(requestId,'request_id'),content=text(body,'note',2000),noteId=id();
 const row={id:noteId,entity_type:entityType,entity_id:target};
 const ciphertext=await encrypt(env,new TextEncoder().encode(content),context(row));
 const hash=await digest(content),timestamp=now();
 // The trigger checks that the target still exists in the committing batch.
 // The SELECT here provides an actionable 404 before encryption is persisted.
 const [targetResult]=await env.DB.batch([env.DB.prepare(`SELECT id FROM ${table} WHERE id=?`).bind(target)]);
 if(!targetResult.results.length)throw new ApiError(404,'not_found','This record was not found.');
 const response=receipt?receipt(noteId):{ok:true,note_id:noteId};
 return mutation(env,actor,operation,rid,requestBody,response,[env.DB.prepare(`INSERT INTO admin_operator_notes
  (id,entity_type,entity_id,body_ciphertext,body_sha256,created_by,session_id,created_at) VALUES(?,?,?,?,?,?,?,?)`)
  .bind(noteId,entityType,target,ciphertext,hash,actor.userId,actor.sessionId,timestamp)],
  {permission,entityType,entityId:target,auditDetails:{note_id:noteId,body_sha256:hash}});
}

export async function listOperatorNotes(env,actor,entityType,entityId,{limit=25,offset=0}={}){
 const {table,permission}=scope(entityType);requirePermission(actor,permission);const target=uuid(entityId,'entity_id');
 const [targetResult,count,result]=await env.DB.batch([
  env.DB.prepare(`SELECT id FROM ${table} WHERE id=?`).bind(target),
  env.DB.prepare('SELECT count(*) AS total FROM admin_operator_notes WHERE entity_type=? AND entity_id=?').bind(entityType,target),
  env.DB.prepare(`SELECT n.*,u.full_name AS author_name FROM admin_operator_notes n JOIN users u ON u.id=n.created_by
   WHERE n.entity_type=? AND n.entity_id=? ORDER BY n.created_at DESC,n.id DESC LIMIT ? OFFSET ?`).bind(entityType,target,limit,offset),
 ]);
 if(!targetResult.results.length)throw new ApiError(404,'not_found','This record was not found.');
 const notes=[];
 for(const row of result.results){
  let raw;try{raw=await decrypt(env,row.body_ciphertext,context(row));}
  catch{throw new ApiError(503,'note_unavailable','A note could not be verified.');}
  if(await digest(raw)!==row.body_sha256)throw new ApiError(503,'note_unavailable','A note could not be verified.');
  notes.push({id:row.id,body:new TextDecoder('utf-8',{fatal:true}).decode(raw),created_by:row.created_by,author_name:row.author_name||'Team member',created_at:row.created_at});
 }
 return {contract_version:1,entity_type:entityType,entity_id:target,rows:notes,total:count.results[0].total,limit,offset};
}

export async function operatorNoteRpc(operation,body,env,actor){
 if(operation!=='admin_record_operator_note')return {handled:false};
 if(Object.keys(body).some(k=>!['p_entity_type','p_entity_id','p_body','p_request_id'].includes(k)))throw new ApiError(400,'invalid_request','Request has unsupported fields.');
 return {handled:true,value:await recordOperatorNote(env,actor,{entityType:body.p_entity_type,entityId:body.p_entity_id,body:body.p_body,requestId:body.p_request_id,requestBody:body})};
}
