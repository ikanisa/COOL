// Offline refusal/projection checks only; these do not establish native success.
import test from 'node:test';
import assert from 'node:assert/strict';
import {validateInvocation,validateReceipt,validateInstallReceipt,projectFailure} from './qualify-stopped-admission-native.mjs';
const env={COLLECT_CI_SYNTHETIC:'true',COLLECT_STOPPED_ADMISSION_ADMIN_DATABASE_URL:'postgres://collect_test:synthetic-only@127.0.0.1:55439/postgres'};
const invoke=delta=>validateInvocation({argv:['node','caller.mjs'],env:{...env,...delta},nodeVersion:'24.19.0'});
for(const target of [undefined,'https://example.com','postgres://collect_test:synthetic-only@localhost:55439/postgres','postgres://collect_test:synthetic-only@db.rrlduytparvsjfmegalh.supabase.co:5432/postgres','postgres://postgres:synthetic-only@127.0.0.1:55439/postgres','postgres://collect_test:synthetic-only@127.0.0.1:55439/collect_old_test',env.COLLECT_STOPPED_ADMISSION_ADMIN_DATABASE_URL+'?sslmode=disable',env.COLLECT_STOPPED_ADMISSION_ADMIN_DATABASE_URL+'#fragment',env.COLLECT_STOPPED_ADMISSION_ADMIN_DATABASE_URL.replace(':55439',':65536'),env.COLLECT_STOPPED_ADMISSION_ADMIN_DATABASE_URL.replace('synthetic-only','bad%0Avalue')])test('refuse unsafe target '+String(target),()=>{
 assert.throws(()=>invoke({COLLECT_STOPPED_ADMISSION_ADMIN_DATABASE_URL:target}),e=>e.qualificationCode==='EXACT_LOCAL_ADMIN_URL_REQUIRED');
});
test('require explicit synthetic execution, exact Node24 and no credential arguments',()=>{
 for(const flag of [undefined,'TRUE','false','1'])assert.throws(()=>invoke({COLLECT_CI_SYNTHETIC:flag}),e=>e.qualificationCode==='EXPLICIT_SYNTHETIC_CI_REQUIRED');
 assert.throws(()=>validateInvocation({argv:['node','caller','--db'],env,nodeVersion:'24.19.0'}),e=>e.qualificationCode==='NO_ARGUMENTS_ALLOWED');
 assert.throws(()=>validateInvocation({argv:['node','caller'],env,nodeVersion:'22.0.0'}),e=>e.qualificationCode==='NODE_24_REQUIRED');
 for(const module of ['relative/pg','/tmp/../pg','/tmp/pg\n'])assert.throws(()=>invoke({COLLECT_PG_MODULE:module}),e=>e.qualificationCode==='PHYSICAL_PG_MODULE_REQUIRED');
});
const native={status:'PASS',checks:43,fixture:'new_unique_loopback_only',raw_admission_unchanged:true,stopped_local_proofs:2,unquantified_unknown_obligations:2,counters_recovered:false,provider_calls:0,hosted_acceptance:false,sb29Satisfied:false};
test('stopped-lifecycle projection retains original unknown obligations and rejects overclaims',()=>{
 assert.equal(validateReceipt(native),native);
 assert.throws(()=>validateReceipt({...native,message:'private detail'}));
 for(const delta of [{checks:40},{checks:0},{raw_admission_unchanged:false},{stopped_local_proofs:1},{unquantified_unknown_obligations:0},{counters_recovered:true},{provider_calls:1},{hosted_acceptance:true},{sb29Satisfied:true}])assert.throws(()=>validateReceipt({...native,...delta}));
});
const install={status:'PASS',fixture:'new_unique_loopback_existing_orphan_install',checks:29,open_install_refused:true,uncommitted_quiesce_refused:true,actual_work_lease_blocked_install:true,committed_quiesce_install_passed:true,raw_admission_unchanged:true,proofs_created:0,provider_calls:0,hosted_acceptance:false,sb29Satisfied:false};
test('installation projection requires all genuine guard results and no fabricated proof',()=>{
 assert.equal(validateInstallReceipt(install),install);
 assert.throws(()=>validateInstallReceipt({...install,message:'private detail'}));
 for(const key of ['open_install_refused','uncommitted_quiesce_refused','actual_work_lease_blocked_install','committed_quiesce_install_passed','raw_admission_unchanged'])assert.throws(()=>validateInstallReceipt({...install,[key]:false}));
 for(const delta of [{checks:28},{proofs_created:1},{provider_calls:1},{hosted_acceptance:true},{sb29Satisfied:true}])assert.throws(()=>validateInstallReceipt({...install,...delta}));
});
test('native failures retain only bounded closed diagnostic fields',()=>{
 const safe={format:'collect.stopped-install.native-failure.v1',stage:'actual_current_retention_catalog',checks:23,sqlState:'42501'};
 assert.deepEqual(projectFailure(Buffer.from(JSON.stringify(safe))),safe);
 for(const value of [{...safe,message:'PRIVATE_TEST_DETAIL'},{...safe,stage:'PRIVATE_TEST_DETAIL'},{...safe,checks:-1},{...safe,sqlState:'PRIVATE_TEST_DETAIL'}])assert.equal(projectFailure(Buffer.from(JSON.stringify(value))),null);
 for(const value of [Buffer.from('raw PRIVATE_TEST_DETAIL'),Buffer.from([255]),Buffer.alloc(65537),Buffer.from(JSON.stringify(safe)+'\n'+JSON.stringify(safe))])assert.equal(projectFailure(value),null);
});
