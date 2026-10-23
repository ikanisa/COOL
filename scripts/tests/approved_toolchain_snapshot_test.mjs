import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile,writeFile,mkdir,mkdtemp,copyFile} from 'node:fs/promises';
import {join,dirname} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {reviewedSupportPins,parseApprovedCommand,approvedCommand} from '../cloudflare/approved_toolchain.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url)),sha=raw=>createHash('sha256').update(raw).digest('hex');
const legacy={
 'scripts/cloudflare/atomic_d1_restore.mjs':'cfd27db9f87d3150f04b2a363bfaf0f5ee4515c463b7c9127fad10c51e1c5fb3',
 'scripts/cloudflare/platform_backup.mjs':'da4479894d2c5fa967d3ccd7e4b829e82a37cff9e8a265418ed79e45ce4cb708',
 'scripts/cloudflare/recovery_quarantine.mjs':'edf10e39d3df145ac3938fc9f6c2fbd37ab7500450d31ef8a8b2b332a73e74a1',
 'deploy/platform-api/src/identity_keys.js':'c0c9fbfb48b44c72c7192acd3853644349a000ba3e7fbf62fdc11037d5f6d4f7',
 'deploy/platform-api/src/core.js':'18ce95c133a4895d13475338089fb00c9ba4c9283ee72c7d4d6f88ae8ea8723e',
};
const old17={...legacy,'scripts/cloudflare/platform_backup.mjs':'bec0686c830eecc8c63a01ed4173113ff3d2fb752f975edb6f21942afad2d196','scripts/cloudflare/recovery_quarantine.mjs':'776712f3be7a3750b1747c6b553d49e1c2c19ae8b6d81654dde22b855c83f506'};
const expected={...old17,'scripts/cloudflare/platform_backup.mjs':'8ade1b0dffc1eac284e05f8df925543747ebf0beebc52799d0552c5f4aa1bd7f','scripts/cloudflare/atomic_d1_restore.mjs':'8d991daf660f46b4fa3a7c61987e45f95b4c9bce954ebd2093163ac777fa5827','scripts/cloudflare/sql_snapshot_import.mjs':'50d1dbdd95fc35fab6efb4226f0975e696629120a4f92639f2eb6588ce1dbbbc'};
const runtime={COLLECT_APPROVED_DEPENDENCY_ROOT:process.env.COLLECT_APPROVED_DEPENDENCY_ROOT,COLLECT_APPROVED_RUNTIME_MANIFEST:process.env.COLLECT_APPROVED_RUNTIME_MANIFEST};
const area=await mkdtemp(join(tmpdir(),'collect-snapshot-profile-'));
const config=process.env.COLLECT_SNAPSHOT_TEST_CONFIG??join(area,'wrangler.jsonc'),bundle=process.env.COLLECT_SNAPSHOT_TEST_BUNDLE??join(area,'worker.mjs');
if(!process.env.COLLECT_SNAPSHOT_TEST_CONFIG)await writeFile(config,JSON.stringify({name:'collect-local-profile-proof',compatibility_date:'2026-10-14'}),{mode:0o600});
if(!process.env.COLLECT_SNAPSHOT_TEST_BUNDLE)await writeFile(bundle,'export default {fetch(){return new Response("local profile proof")}};\n',{mode:0o600});
const args=(profile='auth17-snapshot-v2',action='migrate:remote')=>['check',action,'--support-profile',profile,'--config',config,...(action==='deploy'?['--bundle',bundle]:[])];
test('historical default support profile stays exact frozen and without the new helper',()=>{assert.deepEqual(reviewedSupportPins(),legacy);assert.ok(Object.isFrozen(reviewedSupportPins()));assert.equal(Object.hasOwn(reviewedSupportPins(),'scripts/cloudflare/sql_snapshot_import.mjs'),false);});
test('historical auth17-candidate-v1 profile stays exact frozen and distinct',()=>{assert.deepEqual(reviewedSupportPins('auth17-candidate-v1'),old17);assert.ok(Object.isFrozen(reviewedSupportPins('auth17-candidate-v1')));});
test('snapshot successor pins exactly six reviewed support bodies including the new parser-bound importer',async()=>{assert.deepEqual(reviewedSupportPins('auth17-snapshot-v2'),expected);assert.ok(Object.isFrozen(reviewedSupportPins('auth17-snapshot-v2')));for(const [name,pin]of Object.entries(expected))assert.equal(sha(await readFile(join(root,name))),pin);});
test('only explicit known profile selection is parsed and no bundle/config guard is weakened',()=>{const value=parseApprovedCommand(args());assert.equal(value.supportProfile,'auth17-snapshot-v2');assert.equal(value.checkOnly,true);assert.throws(()=>parseApprovedCommand(['check','deploy','--support-profile','auth17-snapshot-v2']),/explicit physical/);for(const unknown of['auth17-snapshot-v3','latest','',{},false])assert.throws(()=>reviewedSupportPins(unknown),/Unknown reviewed support profile/);});
// Portable CI registers the four source/selection contracts above. Reviewed-host
// runtime/artifact and source-tamper admission requires explicit acceptance mode.
if(process.env.COLLECT_SNAPSHOT_PROFILE_ACCEPTANCE==='1'){
test('current complete pinned runtime admits check-only migration plan under the successor profile without provider approval',async()=>{const p=await approvedCommand(args(),{...process.env,...runtime});assert.equal(p.source.support_profile,'auth17-snapshot-v2');assert.equal(p.check_only,true);assert.equal(p.runtime.entries,1653);assert.equal(p.provider_actions_executed,false);assert.equal(p.source_artifact_target_approval_supplied_by_guard,false);assert.deepEqual(Object.fromEntries(Object.entries(p.source.support_inputs).map(([n,v])=>[n,v.sha256])),expected);});
test('current actual sealed bundle is parsed as self-contained under the successor profile without publishing it',async()=>{const p=await approvedCommand(args('auth17-snapshot-v2','deploy'),{...process.env,...runtime});assert.equal(p.check_only,true);assert.equal(p.bundle.unresolved_imports,0);assert.equal(p.bundle.sha256,sha(await readFile(bundle)));assert.equal(p.config.sha256,sha(await readFile(config)));assert.equal(p.provider_actions_executed,false);});
for(const profile of[null,'auth17-candidate-v1'])test('successor utility bytes cannot enter historical '+String(profile)+' source admission',async()=>{const command=profile===null?['check','migrate:remote','--config',config]:args(profile);await assert.rejects(approvedCommand(command,{...process.env,...runtime}),/Reviewed toolchain support source differs/);});
for(const name of['scripts/cloudflare/platform_backup.mjs','scripts/cloudflare/atomic_d1_restore.mjs','scripts/cloudflare/sql_snapshot_import.mjs'])test('changed successor support role denies before runtime import or provider dispatch '+name,async()=>{const dir=await mkdtemp(join(area,'source-')),names=[...Object.keys(expected),'scripts/cloudflare/approved_toolchain.mjs','deploy/platform-api/package-lock.json','deploy/platform-api/package.json'];for(const n of names){const p=join(dir,n);await mkdir(dirname(p),{recursive:true,mode:0o700});await copyFile(join(root,n),p);}const p=join(dir,name);await writeFile(p,Buffer.concat([await readFile(p),Buffer.from('\n// unauthorized changed support bytes\n')]),{mode:0o600});const mod=await import(pathToFileURL(join(dir,'scripts/cloudflare/approved_toolchain.mjs')));await assert.rejects(mod.approvedCommand(args(),{...process.env,...runtime}),/Reviewed toolchain support source differs/);});

}
