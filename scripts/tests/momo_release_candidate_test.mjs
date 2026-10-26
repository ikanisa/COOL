import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,cp,readFile,writeFile,chmod,rm,symlink,realpath,access} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {fileURLToPath} from 'node:url';
import {createServer} from 'node:http';
import {DatabaseSync} from 'node:sqlite';
import {verifyCandidate,derivePrefixes,assertTrustedSourcePolicy,sqliteReferenceAuthorizer,hash,canonical} from '../cloudflare/momo_release_candidate.mjs';

const backend=fileURLToPath(new URL('../../deploy/platform-api/',import.meta.url));
async function actualPolicyRoles(){
 const inventoryPath=join(backend,'operations-manifest-momo15.json'),inventoryBytes=await readFile(inventoryPath),inventory=JSON.parse(inventoryBytes);
 return {'operations-manifest-momo15.json':{sha256:hash(inventoryBytes)},'scripts/operation_inventory.mjs':{sha256:hash(await readFile(join(backend,'scripts/operation_inventory.mjs')))},...Object.fromEntries(Object.entries(inventory.migrations_sha256).map(([n,sha256])=>['migrations/'+n,{sha256}]))};
}
// These safety tests are mandatory in normal Node/CI runs. Only the separate
// real compiled-artifact integration cohort below needs an explicit packet pin.
test('mandatory exact trusted source-only inventory/producer/migration admission',async()=>{assert.equal(assertTrustedSourcePolicy(await actualPolicyRoles()),true);});
test('mandatory untrusted inventory bytes refuse before executable source',async()=>{const roles=await actualPolicyRoles();roles['operations-manifest-momo15.json'].sha256=hash('untrusted inventory');assert.throws(()=>assertTrustedSourcePolicy(roles),/inventory bytes differ/);});
test('mandatory untrusted producer bytes refuse before execution',async()=>{const roles=await actualPolicyRoles();roles['scripts/operation_inventory.mjs'].sha256=hash('untrusted producer');assert.throws(()=>assertTrustedSourcePolicy(roles),/producer bytes differ/);});
test('mandatory untrusted migration digest refuses before SQL',async()=>{const roles=await actualPolicyRoles();roles['migrations/0015_momo_gateway_allocation.sql'].sha256=hash('ATTACH DATABASE');assert.throws(()=>assertTrustedSourcePolicy(roles),/exact trusted15 migration digests/);});
test('mandatory exact15 local in-memory derivation and every prefix',async()=>{const evidence=await derivePrefixes(backend,await actualPolicyRoles());assert.equal(Object.keys(evidence.prefixes).length,16);assert.equal(evidence.prefixes['15'].application_tables,94);assert.equal(evidence.prefixes['15'].role_definitions,67);assert.equal(evidence.target_upgrade_acceptance,false);});
test('mandatory SQLite authorizer blocks host writes/extensions/mutating pragmas',async()=>{
 const work=await mkdtemp(join(await realpath(tmpdir()),'collect-momo15-authorizer-')),canary=join(work,'escaped.sqlite'),db=new DatabaseSync(':memory:',{allowExtension:false});db.setAuthorizer(sqliteReferenceAuthorizer);
 try{for(const sql of ["ATTACH DATABASE '"+canary+"' AS escaped",'DETACH DATABASE escaped',"SELECT load_extension('/private/tmp/untrusted-extension')",'PRAGMA writable_schema=ON','PRAGMA user_version=9',"PRAGMA journal_mode='OFF'"])assert.throws(()=>db.exec(sql),/not authorized|authorization denied|no such database/);db.exec('PRAGMA foreign_keys=ON');assert.equal(db.prepare('PRAGMA integrity_check').get().integrity_check,'ok');await assert.rejects(access(canary),error=>error.code==='ENOENT');}finally{db.close();await rm(work,{recursive:true,force:true});}
});
test('mandatory CLI rejects deploy/migrate/executor options',async()=>{const cli=fileURLToPath(new URL('../cloudflare/momo_release_candidate.mjs',import.meta.url)),run=promisify(execFile);for(const args of [['deploy'],['migrate'],['verify','--packet','unused','--sha256',hash('unused'),'--execute','true']])await assert.rejects(run(process.execPath,[cli,...args]),error=>error.code===1&&/Use capture or verify|Unknown\/duplicate option/.test(error.stderr));});

const packet=process.env.COLLECT_MOMO15_PACKET,pin=process.env.COLLECT_MOMO15_SHA256;
// Actual qualification is explicit: a real pinned packet is supplied by its
// capture owner; no synthetic fixture is represented as a compiled candidate.
test('actual MoMo15 inert candidate qualification',{skip:!packet||!pin},async t=>{
 const work=await mkdtemp(join(await realpath(tmpdir()),'collect-momo15-negative-'));
 const base=JSON.parse(await readFile(join(packet,'candidate.json'),'utf8'));
 async function fixture(){const path=join(work,'case-'+Math.random().toString(16).slice(2));await cp(packet,path,{recursive:true,filter:p=>!p.split('/').at(-1).startsWith('._')});return path;}
 async function change(path,name,bytes){await chmod(join(path,name),0o600);await writeFile(join(path,name),bytes);}
 async function repin(path,edit){const manifest=JSON.parse(await readFile(join(path,'candidate.json'),'utf8'));edit(manifest);const raw=canonical(manifest)+'\n';await change(path,'candidate.json',raw);return hash(raw);}
 try{
  await t.test('exact captured71 roles/15-prefix/92-wire candidate verifies with no acceptance',async()=>{const result=await verifyCandidate({packet,sha256:pin});assert.equal(result.source_roles,71);assert.equal(result.migration_prefixes,16);assert.equal(result.application_tables,94);assert.ok(Object.values(result.acceptance).every(v=>v===false));});
  await t.test('missing independent pin refuses',async()=>{await assert.rejects(verifyCandidate({packet}),/external exact candidate SHA256/);});
  await t.test('external manifest pin refuses modified manifest',async()=>{const p=await fixture();await change(p,'candidate.json',JSON.stringify({...base,created_at:'changed'}));await assert.rejects(verifyCandidate({packet:p,sha256:pin}),/external SHA256/);});
  await t.test('omitted captured role refuses',async()=>{const p=await fixture();await rm(join(p,'source/src/index.js'));await assert.rejects(verifyCandidate({packet:p,sha256:pin}),/missing\/extra\/changed/);});
  await t.test('added source role refuses',async()=>{const p=await fixture();await writeFile(join(p,'source/src/unreviewed.js'),'export default 1;');await assert.rejects(verifyCandidate({packet:p,sha256:pin}),/missing\/extra\/changed/);});
  await t.test('bundle mutation refuses',async()=>{const p=await fixture();await change(p,'bundle/index.js','export default {};\n');await assert.rejects(verifyCandidate({packet:p,sha256:pin}),/missing\/extra\/changed/);});
  await t.test('source alias refuses even when contents match',async()=>{const p=await fixture(),target=join(p,'source/src/index.js');await rm(target);await symlink(join(packet,'source/src/index.js'),target);await assert.rejects(verifyCandidate({packet:p,sha256:pin}),/symlink/);});
  await t.test('packet root alias refuses',async()=>{const link=join(work,'alias');await symlink(packet,link);await assert.rejects(verifyCandidate({packet:link,sha256:pin}),/Aliases\/symlinks/);});
  await t.test('rebasing a promoted acceptance flag still refuses',async()=>{const p=await fixture(),digest=await repin(p,m=>m.acceptance.release_adoption=true);await assert.rejects(verifyCandidate({packet:p,sha256:digest}),/promoted acceptance/);});
  await t.test('rebasing inventory cardinality still refuses',async()=>{const p=await fixture(),name='source/operations-manifest-momo15.json',value=JSON.parse(await readFile(join(p,name),'utf8'));value.operations.pop();const bytes=canonical(value)+'\n';await change(p,name,bytes);const digest=await repin(p,m=>{m.files[name]={sha256:hash(bytes),bytes:Buffer.byteLength(bytes)};m.source_roles['operations-manifest-momo15.json']=m.files[name];m.backend_content_identity=hash(canonical({format:'collect.momo15.backend-content.v1',files:m.source_roles}));});await assert.rejects(verifyCandidate({packet:p,sha256:digest}),/Exact source-only MoMo15 inventory bytes differ/);});
  await t.test('rebasing an altered migration cannot bypass exact producer inventory',async()=>{const p=await fixture(),name='source/migrations/0015_momo_gateway_allocation.sql',bytes=(await readFile(join(p,name),'utf8'))+'\n-- changed\n';await change(p,name,bytes);const digest=await repin(p,m=>{m.files[name]={sha256:hash(bytes),bytes:Buffer.byteLength(bytes)};m.source_roles[name.slice(7)]=m.files[name];m.backend_content_identity=hash(canonical({format:'collect.momo15.backend-content.v1',files:m.source_roles}));});await assert.rejects(verifyCandidate({packet:p,sha256:digest}),/exact trusted15 migration digests/);});
  await t.test('source drift against current source is refused',async()=>{const p=join(work,'drift');await cp(join(packet,'source'),p,{recursive:true,filter:n=>!n.split('/').at(-1).startsWith('._')});await change(p,'src/index.js',(await readFile(join(p,'src/index.js'),'utf8'))+'\n// drift\n');await assert.rejects(verifyCandidate({packet,sha256:pin,backend:p}),/Current backend source drifted/);});
  await t.test('freshly repinned malicious pass-JSON producer executes neither file nor network canary',async()=>{
   let requests=0;const server=createServer((_req,res)=>{requests++;res.end('canary');});await new Promise(done=>server.listen(0,'127.0.0.1',done));
   const canary=join(work,'producer-executed'),url='http://127.0.0.1:'+server.address().port;
   try{const p=await fixture(),name='source/scripts/operation_inventory.mjs',bytes="import{writeFile}from'node:fs/promises';await writeFile("+JSON.stringify(canary)+",'executed');await fetch("+JSON.stringify(url)+");console.log(JSON.stringify({status:'pass',profile:'momo15_candidate'}));\n";await change(p,name,bytes);
    const inventoryName='source/operations-manifest-momo15.json',inventory=JSON.parse(await readFile(join(p,inventoryName),'utf8'));inventory.producer.sha256=hash(bytes);const inventoryBytes=canonical(inventory)+'\n';await change(p,inventoryName,inventoryBytes);
    const digest=await repin(p,m=>{for(const [n,b]of [[name,bytes],[inventoryName,inventoryBytes]]){m.files[n]={sha256:hash(b),bytes:Buffer.byteLength(b)};m.source_roles[n.slice(7)]=m.files[n];}m.backend_content_identity=hash(canonical({format:'collect.momo15.backend-content.v1',files:m.source_roles}));});
    await assert.rejects(verifyCandidate({packet:p,sha256:digest}),/Exact source-only MoMo15 inventory bytes differ|producer bytes differ/);await assert.rejects(access(canary),error=>error.code==='ENOENT');assert.equal(requests,0);
   }finally{await new Promise(done=>server.close(done));}
  });
  await t.test('freshly repinned malicious SQL cannot attach or create a host canary',async()=>{
   const p=await fixture(),canary=join(work,'sql-escaped.sqlite'),name='source/migrations/0015_momo_gateway_allocation.sql',bytes=(await readFile(join(p,name),'utf8'))+"\nATTACH DATABASE '"+canary+"' AS escaped;CREATE TABLE escaped.host_write(value TEXT);\n";await change(p,name,bytes);
   const inventoryName='source/operations-manifest-momo15.json',inventory=JSON.parse(await readFile(join(p,inventoryName),'utf8'));inventory.migrations_sha256['0015_momo_gateway_allocation.sql']=hash(bytes);const inventoryBytes=canonical(inventory)+'\n';await change(p,inventoryName,inventoryBytes);
   let forgedRoles;const digest=await repin(p,m=>{for(const [n,b]of [[name,bytes],[inventoryName,inventoryBytes]]){m.files[n]={sha256:hash(b),bytes:Buffer.byteLength(b)};m.source_roles[n.slice(7)]=m.files[n];}m.backend_content_identity=hash(canonical({format:'collect.momo15.backend-content.v1',files:m.source_roles}));forgedRoles=m.source_roles;});
   await assert.rejects(verifyCandidate({packet:p,sha256:digest}),/Exact source-only MoMo15 inventory bytes differ/);await assert.rejects(derivePrefixes(join(p,'source'),forgedRoles),/exact trusted15 migration digests/);await assert.rejects(access(canary),error=>error.code==='ENOENT');
  });
  await t.test('SQLite authorizer independently denies host attach, extensions and mutating pragmas',async()=>{
   const canary=join(work,'authorizer-escaped.sqlite'),db=new DatabaseSync(':memory:',{allowExtension:false});db.setAuthorizer(sqliteReferenceAuthorizer);
   try{for(const sql of ["ATTACH DATABASE '"+canary+"' AS escaped",'DETACH DATABASE escaped',"SELECT load_extension('/private/tmp/untrusted-extension')",'PRAGMA writable_schema=ON','PRAGMA user_version=9',"PRAGMA journal_mode='OFF'"])assert.throws(()=>db.exec(sql),/not authorized|authorization denied|no such database/);db.exec('PRAGMA foreign_keys=ON');assert.equal(db.prepare('PRAGMA integrity_check').get().integrity_check,'ok');await assert.rejects(access(canary),error=>error.code==='ENOENT');}finally{db.close();}
  });
  await t.test('CLI refuses transport actions and executor options',async()=>{const cli=fileURLToPath(new URL('../cloudflare/momo_release_candidate.mjs',import.meta.url)),run=promisify(execFile);for(const args of [['deploy'],['migrate'],['verify','--packet',packet,'--sha256',pin,'--execute','true']])await assert.rejects(run(process.execPath,[cli,...args]),error=>error.code===1&&/Use capture or verify|Unknown\/duplicate option/.test(error.stderr));});
 }finally{await rm(work,{recursive:true,force:true});}
});
