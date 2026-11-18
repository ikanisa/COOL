// Readback-only reconciliation for the native-config secret write. No provider
// request is made here. Secret *hashes* and exact reviewed inventory only.
import {sha} from './access.mjs';
import {sameDeployedFunctions} from './managed-jobs-key-operator.mjs';
import {evidenceCore,registrationSnapshot,requireVersionOnlyRequalification} from './ancillary-inventory.mjs';
const HASH=/^[a-f0-9]{64}$/;
const fail=()=>{throw Error('native_config_reconciliation_unconfirmed');};
const same=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
const obj=x=>Object.fromEntries([...x].sort(([a],[b])=>a.localeCompare(b)));
const exact=(a,b)=>same(Object.entries(a).sort(),Object.entries(b).sort());
const budgetNames=['native_provider_source_sha256','native_provider_model_id','native_provider_approval_sha256',
 'native_provider_used','native_provider_limit','native_provider_expires_at'];
function budget(pre){
 const row=pre?.row;if(!row||budgetNames.some(name=>!Object.hasOwn(row,name)))fail();
 return Object.fromEntries(budgetNames.map(name=>[name,row[name] instanceof Date?row[name].toISOString():row[name]]));
}
const expectedNames=['BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED','COLLECT_JOB_NATIVE_SMS_APPROVAL_SHA256','MOMO_AI_ENABLED','MOMO_AI_MODEL'].sort().join(',');
function currentMetadata(pre){
 if(!(pre?.secrets instanceof Map))fail();
 const out=obj(pre.secrets);
 if(Object.entries(out).some(([name,value])=>!/^[A-Z][A-Z0-9_]{1,127}$/.test(name)||!HASH.test(value??'')))fail();
 return out;
}
export function createNativeConfigIntent(pre,evidenceSha256,changes){
 if(!HASH.test(pre?.source??'')||!HASH.test(evidenceSha256??'')||!Array.isArray(changes)||changes.length!==4||
  new Set(changes.map(x=>x?.name)).size!==4||
  [...changes.map(x=>x.name)].sort().join(',')!==expectedNames||changes.some(x=>typeof x.value!=='string'))fail();
 const values=Object.fromEntries(changes.map(x=>[x.name,x.value]));
 if(values.MOMO_AI_ENABLED!=='true'||values.BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED!=='true'||
  !HASH.test(values.COLLECT_JOB_NATIVE_SMS_APPROVAL_SHA256)||!/^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$/.test(values.MOMO_AI_MODEL))fail();
 const metadata=currentMetadata(pre),expected=Object.fromEntries(changes.map(x=>[x.name,sha(x.value)]));
 const functions=evidenceCore(pre.functions,pre.ancillaryRegistration??null);
 if(pre.ancillaryRegistration?.entries?.some(x=>x.slug==='collect-sms')&&
  (metadata.COLLECT_SMS_ENABLED!==sha('true')||metadata.COLLECT_SMS_DISPATCH_PAUSED!==sha('false')))fail();
 return {format:'collect.native-config-intent.v2',project:'rrlduytparvsjfmegalh',sourceSha256:pre.source,
  evidenceSha256,metadata,expected,budget:budget(pre),functions,ancillaryRegistration:registrationSnapshot(pre.ancillaryRegistration??null)};
}
export function requireNativeConfigPreimage(intent,pre){
 if(intent?.format!=='collect.native-config-intent.v2'||pre?.source!==intent.sourceSha256||
  !exact(intent.metadata,currentMetadata(pre))||!same(intent.budget,budget(pre))||
  !sameDeployedFunctions(intent.functions,pre.functions,pre.ancillaryRegistration??null)||
  !same(intent.ancillaryRegistration,registrationSnapshot(pre.ancillaryRegistration??null)))fail();
}
function verifyAcknowledged(intent,attempt,ack,pre,evidenceSha256){
 if(intent?.format!=='collect.native-config-intent.v2'||intent.project!=='rrlduytparvsjfmegalh'||
  intent.sourceSha256!==pre?.source||intent.evidenceSha256!==evidenceSha256||
  !intent.expected||Object.keys(intent.expected).sort().join(',')!==expectedNames||
  Object.values(intent.expected).some(value=>!HASH.test(value??''))||!same(intent.budget,budget(pre))||
  attempt?.intentSha256!==sha(JSON.stringify(intent))||ack?.attemptSha256!==sha(JSON.stringify(attempt))||
  !Number.isInteger(ack.status)||ack.status<200||ack.status>=300||pre.row?.enabled!==false||pre.row?.active!==false||pre.row?.pending!==0)
  fail();
 if(!exact({...intent.metadata,...intent.expected},currentMetadata(pre))||
  !sameDeployedFunctions(intent.functions,pre.functions,pre.ancillaryRegistration??null))fail();
 const current=registrationSnapshot(pre.ancillaryRegistration??null);
 if(current?.entries?.some(x=>x.slug==='collect-sms')&&
  (pre.secrets.get('COLLECT_SMS_ENABLED')!==sha('true')||pre.secrets.get('COLLECT_SMS_DISPATCH_PAUSED')!==sha('false')))fail();
 return current;
}
export function createNativeConfigBridge(intent,attempt,ack,pre,evidenceSha256){
 const current=verifyAcknowledged(intent,attempt,ack,pre,evidenceSha256);
 try{requireVersionOnlyRequalification(intent.ancillaryRegistration,current);}catch{fail();}
 return {format:'collect.native-config-ancillary-bridge.v1',previousDigest:intent.ancillaryRegistration.digest,
  registration:current,intentSha256:sha(JSON.stringify(intent)),attemptSha256:sha(JSON.stringify(attempt)),ackSha256:sha(JSON.stringify(ack))};
}
export function requireNativeConfigReadback(intent,attempt,ack,pre,evidenceSha256,bridge=null){
 const current=verifyAcknowledged(intent,attempt,ack,pre,evidenceSha256);
 if(same(current,intent.ancillaryRegistration))return true;
 if(!bridge||bridge.format!=='collect.native-config-ancillary-bridge.v1'||bridge.previousDigest!==intent.ancillaryRegistration?.digest||
  bridge.intentSha256!==sha(JSON.stringify(intent))||bridge.attemptSha256!==sha(JSON.stringify(attempt))||
  bridge.ackSha256!==sha(JSON.stringify(ack))||!same(bridge.registration,current))fail();
 try{requireVersionOnlyRequalification(intent.ancillaryRegistration,current);}catch{fail();}
 return true;
}
