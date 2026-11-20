import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash,randomBytes,randomUUID} from 'node:crypto';
import {mkdtemp,mkdir,readFile,rm,unlink,writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {captureSynthetic,planDigest} from './core.mjs';
import {fixtureTransport} from './fixture.mjs';
import {captureStatus,verifyCapture} from './offline.mjs';
const sha=b=>createHash('sha256').update(b).digest('hex');
async function fixture(fn){const root=await mkdtemp('/private/tmp/collect-edge-capture-test-'),archive=join(root,'archive'),keys=join(root,'key');await mkdir(archive,{mode:0o700});await mkdir(keys,{mode:0o700});
 const pin=sha(await readFile(new URL('./LIVE-SOURCE-PINS.json',import.meta.url))),plan={format:'collect.edge-capture.plan.v2',scope:'synthetic',operation_id:randomUUID(),archive_dir:archive,key_dir:keys,token_path:null,source_pins_sha256:pin,deadline_ms:30000,fixture:'normal'};
 try{return await fn({root,archive,keys,plan,expectedPlanSha256:planDigest(plan)});}finally{await rm(root,{recursive:true,force:true});}}
async function capture(f){const x=fixtureTransport('normal',null);try{return await captureSynthetic({plan:f.plan,expectedPlanSha256:f.expectedPlanSha256,transport:x.transport,signal:null});}finally{for(const b of x.bodies)b.fill(0);}}
test('missing outcome stays unknown even when an authenticated archive exists',async()=>fixture(async f=>{
 await capture(f);const path=join(f.archive,'EDGE-CAPTURE-OUTCOME.json'),outcome=JSON.parse(await readFile(path,'utf8'));outcome.provider_read_attempted=true;await writeFile(path,JSON.stringify(outcome));
 assert.equal((await verifyCapture(f)).status,'capture_unconfirmed');await unlink(path);
 for(const read of [captureStatus,verifyCapture]){const r=await read(f);assert.equal(r.status,'capture_unconfirmed');assert.equal(r.retryAuthorized,false);}
}));
test('offline verification rejects tampered receipt and wrong key without returning content',async()=>fixture(async f=>{
 const result=await capture(f),good=await verifyCapture(f);assert.equal(good.status,'capture_verified_point_in_time');assert.equal(good.archive_sha256,result.archive_sha256);assert(!JSON.stringify(good).includes('synthetic-private-source'));
 const receiptPath=join(f.archive,'EDGE-CAPTURE-RESULT.json'),original=await readFile(receiptPath),receipt=JSON.parse(original);receipt.functions[0].version++;
 await writeFile(receiptPath,JSON.stringify(receipt));await assert.rejects(verifyCapture(f),/OFFLINE_VERIFICATION_UNAVAILABLE/);assert.equal((await captureStatus(f)).status,'capture_recorded_unverified');
 await writeFile(receiptPath,original);const keyPath=join(f.keys,f.plan.operation_id+'.key'),key=await readFile(keyPath),wrong=randomBytes(32);await writeFile(keyPath,wrong);
 await assert.rejects(verifyCapture(f),/OFFLINE_VERIFICATION_UNAVAILABLE/);await writeFile(keyPath,key);assert.equal((await verifyCapture(f)).status,'capture_verified_point_in_time');original.fill(0);key.fill(0);wrong.fill(0);
}));
