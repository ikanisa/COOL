import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile,writeFile,readdir,stat} from 'node:fs/promises';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {makePlanSynthetic as makePlan,safeEnvironment,checkRuntimeArguments} from './capture-plan.mjs';
import {pin,syntheticPreflight,syntheticPlan,testDirectory} from './capture-fixtures.mjs';

test('each synthetic count receipt compiles a private source-bound request without dispatch',async t=>{
 const base=await testDirectory(t);
 for(const component of ['auth','storage']){
  const plan=await syntheticPlan(base,component),record=JSON.parse(await readFile(plan.plan_path,'utf8'));
  assert.equal(record.component,component);assert.equal(record.capture_dispatched,false);assert.equal(record.restore_dispatched,false);assert.equal(record.quiescence_proven,false);
  const request=JSON.parse(await readFile(join(base,'plan-'+component,'CAPTURE-REQUEST.json'),'utf8'));
  assert.equal(request.kind,'capture');assert.equal(request.body.read_only,true);assert.ok(request.body.query.startsWith('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;\n'));assert.ok(request.body.query.endsWith('\nROLLBACK;'));
  assert.deepEqual((await readdir(join(base,'plan-'+component))).sort(),['CAPTURE-REQUEST.json','PLAN.json']);
  for(const n of ['PLAN.json','CAPTURE-REQUEST.json'])assert.equal((await stat(join(base,'plan-'+component,n))).mode&0o777,0o600);
 }
});
test('changed result, counts, intent, pin and unsafe environment fail without creating a plan',async t=>{
 const base=await testDirectory(t),pre=await syntheticPreflight(base,'auth'),pins=await pin();
 const opt={component:'auth',resultPath:pre.result_path,resultSha256:pre.result_sha256,pinsSha256:pins,environment:{}};
 await assert.rejects(makePlan({...opt,resultSha256:'0'.repeat(64),outputDirectory:join(base,'bad-result')}),e=>e.code==='RESULT_CHANGED');
 await assert.rejects(makePlan({...opt,pinsSha256:'0'.repeat(64),outputDirectory:join(base,'bad-source')}),e=>e.code==='SOURCE_CHANGED');
 await assert.rejects(makePlan({...opt,environment:{HTTPS_PROXY:'https://example.invalid'},outputDirectory:join(base,'bad-env')}),e=>e.code==='UNSAFE_ENVIRONMENT');
 const countsPath=pre.counts_path,counts=await readFile(countsPath);await writeFile(countsPath,Buffer.concat([counts,Buffer.from(' ')]));
 await assert.rejects(makePlan({...opt,outputDirectory:join(base,'bad-counts')}),e=>e.code==='COUNTS_CHANGED');await writeFile(countsPath,counts);
 const intentPath=join(base,'counts-auth','INTENT.json'),intent=JSON.parse(await readFile(intentPath,'utf8'));intent.capture_dispatched=true;await writeFile(intentPath,JSON.stringify(intent));
 await assert.rejects(makePlan({...opt,outputDirectory:join(base,'bad-intent')}),e=>e.code==='INTENT_INVALID');
 assert.deepEqual(await readdir(base),['counts-auth']);
});
test('fresh plan directory cannot be reused or placed inside the count directory',async t=>{
 const base=await testDirectory(t),pre=await syntheticPreflight(base,'storage'),opt={component:'storage',resultPath:pre.result_path,resultSha256:pre.result_sha256,pinsSha256:await pin(),environment:{}};
 await makePlan({...opt,outputDirectory:join(base,'plan')});
 await assert.rejects(makePlan({...opt,outputDirectory:join(base,'plan')}));
 await assert.rejects(makePlan({...opt,outputDirectory:join(base,'counts-storage','nested')}),e=>e.code==='OUTPUT_PATH_INVALID');
});
test('alternate CA environment and nonempty runtime arguments are refused',()=>{
 for(const key of ['NODE_DEBUG','NODE_V8_COVERAGE','NODE_COMPILE_CACHE','NODE_USE_SYSTEM_CA','NODE_USE_OPENSSL_CA','NODE_USE_BUNDLED_CA',
  'NODE_EXTRA_CA_CERTS','SSL_CERT_FILE','SSLKEYLOGFILE','OPENSSL_CONF','OPENSSL_MODULES','LD_LIBRARY_PATH','DYLD_LIBRARY_PATH'])
  assert.throws(()=>safeEnvironment({[key]:'1'}),e=>e.code==='UNSAFE_ENVIRONMENT');
 for(const args of [['--use-system-ca'],['--require','node:util'],['--import','node:util'],['--no-node-snapshot']])assert.throws(()=>checkRuntimeArguments(args),e=>e.code==='UNSAFE_EXEC_ARGS');
 assert.doesNotThrow(()=>checkRuntimeArguments([]));
 const result=spawnSync('/Volumes/PRO-G40/Development/Node/bin/node',['--require','node:util',new URL('./capture-plan.mjs',import.meta.url).pathname],{env:{PATH:'/usr/bin:/bin'},encoding:'utf8'});
 assert.equal(result.status,1);assert.match(result.stderr,/UNSAFE_EXEC_ARGS/);
});
