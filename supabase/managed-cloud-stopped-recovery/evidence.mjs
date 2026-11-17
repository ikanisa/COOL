// Review-only evidence preparation. This module has no database or network
// client and never authorizes a fence transition, migration, or retry.
import {createHash,createPublicKey,verify} from 'node:crypto';

export class EvidenceError extends Error {
 constructor(code){super(code);this.name='EvidenceError';this.code=code;}
}
const fail=code=>{throw new EvidenceError(code);};
const exact=(value,names)=>value!==null&&typeof value==='object'&&!Array.isArray(value)&&
 Object.getPrototypeOf(value)===Object.prototype&&Object.keys(value).sort().join('\0')===[...names].sort().join('\0');
const hash=value=>typeof value==='string'&&/^[a-f0-9]{64}$/.test(value);
const uuid=value=>typeof value==='string'&&/^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/.test(value);
const epoch=value=>typeof value==='string'&&/^[1-9][0-9]{0,15}$/.test(value)&&BigInt(value)<=9007199254740991n;
const count=value=>typeof value==='string'&&/^(0|[1-9][0-9]{0,9})$/.test(value)&&BigInt(value)<=2147483647n;
const bounded=(value,min,max)=>Number.isSafeInteger(value)&&value>=min&&value<=max;
const text=value=>typeof value==='string'&&value.length>0&&value.length<=128&&/^[a-zA-Z0-9._:-]+$/.test(value);

// UTC microseconds are compared as integers; no timestamp loses PostgreSQL's
// precision through a JavaScript Date conversion. Leap seconds are refused.
function micros(value){
 if(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/.test(value))fail('invalid_timestamp');
 const msText=value.slice(0,23)+'Z',ms=Date.parse(msText);
 if(!Number.isFinite(ms)||new Date(ms).toISOString()!==msText)fail('invalid_timestamp');
 return BigInt(ms)*1000n+BigInt(value.slice(23,26));
}
function canonical(value){
 if(value===null||typeof value==='string'||typeof value==='boolean')return JSON.stringify(value);
 if(typeof value==='number'&&Number.isSafeInteger(value))return JSON.stringify(value);
 if(Array.isArray(value))return '['+value.map(canonical).join(',')+']';
 if(value&&typeof value==='object'&&Object.getPrototypeOf(value)===Object.prototype)
  return '{'+Object.keys(value).sort().map(key=>JSON.stringify(key)+':'+canonical(value[key])).join(',')+'}';
 fail('invalid_json_value');
}
// Check object graphs iteratively before recursive serialization. A compact
// JSON string can otherwise fit the byte limit while exhausting the call stack.
// JSON trees have no aliases, cycles, sparse arrays, accessors or symbol keys.
function boundedStructure(value){
 const stack=[{value,depth:0}],seen=new WeakSet();let nodes=0,textBytes=0;
 while(stack.length){
  const current=stack.pop();if(++nodes>1024||current.depth>12)fail('evidence_structure_limit');
  const item=current.value;
  if(item===null||typeof item==='boolean')continue;
  if(typeof item==='number'){if(!Number.isSafeInteger(item))fail('invalid_json_value');continue;}
  if(typeof item==='string'){textBytes+=Buffer.byteLength(item,'utf8');if(textBytes>16384)fail('evidence_too_large');continue;}
  if(!item||typeof item!=='object'||(!Array.isArray(item)&&Object.getPrototypeOf(item)!==Object.prototype))fail('invalid_json_value');
  if(seen.has(item))fail('invalid_json_value');seen.add(item);
  const keys=Reflect.ownKeys(item),descriptors=Object.getOwnPropertyDescriptors(item);
  if(keys.some(key=>typeof key!=='string'))fail('invalid_json_value');
  if(Array.isArray(item)){
   if(item.length>128||keys.length!==item.length+1)fail('evidence_structure_limit');
   for(let i=0;i<item.length;i++){
    const descriptor=descriptors[String(i)];
    if(!descriptor||!descriptor.enumerable||!Object.hasOwn(descriptor,'value'))fail('invalid_json_value');
    stack.push({value:descriptor.value,depth:current.depth+1});
   }
  }else{
   if(keys.length>128)fail('evidence_structure_limit');
   for(const key of keys){
    const descriptor=descriptors[key];textBytes+=Buffer.byteLength(key,'utf8');
    if(Buffer.byteLength(key,'utf8')>128||textBytes>16384)fail('evidence_too_large');
    if(!descriptor.enumerable||!Object.hasOwn(descriptor,'value'))fail('invalid_json_value');
    stack.push({value:descriptor.value,depth:current.depth+1});
   }
  }
 }
}
export function canonicalEvidence(value){boundedStructure(value);const out=canonical(value);if(Buffer.byteLength(out,'utf8')>16384)fail('evidence_too_large');return out;}
export function evidenceDigest(value){return createHash('sha256').update(canonicalEvidence(value),'utf8').digest('hex');}
// Ingest exact canonical wire bytes to reject duplicate keys and aliases.
export function parseCanonicalEvidence(raw){
 if(typeof raw!=='string'||Buffer.byteLength(raw,'utf8')>16384)fail('invalid_evidence');
 let value;try{value=JSON.parse(raw);}catch{fail('invalid_evidence');}
 if(canonicalEvidence(value)!==raw)fail('noncanonical_evidence');return value;
}

function validateSnapshot(s){
 if(!exact(s,['format','project_ref','control','admission'])||s.format!=='collect.managed-fence-snapshot.v1'||
  s.project_ref!=='rrlduytparvsjfmegalh'||!exact(s.control,['mode','epoch','source_sha256','operation_id','changed_at','quiesce_receipt_sha256'])||
  !exact(s.admission,['admission_id','epoch','source_sha256','kind','state','created_at','external_dispatches','uncertain_dispatches']))fail('invalid_snapshot');
 const c=s.control,a=s.admission;
 if(!['open','quiescing','fenced'].includes(c.mode)||!epoch(c.epoch)||!hash(c.source_sha256)||!uuid(c.operation_id)||
  !(c.quiesce_receipt_sha256===null||hash(c.quiesce_receipt_sha256))||!uuid(a.admission_id)||!epoch(a.epoch)||!hash(a.source_sha256)||
  !['http_collect','http_admin','jobs'].includes(a.kind)||!['active','unresolved'].includes(a.state)||!count(a.external_dispatches)||!count(a.uncertain_dispatches))fail('invalid_snapshot');
 const changed=micros(c.changed_at),created=micros(a.created_at);
 if(c.epoch!==a.epoch||c.source_sha256!==a.source_sha256)fail('snapshot_binding_mismatch');
 return {changed,created};
}
function validatePolicy(p){
 if(!exact(p,['format','project_ref','admission_id','epoch','source_sha256','snapshot_sha256','signer_spki_sha256',
  'max_age_seconds','clock_skew_seconds','max_worker_seconds'])||p.format!=='collect.managed-stop-review-policy.v1'||
  p.project_ref!=='rrlduytparvsjfmegalh'||!uuid(p.admission_id)||!epoch(p.epoch)||!hash(p.source_sha256)||!hash(p.snapshot_sha256)||
  !hash(p.signer_spki_sha256)||!bounded(p.max_age_seconds,1,900)||!bounded(p.clock_skew_seconds,0,30)||!bounded(p.max_worker_seconds,1,600))fail('invalid_policy');
}
function validateClaims(a){
 if(!exact(a,['format','project_ref','admission_id','epoch','source_sha256','snapshot_sha256','control_operation_id',
  'quiesce_receipt_sha256','invocation_id','deployment_sha256','linkage_artifact_sha256','stopped_artifact_sha256',
  'invocation_started_at','invocation_stopped_at','issued_at','external_effects','executor_outcome'])||
  a.format!=='collect.managed-edge-stop-attestation.v1'||a.project_ref!=='rrlduytparvsjfmegalh'||!uuid(a.admission_id)||
  !epoch(a.epoch)||!hash(a.source_sha256)||!hash(a.snapshot_sha256)||!uuid(a.control_operation_id)||!hash(a.quiesce_receipt_sha256)||
  !text(a.invocation_id)||!hash(a.deployment_sha256)||!hash(a.linkage_artifact_sha256)||!hash(a.stopped_artifact_sha256)||
  a.external_effects!=='unknown'||a.executor_outcome!=='stopped')fail('invalid_attestation');
 return {start:micros(a.invocation_started_at),stop:micros(a.invocation_stopped_at),issued:micros(a.issued_at)};
}

// The independently pinned policy is not itself authenticated by this module.
// A valid signature only proves that the pinned key signed the exact claims;
// it does not prove the signer's authority or the truth of external evidence.
export function inspectManagedStopEvidence({snapshot,policy,expectedPolicySha256,attestation,signatureBase64,signerPublicKeyPem,now}){
 const times=validateSnapshot(snapshot);validatePolicy(policy);
 if(!hash(expectedPolicySha256)||evidenceDigest(policy)!==expectedPolicySha256)fail('policy_pin_mismatch');
 const snapshotSha=evidenceDigest(snapshot),c=snapshot.control,a=snapshot.admission;
 if(snapshotSha!==policy.snapshot_sha256||a.admission_id!==policy.admission_id||a.epoch!==policy.epoch||a.source_sha256!==policy.source_sha256)fail('snapshot_pin_mismatch');
 const at=micros(now),blockers=[];
 if(c.mode!=='quiescing'||c.quiesce_receipt_sha256===null)blockers.push('committed_quiesce_not_verified');
 if(attestation===undefined||attestation===null){
  blockers.push('authenticated_admission_execution_binding_missing','authenticated_executor_stop_missing');
  return result('blocked',snapshotSha,blockers);
 }
 const claimTimes=validateClaims(attestation);
 if(typeof signerPublicKeyPem!=='string'||Buffer.byteLength(signerPublicKeyPem,'utf8')>4096||
  typeof signatureBase64!=='string'||signatureBase64.length!==88)fail('invalid_signature');
 let publicKey,signature;
 try{publicKey=createPublicKey(signerPublicKeyPem);signature=Buffer.from(signatureBase64,'base64');}catch{fail('invalid_signature');}
 if(publicKey.asymmetricKeyType!=='ed25519'||signature.length!==64||signature.toString('base64')!==signatureBase64||
  createHash('sha256').update(publicKey.export({type:'spki',format:'der'})).digest('hex')!==policy.signer_spki_sha256||
  !verify(null,Buffer.from(canonicalEvidence(attestation),'utf8'),publicKey,signature))fail('invalid_signature');
 if(c.mode!=='quiescing'||c.quiesce_receipt_sha256===null)return result('blocked',snapshotSha,blockers);
 if(attestation.admission_id!==a.admission_id||attestation.epoch!==a.epoch||attestation.source_sha256!==a.source_sha256||
  attestation.snapshot_sha256!==snapshotSha||attestation.control_operation_id!==c.operation_id||
  attestation.quiesce_receipt_sha256!==c.quiesce_receipt_sha256)fail('attestation_binding_mismatch');
 const skew=BigInt(policy.clock_skew_seconds)*1000000n,age=BigInt(policy.max_age_seconds)*1000000n,wall=BigInt(policy.max_worker_seconds)*1000000n;
 if(times.changed<times.created||claimTimes.start>times.created||claimTimes.stop<times.created||claimTimes.stop<claimTimes.start||claimTimes.stop-claimTimes.start>wall||
  claimTimes.issued<claimTimes.stop||claimTimes.issued<times.changed||claimTimes.issued>at+skew||at-claimTimes.issued>age)fail('attestation_time_mismatch');
 return result('signed_claims_consistent',snapshotSha,[]);
}
function result(status,snapshotSha,blockers){return {format:'collect.managed-stop-evidence-result.v1',status,snapshot_sha256:snapshotSha,blockers,
 write_authorized:false,fence_change_authorized:false,stopped_record_authorized:false,replay_authorized:false,
 external_effects:'unknown',original_counters_recovered:false,provider_settlement_proven:false,
 still_unverified:['signer_authority','provider_artifact_authenticity','admission_execution_link','committed_quiesce',
  'executor_termination','unknown_effect_obligation_retention','current_catalogue','schema_actor_exclusion','recovery_protocol']};}
