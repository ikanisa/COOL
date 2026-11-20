import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {sha,PROJECT} from './access.mjs';
import {renderManagedJobsHandler} from './managed-jobs-handler-patch.mjs';
import {verifyDeploymentEvidence,qualifiedSchedule} from './managed-jobs-key-operator.mjs';
const handler=await renderManagedJobsHandler();
const manifest={format:'collect.cloud-runtime-source.v1',project:PROJECT,files:[
 {path:'functions/_shared/serve.js',sha256:handler.hashes.serve},
 {path:'functions/_shared/scheduled-processing.js',sha256:handler.hashes.processing},
 {path:'functions/_shared/managed-jobs-dispatch-auth.mjs',sha256:handler.hashes.auth},
 {path:'functions/_shared/native-provider-budget.mjs',sha256:handler.hashes.budget}],functions:[]};
const source=sha(JSON.stringify(manifest)),functions=['collect-api','admin-api','collect-jobs'].map(slug=>({slug,id:randomUUID(),status:'ACTIVE',version:1,verify_jwt:false,ezbr_sha256:'a'.repeat(64)}));
const evidence={handler,intent:{sourceSha256:source,snapshot:{manifest}},deployment:{sourceSha256:source,functions},currentFunctions:structuredClone(functions),currentSource:source};
assert.equal(verifyDeploymentEvidence(evidence),source);
assert.equal(verifyDeploymentEvidence({...evidence,currentFunctions:evidence.currentFunctions.map(x=>({...x,version:x.version+1}))}),source);
for(const change of [
 {...evidence,currentSource:'b'.repeat(64)},
 {...evidence,deployment:{...evidence.deployment,sourceSha256:'b'.repeat(64)}},
 {...evidence,currentFunctions:evidence.currentFunctions.map((x,i)=>i?x:{...x,version:0})},
 {...evidence,currentFunctions:evidence.currentFunctions.map((x,i)=>i?x:{...x,version:2,ezbr_sha256:'b'.repeat(64)})},
 {...evidence,currentFunctions:evidence.currentFunctions.map((x,i)=>i?x:{...x,version:2,id:randomUUID()})},
 {...evidence,currentFunctions:evidence.currentFunctions.map((x,i)=>i?x:{...x,verify_jwt:true})},
 {...evidence,handler:{hashes:{...handler.hashes,auth:'b'.repeat(64)}}},
 {...evidence,intent:{...evidence.intent,snapshot:{manifest:{...manifest,project:'wrong'}}}},
])assert.throws(()=>verifyDeploymentEvidence(change));
const scheduleSha='df5ff3ec33e8e8d02c182072abd99e0c24705fb74f1f85514b46f9da9149300c';
assert.equal(qualifiedSchedule(undefined,undefined),'*/5 * * * *');
assert.equal(qualifiedSchedule(scheduleSha,scheduleSha),'* * * * *');
assert.throws(()=>qualifiedSchedule('0'.repeat(64),scheduleSha));
assert.throws(()=>qualifiedSchedule(scheduleSha,'0'.repeat(64)));
console.log(JSON.stringify({suite:'managed-jobs-key-evidence',checks:14,network_calls:0}));
