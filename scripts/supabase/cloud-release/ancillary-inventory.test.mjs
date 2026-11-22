import {managedJobsHandlerFiles} from './managed-jobs-handler-patch.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,writeFileSync,chmodSync,symlinkSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {sha,PROJECT} from './access.mjs';
import {CORE_FUNCTIONS,decodeAncillaryRegistration,readAncillaryRegistration,scopedInventory,evidenceCore,requireSameRegistration} from './ancillary-inventory.mjs';
import {sameDeployedFunctions,requireKeyInventoryCheckpoint,verifyDeploymentEvidence} from './managed-jobs-key-operator.mjs';
import {requireInventoryCheckpoint,requireSchedulerInventory} from './managed-jobs-operator.mjs';

const uuid=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const core=CORE_FUNCTIONS.map((slug,i)=>({slug,id:uuid(i+1),status:'ACTIVE',version:4,verify_jwt:false,ezbr_sha256:'a'.repeat(64)}));
const ancillary={slug:'collect-sms',id:uuid(7),status:'ACTIVE',version:2,verify_jwt:false,ezbr_sha256:'b'.repeat(64),sourceSha256:'c'.repeat(64)};
const provider=({sourceSha256,...rest})=>rest;
const make=(entries=[ancillary])=>{const bytes=Buffer.from(JSON.stringify({format:'collect.cloud-ancillary-inventory.v1',project:PROJECT,reviewedEvidenceSha256:'d'.repeat(64),functions:entries}));return {bytes,digest:sha(bytes),registration:decodeAncillaryRegistration(bytes,sha(bytes))};};

test('without registration the original exact-three invariant stays in force',()=>{
 assert.deepEqual(scopedInventory(core).core,core);assert.throws(()=>scopedInventory([...core,provider(ancillary)]));
 assert.throws(()=>scopedInventory([core[0],core[0],core[2]]));
});
test('registered sidecars are exact and old core evidence remains valid',()=>{
 const {registration}=make();const rows=[core[2],provider(ancillary),core[0],core[1]];
 assert.deepEqual(scopedInventory(rows,registration),{core,ancillary:[provider(ancillary)]});
 assert.deepEqual(evidenceCore(core,registration),core);
 assert.deepEqual(evidenceCore(rows,registration),core);
 assert.equal(sameDeployedFunctions(core,rows,registration),true);
 assert.equal(sameDeployedFunctions(core,rows),false);
 assert.equal(sameDeployedFunctions(core,[...core,{...provider(ancillary),version:3}],registration),false);
});
test('both reviewed sidecars retain their independently pinned JWT configuration',()=>{
 const second={...ancillary,slug:'send-sms-hook',id:uuid(9),verify_jwt:true,version:8};
 const {registration}=make([ancillary,second]);
 const rows=[...core,provider(ancillary),provider(second)];assert.equal(scopedInventory(rows,registration).ancillary.length,2);
 assert.throws(()=>scopedInventory([...core,provider(ancillary),{...provider(second),verify_jwt:false}],registration));
});
test('provider drift, unknown, missing and duplicate sidecars fail closed',()=>{
 const {registration}=make();const side=provider(ancillary);
 for(const changed of [{...side,id:uuid(8)},{...side,version:3},{...side,status:'REMOVED'},
  {...side,verify_jwt:true},{...side,ezbr_sha256:'0'.repeat(64)},{...side,slug:'unexpected'}])
  assert.throws(()=>scopedInventory([...core,changed],registration));
 assert.throws(()=>scopedInventory(core,registration));
 assert.throws(()=>scopedInventory([...core,side,side],registration));
});
test('the scheduler refuses changed proof or inventory before a mutation',()=>{
 const registration=make().registration,rows=[...core,provider(ancillary)],pre={functions:core,ancillaryRegistration:registration};
 assert.equal(requireSchedulerInventory(core,rows,registration),rows);
 assert.throws(()=>requireSchedulerInventory(core,rows));
 assert.throws(()=>requireSchedulerInventory(core,[...core,{...provider(ancillary),version:3}],registration));
 requireInventoryCheckpoint(pre,rows,registration);
 requireKeyInventoryCheckpoint(pre,rows,registration);
 assert.throws(()=>requireInventoryCheckpoint(pre,[...core,{...provider(ancillary),version:3}],registration));
 assert.throws(()=>requireKeyInventoryCheckpoint(pre,[...core,{...provider(ancillary),version:3}],registration));
 assert.throws(()=>requireInventoryCheckpoint(pre,rows,make([{...ancillary,version:3}]).registration));
});
test('source-bound key evidence accepts only the separately reviewed sidecar',()=>{
 const registration=make().registration;
 const modules=Object.entries(managedJobsHandlerFiles);
 const hashes=Object.fromEntries(modules.map(([key],index)=>[key,(index+1).toString(16).repeat(64)]));
 const manifest={project:PROJECT,files:modules.map(([key,name])=>({path:'functions/_shared/'+name,sha256:hashes[key]}))};
 const sourceSha=sha(JSON.stringify(manifest)),evidence={intent:{sourceSha256:sourceSha,snapshot:{manifest}},
  deployment:{sourceSha256:sourceSha,functions:core},currentFunctions:[...core,provider(ancillary)],
  currentSource:sourceSha,handler:{hashes},ancillaryRegistration:registration};
 assert.equal(verifyDeploymentEvidence(evidence),sourceSha);
 assert.throws(()=>verifyDeploymentEvidence({...evidence,ancillaryRegistration:null}));
 assert.throws(()=>verifyDeploymentEvidence({...evidence,currentFunctions:[...core,{...provider(ancillary),ezbr_sha256:'f'.repeat(64)}]}));
});
test('registration is project bound and rejects bad names, duplicate entries and changed bytes',()=>{
 const {bytes,digest,registration}=make();assert.throws(()=>decodeAncillaryRegistration(Buffer.concat([bytes,Buffer.from(' ')]),digest));
 const duplicate=Buffer.from(bytes.toString().replace('"format":','"format":"other","format":'));
 assert.throws(()=>decodeAncillaryRegistration(duplicate,sha(duplicate)));
 for(const change of [{...ancillary,slug:'unexpected'},{...ancillary,sourceSha256:'x'}, {...ancillary,version:0}])
  assert.throws(()=>make([change]));
 assert.throws(()=>make([ancillary,ancillary]));
 assert.throws(()=>decodeAncillaryRegistration(Buffer.from('{}'),'0'.repeat(64)));
 assert.throws(()=>requireSameRegistration(registration,make([{...ancillary,version:3}]).registration));
});
test('proof loader requires an owned, private, digest-named, non-symlink file',()=>{
 const root=mkdtempSync(join(tmpdir(),'collect-ancillary-proof-')),{bytes,digest,registration}=make();
 const file=join(root,'ancillary-inventory-'+digest+'.json');
 try{
  assert.equal(readAncillaryRegistration({root,digest:undefined}),null);
  writeFileSync(file,bytes,{mode:0o600,flag:'wx'});assert.deepEqual(readAncillaryRegistration({root,digest}),registration);
  chmodSync(file,0o644);assert.throws(()=>readAncillaryRegistration({root,digest}));
  rmSync(file);const target=join(root,'other');writeFileSync(target,bytes,{mode:0o600});symlinkSync(target,file);
  assert.throws(()=>readAncillaryRegistration({root,digest}));
 }finally{rmSync(root,{recursive:true,force:true});}
});
