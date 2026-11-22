import test from 'node:test';import assert from 'node:assert/strict';import {randomBytes,randomUUID} from 'node:crypto';
import {sealRecoveryCapsule,openRecoveryCapsule} from './recovery-capsule.mjs';
import {openDatabase} from '/Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-16/burimunsi-cloud-preflight-001/object-custody-code-001/binary-codec.mjs';
test('key capsule is encrypted, authenticated and distinctly labelled',()=>{
 const key=randomBytes(32),plain=randomBytes(4096),op=randomUUID();
 const archive=sealRecoveryCapsule(plain,key,{project:'abcdefghijklmnopqrst',operationId:op,keyId:'old-data-key'});
 const opened=openRecoveryCapsule(archive,key);
 assert.equal(opened.header.payloadType,'migration-lineage-key-and-cutover-evidence');assert.equal(opened.header.operationId,op);
 assert.deepEqual(opened.plaintext,plain);assert.equal(archive.includes(plain.subarray(0,64)),false);
 assert.throws(()=>openDatabase(archive,key));opened.plaintext.fill(0);plain.fill(0);key.fill(0);
});
test('key capsule rejects wrong key, truncation and tampering',()=>{
 const key=randomBytes(32),wrong=randomBytes(32),plain=Buffer.from('private synthetic data');
 const archive=sealRecoveryCapsule(plain,key,{project:'abcdefghijklmnopqrst',operationId:randomUUID(),keyId:'old-data-key'});
 assert.throws(()=>openRecoveryCapsule(archive,wrong));assert.throws(()=>openRecoveryCapsule(archive.subarray(0,-1),key));
 const changed=Buffer.from(archive);changed[changed.length-20]^=1;assert.throws(()=>openRecoveryCapsule(changed,key));
 key.fill(0);wrong.fill(0);plain.fill(0);
});
