// Injected management adapter for one fenced core revision with collect-sms
// enabled and dispatch unpaused. Importing this module makes no network calls.
// The caller uses the normal revision operator and its immutable journals;
// this adapter never filters inventory or changes the gateway pause flag.
import {createHash} from 'node:crypto';
import {readAncillaryRegistration,requireSameRegistration,scopedInventory} from './ancillary-inventory.mjs';

const digest=/^[a-f0-9]{64}$/;
const uuid=/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const hash=x=>createHash('sha256').update(x).digest('hex');
const fail=code=>{throw Error(code);};
const names=['BUILD_SOURCE_ID','COLLECT_SMS_CORE_SOURCE_SHA256'];
const slugs=new Set(['collect-api','admin-api','collect-jobs']);

export function createSmsSourceRevisionApi({request,oldSource,newSource,gatewayReleaseSha256,oldEpoch,
  readFence,expectedFenceId,withFenceLock,readRegistration=readAncillaryRegistration,unchangedSecrets={}}) {
 if(typeof request!=='function'||typeof readFence!=='function'||typeof expectedFenceId!=='function'||typeof withFenceLock!=='function'||
  typeof readRegistration!=='function'||!digest.test(oldSource??'')||!digest.test(newSource??'')||oldSource===newSource||
  !digest.test(gatewayReleaseSha256??'')||!Number.isSafeInteger(oldEpoch)||oldEpoch<1||!unchangedSecrets||
  typeof unchangedSecrets!=='object'||Array.isArray(unchangedSecrets)) fail('sms_revision_input_invalid');
 const fixed={...unchangedSecrets,COLLECT_SMS_ENABLED:hash('true'),COLLECT_SMS_DISPATCH_PAUSED:hash('false'),
  COLLECT_SMS_RELEASE_SHA256:hash(gatewayReleaseSha256)};
 if(Object.entries(fixed).some(([k,v])=>names.includes(k)||!/^[A-Z][A-Z0-9_]{1,127}$/.test(k)||!digest.test(v??'')))
  fail('sms_revision_input_invalid');
 // Reject conflicting assertions rather than silently overwriting caller pins.
 for(const [k,v] of Object.entries(unchangedSecrets)) if(fixed[k]!==v)fail('sms_revision_input_invalid');
 const oldHash=hash(oldSource),newHash=hash(newSource);let attempted=false;
 async function bindings(response) {
  const rows=response.json();if(!Array.isArray(rows))fail('sms_revision_secret_metadata_invalid');
  const get=name=>{const found=rows.filter(r=>r?.name===name);
   if(found.length!==1||!digest.test(found[0]?.value??''))fail('sms_revision_secret_metadata_invalid');return found[0].value;};
  for(const [name,value] of Object.entries(fixed))if(get(name)!==value)fail('sms_revision_unchanged_secret_changed');
  const core=get(names[0]),sms=get(names[1]);
  if(core!==sms||![oldHash,newHash].includes(core))fail('sms_revision_source_bindings_disagree');
  return core===oldHash?'previous':'candidate';
 }
 async function secrets() {const response=await request('secrets');return {response,stage:await bindings(response)};}
 async function inventory() {
  const registration=readRegistration();
  if(!registration?.entries?.some(r=>r.slug==='collect-sms'))fail('sms_revision_registration_required');
  const response=await request('functions');
  scopedInventory(response.json(),registration);
  requireSameRegistration(registration,readRegistration());
  return response; // Preserve every row; reviseRuntime must perform its own exact checks.
 }
 async function fenced() {
  const id=expectedFenceId(),s=await readFence();
  if(!uuid.test(id??'')||!s||s.mode!=='fenced'||Number(s.epoch)!==oldEpoch||s.source_sha256!==oldSource||
   s.operation_id!==id||s.activeAdmissions!==0||s.scheduler?.checked!==true||
   s.scheduler?.coverageVerified!==true||s.scheduler?.blocking!==false)fail('sms_revision_fence_unconfirmed');
 }
 return async function smsSourceRevisionApi(path,options) {
  const method=options?.method??'GET';
  if(path==='functions'&&method==='GET') {
   // Let the integrated operator handle exact proof and deliberate version-bump
   // stop after its source-secret completion receipt has been persisted.
   const response=await request(path,options);await secrets();return response;
  }
  if(path==='secrets'&&method==='GET')return (await secrets()).response;
  if(path==='secrets'&&method==='POST') {
   let rows;try{rows=JSON.parse(options.body);}catch{fail('sms_revision_write_invalid');}
   if(attempted||!Array.isArray(rows)||rows.length!==1||Object.keys(rows[0]??{}).sort().join(',')!=='name,value'||
    rows[0].name!==names[0]||rows[0].value!==newSource)fail('sms_revision_write_invalid');
   return withFenceLock(async()=>{
    await fenced();await inventory();if((await secrets()).stage!=='previous')fail('sms_revision_source_not_previous');
    await fenced();
    attempted=true; // A timeout or ambiguous response is never retried by this instance.
    const body=JSON.stringify(names.map(name=>({name,value:newSource})));
    const response=await request(path,{...options,body});
    if((await secrets()).stage!=='candidate')fail('sms_revision_write_unconfirmed');
    // Do not read inventory here: Supabase may increment function versions on a
    // secret write. The caller must first journal the acknowledged source write,
    // then stop on the normal registered inventory check and requalify fenced.
    return response;
   });
  }
  if(path.startsWith('functions/deploy?slug=')&&method==='POST') {
   if(!slugs.has(path.slice('functions/deploy?slug='.length)))fail('sms_revision_request_invalid');
   return withFenceLock(async()=>{await fenced();await inventory();
    if((await secrets()).stage!=='candidate')fail('sms_revision_write_unconfirmed');
    await fenced();return request(path,options);});
  }
  fail('sms_revision_request_invalid');
 };
}

/** A read-only fence probe on the exact connection owned by reviseRuntime. */
export function smsRevisionFenceReader(client) {
 if(!client||typeof client.query!=='function')fail('sms_revision_input_invalid');
 return async()=>{
  const rows=(await client.query(`SELECT c.mode,c.epoch,c.operation_id::text,c.source_sha256,
   (SELECT count(*)::int FROM private.collect_fence_admissions a WHERE a.state IN('active','unresolved')
    AND NOT private._collect_stopped_matches(a.admission_id,a.epoch,a.source_sha256,a.kind)) AS "activeAdmissions",
   private._collect_fence_scheduler_status() AS scheduler
   FROM private.collect_fence_control c WHERE c.singleton FOR UPDATE OF c`)).rows;
  if(!Array.isArray(rows)||rows.length!==1)fail('sms_revision_fence_unconfirmed');return rows[0];
 };
}
