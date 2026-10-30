import {dirname,join} from 'node:path';
import {SqliteDesktopJournal} from './direct-desktop/journal.mjs';
import {SafeError,UUID,object} from './config.mjs';
import {SHA,canonical,digest,instant} from './retention_contract.mjs';

const fail=()=>{throw new SafeError('retention_journal_unavailable','The private retention journal could not be verified. Preserve it and the original operation references; no action was replayed.');};
const states=['prepared','dispatching','unknown','observed','cancelled'];
function validate(record){
 if(!object(record)||Object.keys(record).sort().join(',')!=='dispatches,observations,preview,preview_sha256,receipt,state,version'||record.version!==1||!states.includes(record.state)||!Number.isSafeInteger(record.dispatches)||record.dispatches<0||record.dispatches>20||!Array.isArray(record.observations)||record.observations.length>20)fail();
 const p=record.preview;
 if(!object(p)||Object.keys(p).sort().join(',')!=='binding,contract_version,created_at,expected,input,kind,operation_id,scope'||p.contract_version!==1||p.scope!=='approved_eligible_data_disposition'||!['plan','claim','execute','reconcile'].includes(p.kind)||!UUID.test(p.operation_id??'')||!instant(p.created_at)||!object(p.binding)||!object(p.input)||!object(p.expected)||!SHA.test(record.preview_sha256??'')||digest(p)!==record.preview_sha256)fail();
 if(p.kind!=='reconcile'&&p.input.p_operation_id!==p.operation_id||p.kind==='reconcile'&&Object.hasOwn(p.input,'p_operation_id'))fail();
 return record;
}
export class RetentionJournal {
 #store;
 constructor(config){
  this.#store=new SqliteDesktopJournal(join(dirname(config.credentialFile),'retention.sqlite'));
  try{this.#store.transaction(tx=>{
   const marker=tx.get('control','retention');
   if(marker===null){if(['tickets','jobs','attempts','observations','policies','syncs','control'].some(table=>tx.all(table).length))fail();tx.put('control','retention',{contract_version:1,scope:'retention_operator_journal'});}
   else if(canonical(marker)!==canonical({contract_version:1,scope:'retention_operator_journal'}))fail();
  });}catch(error){this.#store.close();throw error;}
 }
 close(){this.#store.close();}
 list(){return this.#store.transaction(tx=>tx.all('attempts').map(validate));}
 get(hash){if(!SHA.test(hash??''))fail();return this.#store.transaction(tx=>{const value=tx.get('attempts',hash);if(!value)fail();return validate(value);});}
 operation(id){if(!UUID.test(id??''))fail();const found=this.list().filter(row=>row.preview.operation_id===id);if(found.length!==1)fail();return found[0];}
 save(preview){
  const record=validate({version:1,preview,preview_sha256:digest(preview),state:'prepared',dispatches:0,receipt:null,observations:[]});
  return this.#store.transaction(tx=>{
   const all=tx.all('attempts').map(validate);if(all.length>=1000||all.some(row=>row.preview.operation_id===preview.operation_id))fail();
   const scopeField={plan:'p_request_id',claim:'p_plan_id',execute:'p_claim_id'}[preview.kind];
   if(scopeField&&all.some(row=>row.preview.kind===preview.kind&&row.preview.input[scopeField]===preview.input[scopeField]&&!['observed','cancelled'].includes(row.state)))
    throw new SafeError('retention_original_operation_unresolved','An original operation in this scope is still prepared or unconfirmed. Recover or review that operation; no replacement identity was created.');
   tx.put('attempts',record.preview_sha256,record);return record;
  });
 }
 begin(hash,{retry=false,expectedDispatches=0}={}){
  return this.#store.transaction(tx=>{
   const record=validate(tx.get('attempts',hash));
   if(record.dispatches!==expectedDispatches||record.dispatches>=20||(!retry&&record.state!=='prepared')||(retry&&!['unknown','dispatching'].includes(record.state))||retry&&record.preview.kind==='reconcile')fail();
   const next={...record,state:'dispatching',dispatches:record.dispatches+1};tx.put('attempts',hash,next);return next;
  });
 }
 finish(hash,dispatches,state,receipt){
  if(!['observed','unknown'].includes(state))fail();
  return this.#store.transaction(tx=>{
   const record=validate(tx.get('attempts',hash));
   if(record.dispatches!==dispatches||!['dispatching','unknown'].includes(record.state))fail();
   const next={...record,state,receipt};tx.put('attempts',hash,next);return next;
  });
 }
 observe(hash,observation,{receipt=null,committed=false}={}){
  return this.#store.transaction(tx=>{
   const record=validate(tx.get('attempts',hash));if(record.dispatches<1||record.state==='cancelled')fail();
   const next={...record,state:committed?'observed':record.state==='observed'?'observed':'unknown',receipt:receipt??record.receipt,observations:[...record.observations.slice(-19),observation]};
   tx.put('attempts',hash,next);return next;
  });
 }
 cancel(hash){return this.#store.transaction(tx=>{
  const record=validate(tx.get('attempts',hash));if(record.state!=='prepared'||record.dispatches!==0)fail();const next={...record,state:'cancelled'};tx.put('attempts',hash,next);return next;
 });}
}
