// Offline target/provenance refusals only. No PostgreSQL, Deno or provider starts.
import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,symlink,realpath,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {selectSchemaCase} from '../test_schema.mjs';
import {validateInvocation as stoppedInvocation} from './qualify-stopped-admission-native.mjs';
import {validateMemberHistoryTarget,validateMemberHistoryInvocation,validateMemberHistoryRunSpec,validateMemberHistoryReceipt,snapshotMemberHistorySources,verifyMemberHistorySources,captureCurrent14MemberHistory,captureBoundedHistoryChild,admitMemberHistoryOutput} from './current14-member-history.mjs';
const target='postgres://postgres:synthetic-only@127.0.0.1:55439/collect_fence_stopped_history_'+'1'.repeat(24)+'_test';
const environment={COLLECT_CI_SYNTHETIC:'true',COLLECT_MEMBER_HISTORY_DATABASE_URL:target,COLLECT_DENO:'/owned/deno',COLLECT_MEMBER_HISTORY_OUTPUT_DIR:'/owned/new-history-output'};
const sha=value=>createHash('sha256').update(value).digest('hex');

test('schema selector preserves the default suite and accepts only the named history case',()=>{
 assert.equal(selectSchemaCase([]),'schema');
 assert.equal(selectSchemaCase(['--case=current14-member-history']),'current14-member-history');
 for(const args of [['--case=legacy'],['--case=current14-member-history','--reset'],['--database='+target],['--case=current14-member-history ']])assert.throws(()=>selectSchemaCase(args));
});
for(const [label,value]of Object.entries({missing:undefined,managed:'postgres://postgres:synthetic-only@db.rrlduytparvsjfmegalh.supabase.co:5432/postgres',localhost:target.replace('127.0.0.1','localhost'),bootstrap:target.replace('postgres:synthetic-only','collect_test:synthetic-only'),oldDatabase:target.replace(/collect_fence_stopped_history_[a-f0-9]+_test/,'collect_old_test'),query:target+'?sslmode=disable',fragment:target+'#fragment',noPort:target.replace(':55439',''),invalidPort:target.replace(':55439',':65536'),controlPassword:target.replace('synthetic-only','bad%0Avalue'),emptyPassword:target.replace(':synthetic-only','')}))test('refuse non-owned history target: '+label,()=>{
 assert.throws(()=>validateMemberHistoryTarget(value),e=>e.captureCode==='EXACT_CURRENT14_LOOPBACK_TARGET_REQUIRED');
});
test('history capture requires explicit synthetic profile, Node24 and fixed paths',()=>{
 assert.equal(validateMemberHistoryInvocation(environment,'24.19.0').target.href,target);
 for(const value of [undefined,'false','TRUE'])assert.throws(()=>validateMemberHistoryInvocation({...environment,COLLECT_CI_SYNTHETIC:value},'24.19.0'),e=>e.captureCode==='EXPLICIT_SYNTHETIC_CI_REQUIRED');
 assert.throws(()=>validateMemberHistoryInvocation(environment,'22.0.0'),e=>e.captureCode==='NODE_24_REQUIRED');
 for(const key of ['COLLECT_DENO','COLLECT_MEMBER_HISTORY_OUTPUT_DIR'])for(const value of ['relative','/owned/../other','/owned/new\nline'])assert.throws(()=>validateMemberHistoryInvocation({...environment,[key]:value},'24.19.0'),e=>e.captureCode==='PHYSICAL_EXECUTABLE_AND_OUTPUT_REQUIRED');
});
test('execution spec provides the validated runtime URL and database bindings before driver import',()=>{
 const root=fileURLToPath(new URL('../../../',import.meta.url)).replace(/\/$/,'');
 const spec={format:'collect.current14.history.run-spec.v1',source:root,output:'/owned/history',url:target,port:55439};
 const result=validateMemberHistoryRunSpec(spec,'/owned/history/RUN-SPEC.private.json');
 assert.equal(result.target.href,target);assert.equal(result.name,'collect_fence_stopped_history_'+'1'.repeat(24)+'_test');
 for(const change of [{source:'/other-checkout'},{port:55440},{url:target.replace('127.0.0.1','remote.example')}])assert.throws(()=>validateMemberHistoryRunSpec({...spec,...change},'/owned/history/RUN-SPEC.private.json'));
 assert.throws(()=>validateMemberHistoryRunSpec(spec,'/other/RUN-SPEC.private.json'));
});
test('source capture binds the executing Dart money and signed-history part bodies',async()=>{
 const root=fileURLToPath(new URL('../../../',import.meta.url)).replace(/\/$/,'');
 const files=await snapshotMemberHistorySources(root),roles=new Set(files.map(value=>value.role));
 for(const role of ['collect_payment_models.dart','collect_payment_json.dart','collect_model_json_helpers.dart','collect_summary_json.dart','member_history_signed.dart','collect_profile_country_rules.dart'])assert(roles.has('lib/shared/models/'+role),role);
 assert(roles.has('lib/core/data/exact_json_values.dart'));
});
test('stopped-admission default remains closed and history allocation is an explicit extension',()=>{
 const env={COLLECT_CI_SYNTHETIC:'true',COLLECT_STOPPED_ADMISSION_ADMIN_DATABASE_URL:'postgres://collect_test:synthetic-only@127.0.0.1:55439/postgres'};
 const base={argv:['node','caller'],env,nodeVersion:'24.19.0'};
 assert.deepEqual(Object.keys(stoppedInvocation(base)).sort(),['module','url']);
 assert.throws(()=>stoppedInvocation({...base,argv:[...base.argv,'--with-member-history']}),e=>e.qualificationCode==='MEMBER_HISTORY_EXECUTABLE_AND_OUTPUT_REQUIRED');
 const extended=stoppedInvocation({...base,argv:[...base.argv,'--with-member-history'],env:{...env,COLLECT_DENO:'/owned/deno',COLLECT_MEMBER_HISTORY_OUTPUT_DIR:'/owned/history'}});
 assert.equal(extended.memberHistory,true);
 for(const args of [['--with-member-history','--reset'],['--with-member-history=1'],['--with-member-history ']])assert.throws(()=>stoppedInvocation({...base,argv:[...base.argv,...args]}),e=>e.qualificationCode==='NO_ARGUMENTS_ALLOWED');
});
test('source evidence rejects changed bytes and symlink substitution before runtime dispatch',async()=>{
 const root=await realpath(await mkdtemp(join(tmpdir(),'collect-history-source-')));
 try{
  const file=join(root,'source.mjs'),link=join(root,'substitute.mjs');await writeFile(file,'export const current=true;');
  const pin={path:file,sha256:sha('export const current=true;')};await verifyMemberHistorySources([pin]);
  await writeFile(file,'export const current=false;');await assert.rejects(verifyMemberHistorySources([pin]),e=>e.captureCode==='MEMBER_HISTORY_SOURCE_CHANGED');
  await symlink(file,link);await assert.rejects(verifyMemberHistorySources([{path:link,sha256:sha('export const current=false;')}]),e=>e.captureCode==='MEMBER_HISTORY_SOURCE_CHANGED');
 }finally{await rm(root,{recursive:true,force:true});}
});
test('existing output and symlink paths cannot be adopted as a new fixture artifact',async()=>{
 const root=await realpath(await mkdtemp(join(tmpdir(),'collect-history-output-')));
 try{await admitMemberHistoryOutput(join(root,'absent'));await assert.rejects(admitMemberHistoryOutput(root),e=>e.captureCode==='FRESH_MEMBER_HISTORY_OUTPUT_REQUIRED');const link=join(root,'link');await symlink(root,link);await assert.rejects(admitMemberHistoryOutput(link),e=>e.captureCode==='FRESH_MEMBER_HISTORY_OUTPUT_REQUIRED');}
 finally{await rm(root,{recursive:true,force:true});}
});
test('invalid capture target is refused before source, executable or output actions',async()=>{
 await assert.rejects(captureCurrent14MemberHistory({...environment,COLLECT_MEMBER_HISTORY_DATABASE_URL:'postgres://postgres:synthetic-only@remote.example/collect_history_test'}),e=>e.captureCode==='EXACT_CURRENT14_LOOPBACK_TARGET_REQUIRED');
});
test('result projection retains synthetic scope and cannot retire the six legacy gates',()=>{
 // A projection fixture checks refusal mechanics; it is not a native pass.
 const value={format:'collect.current14.actual-member-history-native.v1',status:'PASS',failure:null,cases:28,requests:266,SQL_statements:2159,source_parity_verified:true,packet:{path:'/owned/ACTUAL-HISTORY-PACKET.json',sha256:'a'.repeat(64)},actual_runtime_transactions_commit:true,fixture_data_preserved:true,provider_calls:0,hosted_acceptance:false,all_six_legacy_SQL_gates_closed:false};
 assert.equal(validateMemberHistoryReceipt(value),value);
 for(const delta of [{status:'FAIL'},{failure:{}},{provider_calls:1},{hosted_acceptance:true},{all_six_legacy_SQL_gates_closed:true},{source_parity_verified:false},{fixture_data_preserved:false},{actual_runtime_transactions_commit:false},{requests:0},{SQL_statements:-1},{packet:{path:'relative',sha256:'bad'}},{private_detail:'unexpected'}])assert.throws(()=>validateMemberHistoryReceipt({...value,...delta}));
});
test('unknown schema CLI flags fail before any database target is read',()=>{
 const script=new URL('../test_schema.mjs',import.meta.url);
 const child=spawnSync(process.execPath,[fileURLToPath(script),'--case=PRIVATE_ARGUMENT_NOT_ECHOED'],{encoding:'utf8',env:{PATH:process.env.PATH??''},timeout:10000});
 assert.notEqual(child.status,0);assert.match(child.stderr,/Only the default schema suite/);
 assert.doesNotMatch(child.stderr,/COLLECT_TEST_PG_URL|PRIVATE_ARGUMENT_NOT_ECHOED/);
});
test('capture subprocess success waits for actual close and preserves output digests',async()=>{
 const child=await captureBoundedHistoryChild(process.execPath,['-e','process.stdout.write("fixture-only");'],{env:{},deadlineMs:2000});
 assert.equal(child.metadata.code,0);assert.equal(child.metadata.reaped,true);assert.equal(child.metadata.expired,false);assert.equal(child.metadata.overflow,false);assert.equal(child.metadata.cancelled,false);assert.equal(child.stdout.toString(),'fixture-only');assert.equal(child.metadata.stdout_sha256,sha(child.stdout));
});
test('capture subprocess deadline terminates and reaps the owned harmless child',async()=>{
 const child=await captureBoundedHistoryChild(process.execPath,['-e','setInterval(()=>{},1000);'],{env:{},deadlineMs:50});
 assert.equal(child.metadata.expired,true);assert.equal(child.metadata.reaped,true);assert.notEqual(child.metadata.code,0);assert.equal(child.metadata.spawn_error,false);
});
test('capture subprocess output overflow is refused and the owned child is reaped',async()=>{
 const child=await captureBoundedHistoryChild(process.execPath,['-e','process.stdout.write(Buffer.alloc(131072,65));setInterval(()=>{},1000);'],{env:{},deadlineMs:2000});
 assert.equal(child.metadata.overflow,true);assert.equal(child.metadata.reaped,true);assert(child.metadata.stdout_bytes>65536);
});
