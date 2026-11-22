import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {captureManagedArchive,applyManagedArchive,reconcileManagedArchive,archivePlanDigest} from './operator.mjs';
const cli=new URL('./supervisor.mjs',import.meta.url),secret='fixture-password-never-print';
const manifest=createHash('sha256').update(readFileSync(new URL('./SOURCE-PINS.json',import.meta.url))).digest('hex');
const request={format:'collect.managed-archive-operator.v1',action:'capture',password:secret,timeoutMs:1000};
const code=c=>e=>e?.archiveCode===c;
async function launch(raw,{env={},signal=false}={}){
 const child=spawn(process.execPath,[cli.pathname,manifest],{env:{PATH:'/usr/bin:/bin',LC_ALL:'C',...env},stdio:['pipe','pipe','pipe']});
 let out='',err='';child.stdout.on('data',b=>out+=b);child.stderr.on('data',b=>err+=b);child.stdin.on('error',()=>{});
 const done=new Promise((resolve,reject)=>{child.once('error',reject);child.once('close',(exit,sig)=>resolve({exit,sig,out,err}));});
 if(raw!==null)child.stdin.end(raw);else if(signal)setTimeout(()=>child.kill('SIGTERM'),150);
 const r=await done;assert.equal((r.out+r.err).includes(secret),false);return {...r,body:JSON.parse(r.out)};
}

test('managed apply and reconciliation refuse before reading secrets or opening connections',async()=>{
 let touched=false;const o={plan:{reviewedPlanSha256:'a'.repeat(64)},get secret(){touched=true;return secret;}};
 await assert.rejects(applyManagedArchive(o),code('MANAGED_APPLY_UNQUALIFIED'));
 await assert.rejects(reconcileManagedArchive(o),code('MANAGED_APPLY_UNQUALIFIED'));assert.equal(touched,false);
 await assert.rejects(captureManagedArchive({secret:'bad\npassword',implementationManifestSha256:manifest}),code('PRIVATE_INPUT_REFUSED'));
});
test('reviewed plan digest binds source, preimage, admissions and the external-evidence reference',()=>{
 const p={preimageSha256:'a'.repeat(64),admissions:{count:1,sha:'b'.repeat(64)},exclusionEvidenceSha256:'c'.repeat(64),implementationManifestSha256:manifest};
 assert.notEqual(archivePlanDigest(p),archivePlanDigest({...p,exclusionEvidenceSha256:'d'.repeat(64)}));
 assert.notEqual(archivePlanDigest(p),archivePlanDigest({...p,admissions:{...p.admissions,count:2}}));
 assert.notEqual(archivePlanDigest(p),archivePlanDigest({...p,implementationManifestSha256:'f'.repeat(64)}));
});
test('private-pipe CLI rejects managed apply without dispatch and does not expose the credential',async()=>{
 const v={...request,action:'apply',journalRoot:'/synthetic/not-used',plan:{}};const r=await launch(JSON.stringify(v));
 assert.equal(r.exit,1);assert.equal(r.body.code,'MANAGED_APPLY_UNQUALIFIED');assert.equal(r.err,'');
});
test('duplicate keys, oversized input and environment overrides are refused',async()=>{
 for(const raw of ['{"x":1,"x":2}','x'.repeat(32769)]){const r=await launch(raw);assert.equal(r.exit,1);assert.equal(r.body.code,'PRIVATE_INPUT_REFUSED');}
 const r=await launch(JSON.stringify(request),{env:{PGHOST:'fixture-not-used'}});assert.equal(r.exit,1);assert.equal(r.body.code,'PRIVATE_INPUT_REFUSED');
});
test('interruption while the private pipe remains open is non-success',async()=>{
 const r=await launch(null,{signal:true});assert.equal(r.exit,1);assert.equal(r.body.status,'observation_interrupted');
});
