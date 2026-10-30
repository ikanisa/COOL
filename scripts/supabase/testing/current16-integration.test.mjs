// Pure admission/provenance tests. No database, provider, Deno or scheduler starts.
import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,writeFile,symlink,readFile,rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {createHash} from 'node:crypto';
import {CURRENT16_ROOT,validateCurrent16Target,validateCurrent16Invocation,validateCurrent16RunSpec,admitCurrent16Output,
 current16OwnerProfile,current16Sources,current16RuntimeRoles,verifyCurrent16RoleInventory,verifyCurrent16Sources,validateCurrent16Receipt,removeCurrent16PrivateSpec,qualifyCurrent16} from './current16-integration.mjs';
const admin='postgres://collect_test:synthetic-only@127.0.0.1:55443/postgres';
const owner=admin.replace('collect_test:','postgres:');
const env={COLLECT_CI_SYNTHETIC:'true',COLLECT_CURRENT16_ADMIN_DATABASE_URL:admin,COLLECT_CURRENT16_OWNER_DATABASE_URL:owner,COLLECT_DENO:'/owned/deno',COLLECT_CURRENT16_OUTPUT_DIR:'/owned/output'};
const invocation=delta=>validateCurrent16Invocation({argv:['node','current16.mjs'],env:{...env,...delta},nodeVersion:'24.22.1'});
const code=name=>error=>error.qualificationCode===name;
for(const value of [undefined,'https://example.com','postgres://collect_test:synthetic@localhost:55443/postgres',admin.replace('127.0.0.1','db.rrlduytparvsjfmegalh.supabase.co'),admin.replace(':55443',':55441'),admin.replace('/postgres','/collect_existing_test'),admin+'?sslmode=disable',admin+'#fragment',admin.replace('synthetic-only','bad%0Avalue'),owner]){
 test('reject nonexclusive bootstrap URL '+String(value),()=>assert.throws(()=>invocation({COLLECT_CURRENT16_ADMIN_DATABASE_URL:value}),code('EXACT_CURRENT16_LOOPBACK_URL_REQUIRED')));
}
test('only explicit synthetic Node24, exact paths and zero CLI arguments are accepted',()=>{
 assert.equal(invocation({}).admin.hostname,'127.0.0.1');
 for(const flag of [undefined,'false','TRUE','1'])assert.throws(()=>invocation({COLLECT_CI_SYNTHETIC:flag}),code('EXPLICIT_SYNTHETIC_CI_REQUIRED'));
 assert.throws(()=>validateCurrent16Invocation({argv:['node','caller','--reset'],env,nodeVersion:'24.22.1'}),code('NO_ARGUMENTS_ALLOWED'));
 assert.throws(()=>validateCurrent16Invocation({argv:['node','caller'],env,nodeVersion:'22.0.0'}),code('NODE_24_REQUIRED'));
 for(const path of ['relative','/owned/../deno','/owned/deno\n'])for(const key of ['COLLECT_DENO','COLLECT_CURRENT16_OUTPUT_DIR'])assert.throws(()=>invocation({[key]:path}),code('PHYSICAL_CURRENT16_PATH_REQUIRED'));
 for(const module of ['relative/pg','/owned/../pg','/owned/pg\n'])assert.throws(()=>invocation({COLLECT_PG_MODULE:module}),code('PHYSICAL_PG_MODULE_REQUIRED'));
 assert.throws(()=>invocation({COLLECT_CURRENT16_OWNER_DATABASE_URL:owner.replace(':55443',':55439')}),code('MATCHING_CURRENT16_OWNER_REQUIRED'));
});
test('private execution specification binds exact source, output and generated database identity',()=>{
 const output='/owned/current16',target=new URL(owner);target.pathname='/collect_current16_integration_'+('a'.repeat(24))+'_test';const url=target.href;
 const spec={format:'collect.current16.run-spec.v1',source:CURRENT16_ROOT,output,inputs:output+'/INPUTS.json',inputs_sha256:'b'.repeat(64),source_sha256:'c'.repeat(64),url};
 assert.equal(validateCurrent16RunSpec(spec,output+'/RUN-SPEC.private.json').pathname,'/collect_current16_integration_'+('a'.repeat(24))+'_test');
 for(const delta of [{format:'collect.current14.history.run-spec.v1'},{source:'/foreign'},{inputs:'/elsewhere/INPUTS.json'},{inputs_sha256:'bad'},{source_sha256:'bad'},{extra:true}])assert.throws(()=>validateCurrent16RunSpec({...spec,...delta},output+'/RUN-SPEC.private.json'));
 for(const name of ['collect_current16_integration_test','collect_current16_integration_aaaa_test','collect_notification_delivery_test','postgres']){const wrong=new URL(owner);wrong.pathname='/'+name;assert.throws(()=>validateCurrent16Target(wrong.href,{owner:true,database:true}));}
 assert.throws(()=>validateCurrent16RunSpec(spec,'/elsewhere/RUN-SPEC.private.json'));
});
test('owner profile permits only absent/restricted or the exact observed normal owner',()=>{
 const restricted={rolcanlogin:false,rolsuper:false,rolinherit:false,rolcreaterole:false,rolcreatedb:false,rolbypassrls:false,rolreplication:false};
 assert.equal(current16OwnerProfile(undefined),'absent');assert.equal(current16OwnerProfile(restricted),'restricted');
 const normal={...restricted,rolcanlogin:true,rolcreaterole:true};assert.equal(current16OwnerProfile(normal),'normal');
 for(const key of ['rolsuper','rolinherit','rolcreatedb','rolbypassrls','rolreplication'])assert.throws(()=>current16OwnerProfile({...normal,[key]:true}),code('EXACT_CURRENT16_OWNER_PROFILE_REQUIRED'));
 assert.throws(()=>current16OwnerProfile({...restricted,rolcanlogin:true}),code('EXACT_CURRENT16_OWNER_PROFILE_REQUIRED'));
 assert.throws(()=>current16OwnerProfile({}),code('EXACT_CURRENT16_OWNER_PROFILE_REQUIRED'));
});
test('output refuses an existing directory, file, dangling link and redirected parent',async()=>{
 const root=await mkdtemp(join(tmpdir(),'collect-current16-refusal-'));
 try{
  await admitCurrent16Output(join(root,'fresh'));
  await mkdir(join(root,'existing'));await writeFile(join(root,'file'),'retained');await symlink(join(root,'missing'),join(root,'dangling'));
  for(const item of ['existing','file','dangling'])await assert.rejects(admitCurrent16Output(join(root,item)),code('FRESH_CURRENT16_OUTPUT_REQUIRED'));
  await symlink(root,join(root,'redirect'));await assert.rejects(admitCurrent16Output(join(root,'redirect','child')),code('PHYSICAL_CURRENT16_OUTPUT_PARENT_REQUIRED'));
 }finally{await rm(root,{recursive:true,force:true});}
});
test('source manifest rejects changed bytes, path escapes, duplicates and symlink replacement',async()=>{
 const root=await mkdtemp(join(tmpdir(),'collect-current16-source-')),file=join(root,'source.js'),bytes='export const verified=true;';
 try{
  await writeFile(file,bytes);const item={role:'source.js',bytes:Buffer.byteLength(bytes),sha256:createHash('sha256').update(bytes).digest('hex')};
  await verifyCurrent16Sources([item],root);
  await assert.rejects(verifyCurrent16Sources([item,item],root),code('CURRENT16_SOURCE_MANIFEST_REQUIRED'));
  await assert.rejects(verifyCurrent16Sources([{...item,role:'../source.js'}],root),code('PHYSICAL_CURRENT16_SOURCE_REQUIRED'));
  await symlink(file,join(root,'link.js'));await assert.rejects(verifyCurrent16Sources([{...item,role:'link.js'}],root),code('PHYSICAL_CURRENT16_SOURCE_REQUIRED'));
  await writeFile(file,'export const verified=false;');await assert.rejects(verifyCurrent16Sources([item],root),code('CURRENT16_SOURCE_CHANGED'));
 }finally{await rm(root,{recursive:true,force:true});}
});
test('actual source selection includes complete16, native consumer and both lock files',async()=>{
 const files=await current16Sources();await verifyCurrent16Sources(files);const roles=new Set(files.map(item=>item.role));
 assert.equal(files.filter(item=>item.role.startsWith('supabase/migrations/')).length,16);
 for(const role of ['scripts/supabase/testing/current16-runtime.ts','scripts/supabase/testing/current16-integration.mjs','supabase/functions/_shared/domain/notification_delivery.js','supabase/functions/_shared/domain/client_diagnostics.js','supabase/functions/_shared/domain/admin_accounts_legacy.js','supabase/functions/_shared/private-retention.js','supabase/functions/_shared/member-realtime-retention.js','supabase/functions/deno.lock','scripts/supabase/package-lock.json'])assert(roles.has(role),role);
});
test('runtime inventory refuses linked sources and detects added or removed file roles',async()=>{
 const root=await mkdtemp(join(tmpdir(),'collect-current16-inventory-')),directory=join(root,'supabase/functions');
 try{
  await mkdir(directory,{recursive:true});await writeFile(join(directory,'one.js'),'export const one=true;');
  const roles=await current16RuntimeRoles(root);assert.deepEqual(roles,['supabase/functions/one.js']);
  const files=roles.map(role=>({role}));verifyCurrent16RoleInventory(files,roles);
  await writeFile(join(directory,'two.js'),'export const two=true;');assert.throws(()=>verifyCurrent16RoleInventory(files,[...roles,'supabase/functions/two.js']),code('CURRENT16_SOURCE_INVENTORY_CHANGED'));
  assert.throws(()=>verifyCurrent16RoleInventory(files,[]),code('CURRENT16_SOURCE_INVENTORY_CHANGED'));
  await symlink(join(directory,'one.js'),join(directory,'linked.js'));await assert.rejects(current16RuntimeRoles(root),code('PHYSICAL_CURRENT16_SOURCE_REQUIRED'));
  await rm(join(directory,'linked.js'));await symlink(directory,join(directory,'linked-directory'));await assert.rejects(current16RuntimeRoles(root),code('PHYSICAL_CURRENT16_SOURCE_REQUIRED'));
 }finally{await rm(root,{recursive:true,force:true});}
});
test('receipt validation cannot fabricate hosted, legacy, financial or provider acceptance',()=>{
 const value={format:'collect.current16.native.v1',status:'PASS',failure:null,cases:16,migration_count:16,source_sha256:'a'.repeat(64),normal_owner:true,normal_runtime:true,fixture_preserved:true,external_provider_calls:0,synthetic_provider_calls:5,hosted_acceptance:false,legacy_sql_gates_closed:false,financial_posting_acceptance:false};
 assert.equal(validateCurrent16Receipt(value),value);
 for(const delta of [{status:'FAIL'},{failure:{}},{cases:0},{cases:15},{cases:17},{migration_count:14},{source_sha256:'bad'},{normal_owner:false},{normal_runtime:false},{fixture_preserved:false},{external_provider_calls:1},{synthetic_provider_calls:0},{hosted_acceptance:true},{legacy_sql_gates_closed:true},{financial_posting_acceptance:true},{private_detail:'unexpected'}])assert.throws(()=>validateCurrent16Receipt({...value,...delta}));
});
test('bad invocation returns a bounded failure before output or dependency/database access',async()=>{
 const value=await qualifyCurrent16({...env,COLLECT_CI_SYNTHETIC:'false'},['node','current16.mjs']);
 assert.equal(value.status,'UNCONFIRMED');assert.equal(value.failure.code,'EXPLICIT_SYNTHETIC_CI_REQUIRED');assert.equal(value.database,null);assert.equal(value.output,null);assert.equal(value.provider_calls,0);assert.equal(value.reset_or_drop,false);
});
test('private specification cleanup requires observed absence, not an acknowledged no-op',async()=>{
 const root=await mkdtemp(join(tmpdir(),'collect-current16-cleanup-')),path=join(root,'RUN-SPEC.private.json');
 try{
  await writeFile(path,'synthetic-only');
  await assert.rejects(removeCurrent16PrivateSpec(path,{remove:async()=>{}}),code('CURRENT16_PRIVATE_SPEC_CLEANUP_UNCONFIRMED'));
  assert.equal(await readFile(path,'utf8'),'synthetic-only');
  assert.equal(await removeCurrent16PrivateSpec(path),true);
  await assert.rejects(readFile(path),error=>error.code==='ENOENT');
  assert.equal(await removeCurrent16PrivateSpec(path),true);
  await assert.rejects(removeCurrent16PrivateSpec(path,{inspect:async()=>{throw Object.assign(new Error('synthetic inspection denial'),{code:'EACCES'});}}),code('CURRENT16_PRIVATE_SPEC_CLEANUP_UNCONFIRMED'));
  await assert.rejects(removeCurrent16PrivateSpec(path,{remove:async()=>{throw Object.assign(new Error('synthetic removal denial'),{code:'EACCES'});}}),code('CURRENT16_PRIVATE_SPEC_CLEANUP_UNCONFIRMED'));
 }finally{await rm(root,{recursive:true,force:true});}
});
