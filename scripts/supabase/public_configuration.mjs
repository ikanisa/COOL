// Private operator functions only: no HTTP/RPC, credentials, provider or CLI path.
// The caller owns verified project/TLS identity. verifySource must independently
// regenerate/compare these exact payload bytes and every qualified source pin;
// echoing the plan's hashes does not qualify a payload or its policy content.
import {createHash} from 'node:crypto';
import {catalogIdentity} from './data_promote.mjs';

export const publicConfigurationKeys=Object.freeze([
 'get_collection_type_catalog','get_public_runtime_config','list_account_request_reasons','policy:privacy','policy:terms',
]);
const PROJECT='rrlduytparvsjfmegalh';
const ACTION='operator.public_configuration.replace.v1';
const HASH=/^[a-f0-9]{64}$/;
const UUID=/^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
const MAX_BIGINT=9223372036854775807n;
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const byteOrder=(a,b)=>Buffer.compare(Buffer.from(a),Buffer.from(b));
const same=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
const object=value=>value!==null&&typeof value==='object'&&!Array.isArray(value)&&Object.getPrototypeOf(value)===Object.prototype;
const exactKeys=(value,keys)=>object(value)&&same(Object.keys(value).sort(),[...keys].sort());
const fail=(code,message)=>{const error=new Error(message);error.code=code;throw error;};
const freeze=value=>{if(value&&typeof value==='object'){Object.values(value).forEach(freeze);Object.freeze(value);}return value;};

// Object key order is immaterial to the plan digest; raw stored/payload JSON text
// remains a string and is never normalized. Bigint revisions remain decimal text.
function canonical(value){
 if(value===null||typeof value==='string'||typeof value==='boolean')return JSON.stringify(value);
 if(typeof value==='number'&&Number.isSafeInteger(value))return String(value);
 if(Array.isArray(value))return '['+value.map(canonical).join(',')+']';
 if(object(value))return '{'+Object.keys(value).sort().map(key=>JSON.stringify(key)+':'+canonical(value[key])).join(',')+'}';
 fail('INVALID_PLAN','Only plain serializable plan values are permitted');
}

function payloadText(bytes){
 if(typeof bytes!=='string'&&!Buffer.isBuffer(bytes)&&!(bytes instanceof Uint8Array))fail('INVALID_PAYLOAD','Exact UTF-8 payload bytes required');
 const raw=typeof bytes==='string'?Buffer.from(bytes):Buffer.from(bytes);
 if(!raw.length||raw.length>524288)fail('INVALID_PAYLOAD','Payload exceeds the preparation bound');
 const text=new TextDecoder('utf-8',{fatal:true}).decode(raw);
 if(!Buffer.from(text).equals(raw)||/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(text))fail('INVALID_PAYLOAD','Invalid UTF-8 payload');
 return text;
}

function parsePayload(text,expectedHash,apiSourceId){
 if(!HASH.test(expectedHash)||sha(text)!==expectedHash||!HASH.test(apiSourceId))fail('INVALID_PAYLOAD','Qualified payload/source digest differs');
 const payload=JSON.parse(text);
 if(!exactKeys(payload,['schema_version','kind','api_source_id','legal_release_approved','provider_approved','retention_policy_activation','source_inputs','records'])||
  payload.schema_version!==1||payload.kind!=='collect_public_configuration_seed'||payload.api_source_id!==apiSourceId||
  ['legal_release_approved','provider_approved','retention_policy_activation'].some(key=>payload[key]!==false)||!object(payload.source_inputs)||!Object.keys(payload.source_inputs).length)
  fail('INVALID_PAYLOAD','Unexpected public configuration payload or approval state');
 for(const [path,pin] of Object.entries(payload.source_inputs)){
  if(!/^[a-zA-Z0-9_. /-]+$/.test(path)||path.startsWith('/')||path.split('/').some(part=>!part||part==='.'||part==='..')||
   !exactKeys(pin,['bytes','sha256'])||!Number.isSafeInteger(pin.bytes)||pin.bytes<=0||pin.bytes>1048576||!HASH.test(pin.sha256))
   fail('INVALID_PAYLOAD','Invalid qualified source pin');
 }
 if(!Array.isArray(payload.records)||payload.records.length!==5||
  !same(payload.records.map(row=>row?.key).sort(byteOrder),publicConfigurationKeys))fail('INVALID_PAYLOAD','Exactly the five reviewed public keys are required');
 let size=0;
 for(const row of payload.records){
  if(!exactKeys(row,['key','value_json'])||typeof row.value_json!=='string')fail('INVALID_PAYLOAD','Exact record JSON text required');
  size+=Buffer.byteLength(row.value_json);const value=JSON.parse(row.value_json);
  if(row.key.startsWith('policy:')&&(!object(value)||value.kind!==row.key.slice(7)||value.content_status!=='draft_for_legal_review'||value.legal_release_approved!==false))
   fail('INVALID_PAYLOAD','Policy must retain its draft and unapproved status');
 }
 if(size>131072)fail('INVALID_PAYLOAD','Public record values exceed the preparation bound');
 return payload.records.map(row=>({...row})).sort((a,b)=>byteOrder(a.key,b.key));
}

function snapshotRows(rows){
 if(!Array.isArray(rows)||rows.length>10000)fail('INVALID_SNAPSHOT','Bounded complete runtime-config snapshot required');
 const result=rows.map(row=>{
  if(!exactKeys(row,['key','value_json','revision','updated_by','updated_at'])||typeof row.key!=='string'||!row.key||
   typeof row.value_json!=='string'||typeof row.revision!=='string'||! /^(?:0|[1-9]\d*|-[1-9]\d*)$/.test(row.revision)||
   BigInt(row.revision)<-9223372036854775808n||BigInt(row.revision)>MAX_BIGINT||
   !(row.updated_by===null||typeof row.updated_by==='string')||typeof row.updated_at!=='string')fail('INVALID_SNAPSHOT','Runtime-config raw row shape differs');
  JSON.parse(row.value_json);return {...row};
 });
 if(!same(result.map(row=>row.key),result.map(row=>row.key).sort(byteOrder))||new Set(result.map(row=>row.key)).size!==result.length)
  fail('INVALID_SNAPSHOT','Runtime-config snapshot must be unique and COLLATE C ordered');
 if(Buffer.byteLength(JSON.stringify(result))>8388608)fail('INVALID_SNAPSHOT','Runtime-config snapshot exceeds bound');
 return result;
}

function buildPlan({payloadJson,payloadSha256,sourceManifestSha256,apiSourceId,catalogSha256,operationId,createdAt,preimage}){
 if(!HASH.test(sourceManifestSha256)||!HASH.test(catalogSha256)||!UUID.test(operationId)||typeof createdAt!=='string'||
  !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{3})?Z$/.test(createdAt)||!Number.isFinite(Date.parse(createdAt))||
  ![new Date(createdAt).toISOString(),new Date(createdAt).toISOString().replace('.000Z','Z')].includes(createdAt))
  fail('INVALID_PLAN','Explicit source/catalog, operation UUID and valid UTC timestamp required');
 const records=parsePayload(payloadJson,payloadSha256,apiSourceId),before=snapshotRows(preimage);
 const values=new Map(records.map(row=>[row.key,row.value_json]));const changed=[];
 for(const key of publicConfigurationKeys){
  const row=before.find(row=>row.key===key);
  if(!row)fail('MISSING_KEY','Reviewed public key is absent: '+key);
  if(BigInt(row.revision)<=0n)fail('INVALID_REVISION','Selected revisions must be positive bigints');
  if(row.value_json!==values.get(key)){
   if(BigInt(row.revision)===MAX_BIGINT)fail('REVISION_OVERFLOW','Selected revision would overflow');
   changed.push(key);
  }
 }
 const postimage=before.map(row=>changed.includes(row.key)?{key:row.key,value_json:values.get(row.key),revision:(BigInt(row.revision)+1n).toString(),updated_by:null,updated_at:createdAt}:{...row});
 const body={format:'collect.public-configuration.plan.v1',project_ref:PROJECT,operation_id:operationId,created_at:createdAt,
  payload_json:payloadJson,payload_sha256:payloadSha256,source_manifest_sha256:sourceManifestSha256,api_source_id:apiSourceId,catalog_sha256:catalogSha256,
  keys:[...publicConfigurationKeys],changed_keys:changed,preimage:before,postimage,
  legal_release_approved:false,provider_approved:false,retention_policy_activation:false};
 return freeze({...body,plan_sha256:sha(canonical(body))});
}

export function validatePublicConfigurationPlan(plan){
 if(!exactKeys(plan,['format','project_ref','operation_id','created_at','payload_json','payload_sha256','source_manifest_sha256','api_source_id','catalog_sha256','keys','changed_keys','preimage','postimage','legal_release_approved','provider_approved','retention_policy_activation','plan_sha256']))
  fail('INVALID_PLAN','Unexpected serialized plan shape');
 const rebuilt=buildPlan({payloadJson:payloadText(plan.payload_json),payloadSha256:plan.payload_sha256,sourceManifestSha256:plan.source_manifest_sha256,
  apiSourceId:plan.api_source_id,catalogSha256:plan.catalog_sha256,operationId:plan.operation_id,createdAt:plan.created_at,preimage:plan.preimage});
 if(canonical(plan)!==canonical(rebuilt))fail('INVALID_PLAN','Plan content or digest differs');
 return rebuilt;
}

async function verifySourcePins(plan,verifySource){
 if(typeof verifySource!=='function')fail('SOURCE_VERIFICATION_REQUIRED','A fresh qualified-source verifier is mandatory');
 const actual=await verifySource();
 const expected={payload_sha256:plan.payload_sha256,source_manifest_sha256:plan.source_manifest_sha256,api_source_id:plan.api_source_id};
 if(!exactKeys(actual,Object.keys(expected))||Object.keys(expected).some(key=>actual[key]!==expected[key]))fail('SOURCE_DRIFT','Qualified source identity changed');
}

// Supply an idle, already connected pg Client (or {client}), or an explicit {pool}.
// A Pool is never mistaken for a Client: its connection is reserved for the TX.
async function withClient(connection,run){
 if(connection?.pool){
  if(Object.keys(connection).length!==1||typeof connection.pool.connect!=='function')fail('INVALID_CONNECTION','Explicit injected pg Pool required');
  const client=await connection.pool.connect();
  let failure;
  try{return await run(client);}catch(error){failure=error;throw error;}
  finally{client.release(failure?.discard_connection?failure:undefined);}
 }
 const client=connection?.client??connection;
 if(!client||typeof client.query!=='function'||'totalCount' in client)fail('INVALID_CONNECTION','Connected pg Client or explicit {pool} required');
 return run(client);
}

async function fence(client,run,{operationId,mutation=false}={}){
 let beginning=true,committing=false;
 try{
  await client.query('BEGIN ISOLATION LEVEL READ COMMITTED');beginning=false;
  await client.query("SET LOCAL lock_timeout='5s'; SET LOCAL statement_timeout='30s'; SET LOCAL idle_in_transaction_session_timeout='30s'");
  await client.query('LOCK TABLE app.runtime_config,app.audit_log IN SHARE ROW EXCLUSIVE MODE');
  const result=await run();committing=true;await client.query('COMMIT');return result;
 }catch(error){
  let rollbackError;
  try{await client.query('ROLLBACK');}catch(failure){rollbackError=failure;}
  if(committing&&mutation){
   const uncertain=new Error('COMMIT acknowledgement is uncertain; reconcile this exact operation before any retry',{cause:error});
   uncertain.code='COMMIT_UNCONFIRMED';uncertain.operation_id=operationId;uncertain.reconcile_required=true;uncertain.discard_connection=true;
   if(rollbackError)uncertain.rollback_error=rollbackError;throw uncertain;
  }
  if(rollbackError){
   const uncertain=new Error('ROLLBACK acknowledgement is uncertain; discard the connection and reconcile the original operation',{cause:error});
   uncertain.code='ROLLBACK_UNCONFIRMED';uncertain.operation_id=operationId;uncertain.reconcile_required=true;uncertain.discard_connection=true;uncertain.rollback_error=rollbackError;throw uncertain;
  }
  if(beginning){
   const uncertain=new Error('BEGIN acknowledgement is uncertain; discard the connection before retrying',{cause:error});
   uncertain.code='BEGIN_UNCONFIRMED';uncertain.operation_id=operationId;uncertain.discard_connection=true;throw uncertain;
  }
  if(committing)error.discard_connection=true;
  throw error;
 }
}

export async function readPublicConfigurationSnapshot(client){
 const result=await client.query('SELECT key,value_json,revision::text AS revision,updated_by,updated_at FROM app.runtime_config ORDER BY key COLLATE "C"');
 return snapshotRows(result.rows);
}

function auditExpected(plan){
 const selected=rows=>rows.filter(row=>publicConfigurationKeys.includes(row.key));
 return {actor_user_id:null,actor_session_id:null,action:ACTION,entity_type:'runtime_config',entity_id:plan.operation_id,request_id:plan.operation_id,
  details_json:canonical({format:'collect.public-configuration.receipt.v1',operation_id:plan.operation_id,project_ref:PROJECT,plan_sha256:plan.plan_sha256,
   payload_sha256:plan.payload_sha256,source_manifest_sha256:plan.source_manifest_sha256,api_source_id:plan.api_source_id,catalog_sha256:plan.catalog_sha256,
   keys:plan.keys,changed_keys:plan.changed_keys,before:selected(plan.preimage),after:selected(plan.postimage),
   legal_release_approved:false,provider_approved:false,retention_policy_activation:false}),created_at:plan.created_at};
}

async function inspectFenced(client,plan){
 if(await catalogIdentity(client)!==plan.catalog_sha256)fail('CATALOG_DRIFT','Current catalog differs from the approved plan');
 const actual=await readPublicConfigurationSnapshot(client);
 // request_id is intentionally checked across all actions. It has no UNIQUE
 // constraint; both tables remain write-fenced until classification/commit.
 const receipts=(await client.query('SELECT id::text AS id,actor_user_id,actor_session_id,action,entity_type,entity_id,request_id,details_json,created_at FROM app.audit_log WHERE request_id=$1 ORDER BY id',[plan.operation_id])).rows;
 if(!receipts.length){
  if(!same(actual,plan.preimage))fail('PREIMAGE_DRIFT','Complete configuration preimage differs without a matching receipt');
  return {status:'not_applied',committed:false,verified:true,operation_id:plan.operation_id,plan_sha256:plan.plan_sha256};
 }
 if(receipts.length!==1)fail('RECEIPT_CARDINALITY','Operation has duplicate audit receipts');
 const {id,...receipt}=receipts[0];
 if(typeof id!=='string'||!/^[1-9]\d*$/.test(id)||canonical(receipt)!==canonical(auditExpected(plan)))fail('RECEIPT_DRIFT','Operation audit receipt differs');
 if(!same(actual,plan.postimage))fail('POSTIMAGE_DRIFT','Configuration differs from the receipted complete postimage');
 return {status:'applied',committed:true,verified:true,operation_id:plan.operation_id,plan_sha256:plan.plan_sha256,audit_id:id,changed_keys:[...plan.changed_keys]};
}

export async function preparePublicConfiguration(connection,{payloadBytes,payloadSha256,sourceManifestSha256,apiSourceId,catalogSha256,operationId,createdAt,verifySource}){
 const payloadJson=payloadText(payloadBytes);parsePayload(payloadJson,payloadSha256,apiSourceId);
 return withClient(connection,client=>fence(client,async()=>{
  const plan=buildPlan({payloadJson,payloadSha256,sourceManifestSha256,apiSourceId,catalogSha256,operationId,createdAt,preimage:await readPublicConfigurationSnapshot(client)});
  await verifySourcePins(plan,verifySource);await inspectFenced(client,plan);return plan;
 },{operationId}));
}

export async function reconcilePublicConfiguration(connection,input,{verifySource}={}){
 const plan=validatePublicConfigurationPlan(input);
 return withClient(connection,client=>fence(client,async()=>{
  await verifySourcePins(plan,verifySource);return inspectFenced(client,plan);
 },{operationId:plan.operation_id}));
}

export async function applyPublicConfiguration(connection,input,{verifySource}={}){
 const plan=validatePublicConfigurationPlan(input);
 return withClient(connection,client=>fence(client,async()=>{
  await verifySourcePins(plan,verifySource);
  const prior=await inspectFenced(client,plan);
  if(prior.committed)return {...prior,replayed:true};
  const changed=[];
  for(const key of plan.changed_keys){
   const row=plan.postimage.find(row=>row.key===key);
   const result=await client.query('UPDATE app.runtime_config SET value_json=$2,revision=$3::bigint,updated_by=NULL,updated_at=$4 WHERE key=$1 RETURNING key',[key,row.value_json,row.revision,row.updated_at]);
   if(result.rows.length!==1||result.rows[0].key!==key)fail('WRITE_SET_DRIFT','Changed configuration key set differs');
   changed.push(key);
  }
  if(!same(changed,plan.changed_keys))fail('WRITE_SET_DRIFT','Changed configuration key set differs');
  const receipt=auditExpected(plan);
  const result=await client.query('INSERT INTO app.audit_log(actor_user_id,actor_session_id,action,entity_type,entity_id,request_id,details_json,created_at) VALUES(NULL,NULL,$1,$2,$3,$4,$5,$6) RETURNING id::text AS id',
   [receipt.action,receipt.entity_type,receipt.entity_id,receipt.request_id,receipt.details_json,receipt.created_at]);
  if(result.rows.length!==1)fail('RECEIPT_CARDINALITY','Audit insert did not return exactly one receipt');
  await verifySourcePins(plan,verifySource);
  const applied=await inspectFenced(client,plan);
  if(!applied.committed||applied.audit_id!==result.rows[0].id)fail('RECEIPT_DRIFT','Inserted audit receipt differs');
  return {...applied,replayed:false};
 },{operationId:plan.operation_id,mutation:true}));
}
