import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash,randomUUID} from 'node:crypto';
import {verifyDeploymentReadback} from './release-runtime.mjs';
import {desiredPublicConfig} from './runtime-plan.mjs';
import {withOwnedArchiveFixture} from '../managed-migration-next/synthetic-fixture.mjs';

const sha=x=>createHash('sha256').update(x).digest('hex');
const source='a'.repeat(64);
function fixture(){
 const functions=['collect-api','admin-api','collect-jobs'].map((slug,i)=>({slug,id:randomUUID(),status:'ACTIVE',version:i+1,
  verify_jwt:false,ezbr_sha256:String(i+1).repeat(64),entrypoint_path:`functions/${slug}/index.ts`}));
 const protectedNames=['DATA_ENCRYPTION_KEY','DATA_KEY_ID','DATA_DECRYPTION_KEYS_JSON','SESSION_ENCRYPTION_KEY','SESSION_KEY_ID',
  'COLLECT_JOB_SIGNING_KEY','BURIMUNSI_PIN_PEPPER_BASE64','BURIMUNSI_PIN_PEPPER_ID','BURIMUNSI_CURSOR_KEY_BASE64','BURIMUNSI_DEFAULT_STAFF_PIN'];
 const secrets=[...Object.entries(desiredPublicConfig(source)).map(([name,value])=>({name,value:sha(value)})),
  ...protectedNames.map(name=>({name,value:sha('fixture-'+name)}))];
 return {deployment:{sourceSha256:source,databaseHeld:true,functions},secretReceipt:{sourceSha256:source,defaultPinConfirmed:true},
  functions:structuredClone(functions),secrets,sourceSha:source};
}
test('requires exact deployed versions, bundle digests, config and default secret proof',()=>{
 const a=fixture();assert.equal(verifyDeploymentReadback(a).functions.length,3);
 const b=fixture();b.functions[0].version++;assert.throws(()=>verifyDeploymentReadback(b),/deployment_readback_changed/);
 const c=fixture();c.functions[1].ezbr_sha256='f'.repeat(64);assert.throws(()=>verifyDeploymentReadback(c),/deployment_readback_changed/);
 const d=fixture();d.functions[0].verify_jwt=true;assert.throws(()=>verifyDeploymentReadback(d),/deployment_readback_changed/);
 const e=fixture();e.secrets.find(x=>x.name==='BURIMUNSI_NATIVE_ENABLED').value=sha('false');assert.throws(()=>verifyDeploymentReadback(e),/runtime_config_changed/);
 const f=fixture();f.secretReceipt.defaultPinConfirmed=false;assert.throws(()=>verifyDeploymentReadback(f),/deployment_receipt_unverified/);
 const g=fixture();g.secrets=g.secrets.filter(x=>x.name!=='DATA_DECRYPTION_KEYS_JSON');assert.throws(()=>verifyDeploymentReadback(g),/runtime_secret_missing/);
});

test('original Postgres fence requires committed upgrade before separate release',{timeout:120000},async()=>{
 await withOwnedArchiveFixture(async({owner})=>{
  const old='b'.repeat(64),next='c'.repeat(64),drain=randomUUID(),upgrade=randomUUID(),release=randomUUID(),baseline='dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3';
  await owner.query(`INSERT INTO private.collect_fence_control(singleton,project_ref,baseline_manifest_sha256,source_sha256,epoch,mode,operation_id)
   VALUES(true,'rrlduytparvsjfmegalh',$1,$2,1,'fenced',$3)`,[baseline,old,drain]);
  await owner.query("INSERT INTO private.collect_fence_operations(operation_id,action,epoch,source_sha256) VALUES($1,'drain',1,$2)",[drain,old]);
  const args=[upgrade,drain,1,old,next,'d'.repeat(64),'e'.repeat(64),'f'.repeat(64)];
  await owner.query('BEGIN');
  await owner.query('SELECT private.collect_fence_upgrade_source_v3($1,$2,$3,$4,$5,$6,$7,$8)',args);
  await assert.rejects(()=>owner.query('SELECT private.collect_fence_release_v3($1,2,$2)',[release,next]),e=>e.code==='55000');
  await owner.query('ROLLBACK');
  assert.equal((await owner.query('SELECT source_sha256 FROM private.collect_fence_control WHERE singleton')).rows[0].source_sha256,old);
  await owner.query('SELECT private.collect_fence_upgrade_source_v3($1,$2,$3,$4,$5,$6,$7,$8)',args);
  const mid=(await owner.query('SELECT mode,epoch::int,source_sha256 FROM private.collect_fence_control WHERE singleton')).rows[0];
  assert.deepEqual(mid,{mode:'fenced',epoch:2,source_sha256:next});
  await owner.query('SELECT private.collect_fence_release_v3($1,2,$2)',[release,next]);
  const end=(await owner.query('SELECT mode,epoch::int,source_sha256 FROM private.collect_fence_control WHERE singleton')).rows[0];
  assert.deepEqual(end,{mode:'open',epoch:3,source_sha256:next});
 });
});
