#!/usr/bin/env node
// Inert source/bundle custody for the separate MoMo15 candidate. No transport,
// migration executor, secret reader, approval writer or deployment is provided.
import {createHash} from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {readFile,readdir,lstat,realpath,mkdir,writeFile} from 'node:fs/promises';
import {resolve,join,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {DatabaseSync,constants as sqlite} from 'node:sqlite';

const run=promisify(execFile), SELF=fileURLToPath(import.meta.url), TEST=fileURLToPath(new URL('../tests/momo_release_candidate_test.mjs',import.meta.url));
const FORMAT='collect.momo15.inert-release-candidate.v1';
const SHA=/^[a-f0-9]{64}$/;
const EXTRAS=['operations-manifest.json','operations-manifest-momo15.json','package.json','package-lock.json','scripts/operation_inventory.mjs','wrangler.jsonc'];
const ARTIFACTS=['README.md','index.js','index.js.map'];
const PINS={wrangler:'4.151.0',miniflare:'5.20261012.0-beta',esbuild:'0.28.2'};
// These identify the observed source-only candidate, not an approval. Generic
// verification must never execute packet-supplied JavaScript or arbitrary SQL.
const INVENTORY_SHA256='ad11e18f723b8f0bf9bf6c98aa9b59fb71b55629cedc45ac42502112730dc258';
const PRODUCER_SHA256='813974f3debc867c7e8cc1d188feadae2f99fecc7426a8ff1f55de3d90dc2cdd';
const MIGRATIONS=Object.freeze({
 '0001_core.sql':'299b0358d2545a6bbc3f6dc004eadb19168ba9d72131368d0e814165ab6b6455',
 '0002_auth.sql':'2106f1db68d8bd21a540c747079da4df032842ae42f38979be7f687e8af0b2a7',
 '0003_mutation_guards.sql':'c1a4aa837663235af26b41977a531db33e9c61b18006ca167cb7eca486562744',
 '0004_privacy.sql':'e7ba2d670e3620e7c4042f6291fa62c83407df7270987d8df5ac6431e8766ef3',
 '0005_ingestion.sql':'b8974163e228cbc776ae88378c7fb3aece26b560841e2f7f76b7a53f254c75f7',
 '0006_admin_accounts.sql':'ed56c5d5da367cccbc877848ffa0cbdb418a5cb6ef58a443318d2b6b7d794ba0',
 '0007_admin_bridge.sql':'9668f1394a24dc18c75eed61d98f24c598dc8b763103c3144fef25988e0ef3b2',
 '0008_receipt_capture.sql':'247771ccb826bb48e894dc1de703ce1cb0706c18ece1620557447faa673449fd',
 '0009_operator_notes.sql':'e7ee374a172bb818c0a382e1e94fdc467f776f05bc31789d1215484d4fbce970',
 '0010_privacy_retention.sql':'94d7ec5146a4ef3e4721cb185a4700edea76c3e72e1cf992dd9fcb2d2e1571d2',
 '0011_auth_identity_keys.sql':'7e315ad76f45a6e5735d5ee42e7ae94f931e413de37b329a009f31ce9027e8f0',
 '0012_notification_operator.sql':'f6bfc6603505b8a29338d845707b3347c8c767d230f41f8347a1979d4c70bac7',
 '0013_sms_receipt_metadata_read.sql':'724f94ab29413b6e1e69c25678078f1e3161d8b0b7bcfe3cd20b1fd25cbc146b',
 '0014_momo_pipeline.sql':'b31e0590ad4d0b5b2e6acf3c6c069b84ec1cbe8d003eb69f7c5d5f306a3a63d6',
 '0015_momo_gateway_allocation.sql':'c84e3ea9330c0506781072173af7f5b9a7324017943ca58a967e399df515c422',
});
const PROVENANCE_SCOPE='Reuses the observed trusted current68-input dry-run artifact/snapshot; no fresh compilation, malicious-input attestation or independent semantic equivalence of arbitrary supplied JavaScript is claimed. The external manifest pin protects exact custody after capture.';
const TOOLCHAIN_SCOPE='Bounded installed dependency entrypoints/binary, exact package metadata/lock and Node executable; the complete installed transitive dependency tree is not hashed or independently qualified by this packet.';
const QUALIFIERS=['tooling/cloudflare/momo_release_candidate.mjs','tooling/tests/momo_release_candidate_test.mjs'];
const NO_ACCEPTANCE=Object.freeze({owner_approval:false,independent_review:false,source_admission:false,release_adoption:false,target_migration:false,deployment:false,provider_accuracy:false,physical_gateway:false,production_acceptance:false,recovery_acceptance:false});
const GATES=Object.freeze([
 'Independently review and admit this exact packet digest; historical candidate11/API16 approval is not inherited.',
 'Independently qualify the complete installed transitive build/runtime inputs; this packet binds entrypoints/binary plus the exact lock only.',
 'Qualify recovery/quarantine for exact complete15 data and device credentials, then approve the exact recovery evidence separately.',
 'Read back the intended target schema/data/grants, review the additive13-to15 upgrade and approve a bounded migration/deployment plan.',
 'Adopt a separately reviewed runtime BUILD_SOURCE_ID/configuration; the captured configuration retains its old label unchanged.',
 'Verify real receiving account/provider receipt profiles and physical gateway lifecycle; validate actual AI accuracy and processing consent.',
 'Independently read back deployed Worker/configuration/AI/cron/migrations and exercise member/Admin/gateway journeys before production acceptance.',
]);
const need=(condition,message)=>{if(!condition)throw new Error(message);};
export const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
export function canonical(value){
 if(value===null||typeof value!=='object')return JSON.stringify(value);
 if(Array.isArray(value))return '['+value.map(canonical).join(',')+']';
 return '{'+Object.keys(value).sort().map(k=>JSON.stringify(k)+':'+canonical(value[k])).join(',')+'}';
}
const same=(a,b)=>canonical(a)===canonical(b);
const rawJSON=value=>Buffer.from(canonical(value)+'\n');
function safe(name){need(typeof name==='string'&&!name.startsWith('/')&&name.split('/').every(p=>/^[A-Za-z0-9_.-]+$/.test(p)&&p!=='.'&&p!=='..'&&!p.startsWith('._')),'Unsafe role path');return name;}
async function physical(path){
 const absolute=resolve(path),s=await lstat(absolute);need(!s.isSymbolicLink()&&await realpath(absolute)===absolute,'Aliases/symlinks are not accepted: '+absolute);return absolute;
}
async function read(path,max=12*1024*1024){
 path=await physical(path);const s=await lstat(path);need(s.isFile()&&s.size<=max,'Regular bounded file required: '+path);
 const bytes=await readFile(path);need(bytes.length===s.size,'File changed while reading: '+path);return {bytes,sha256:hash(bytes),size:bytes.length};
}
async function json(path){return JSON.parse((await read(path)).bytes.toString('utf8'));}
async function files(root){
 root=await physical(root);const names=[];
 async function walk(directory,prefix=''){
  for(const e of (await readdir(directory,{withFileTypes:true})).sort((a,b)=>a.name.localeCompare(b.name,'en'))){
   if(e.name.startsWith('._'))continue;const name=safe(prefix+e.name),path=join(directory,e.name);
   need(!e.isSymbolicLink(),'Source tree symlink: '+name);
   if(e.isDirectory())await walk(path,name+'/');else{need(e.isFile(),'Nonregular source role: '+name);await physical(path);names.push(name);}
  }
 }
 await walk(root);return names.sort();
}
async function records(root,names,max){const result={};for(const name of [...names].sort()){const f=await read(join(root,safe(name)),max);result[name]={sha256:f.sha256,bytes:f.size};}return result;}
async function sourceRoles(root){
 const sources=(await files(join(root,'src'))).map(n=>'src/'+n),migrations=(await files(join(root,'migrations'))).map(n=>'migrations/'+n);
 need(sources.length===50,'MoMo15 requires exactly50 backend source roles');
 need(migrations.length===15&&migrations.every((n,i)=>new RegExp('^migrations/'+String(i+1).padStart(4,'0')+'_[a-z0-9_]+\\.sql$').test(n)),'MoMo15 requires the complete ordered15 migration prefix');
 return records(root,[...sources,...migrations,...EXTRAS]);
}
export function assertTrustedSourcePolicy(roles){
 need(roles['operations-manifest-momo15.json'].sha256===INVENTORY_SHA256,'Exact source-only MoMo15 inventory bytes differ');
 need(roles['scripts/operation_inventory.mjs'].sha256===PRODUCER_SHA256,'Exact source-only inventory producer bytes differ');
 const migrations=Object.fromEntries(Object.entries(roles).filter(([n])=>n.startsWith('migrations/')).map(([n,r])=>[n.slice(11),r.sha256]));
 need(same(migrations,MIGRATIONS),'Local reference accepts only the exact trusted15 migration digests');return true;
}
async function validateInventory(root,roles,{runTrustedProducer=false}={}){
 assertTrustedSourcePolicy(roles);
 const inventory=await json(join(root,'operations-manifest-momo15.json')),config=await json(join(root,'wrangler.jsonc'));
 need(inventory.profile==='momo15_candidate'&&inventory.metadata_is_source_only===true&&inventory.metadata_grants_authority===false&&inventory.rollout?.approval_supplied===false,'Inventory cannot confer acceptance');
 need(inventory.operations?.length===92&&inventory.route_families?.length===30,'Wrong operation/family inventory');
 need(same(inventory.runtime_boundaries?.handler_exports,['fetch','scheduled'])&&same(inventory.runtime_boundaries.configured_crons,['* * * * *'])&&inventory.runtime_boundaries.configured_ai_binding==='AI','Wrong scheduled/AI inventory');
 need(same(config.triggers?.crons,['* * * * *'])&&config.ai?.binding==='AI'&&config.main==='src/index.js','Wrong captured runtime configuration');
 need(inventory.configuration_sha256===roles['wrangler.jsonc'].sha256,'Inventory/configuration digest mismatch');
 const src=Object.fromEntries(Object.entries(roles).filter(([n])=>n.startsWith('src/')).map(([n,r])=>[n.slice(4),r.sha256]));
 const migration=Object.fromEntries(Object.entries(roles).filter(([n])=>n.startsWith('migrations/')).map(([n,r])=>[n.slice(11),r.sha256]));
 need(same(inventory.source_sha256,src)&&same(inventory.migrations_sha256,migration),'Inventory/source/migration role mismatch');
 need(inventory.producer?.path==='scripts/operation_inventory.mjs'&&inventory.producer.sha256===roles['scripts/operation_inventory.mjs'].sha256,'Inventory producer mismatch');
 // Capture can check the known canonical producer after the exact trusted
 // inventory/source digests above match. Generic packet verification never
 // imports or launches any captured JavaScript, regardless of the supplied pin.
 if(runTrustedProducer){const checked=await run(process.execPath,[join(root,'scripts/operation_inventory.mjs'),'--check'],{cwd:root,env:{PATH:dirname(process.execPath),TZ:'UTC',NO_COLOR:'1'},maxBuffer:1024*1024});const result=JSON.parse(checked.stdout.trim());need(result.status==='pass'&&result.profile==='momo15_candidate','Inventory regeneration failed');}
 return {profile:inventory.profile,operation_wires:92,route_families:30,handler_exports:['fetch','scheduled'],cron:['* * * * *'],ai_binding:'AI',provider_or_hosted_acceptance:false,runtime_build_source_id:config.vars?.BUILD_SOURCE_ID??null};
}
function typed(value){
 if(value===null)return ['null'];if(value instanceof Uint8Array)return ['blob',Buffer.from(value).toString('hex')];
 if(typeof value==='bigint')return ['integer',value.toString()];
 if(typeof value==='number'){need(Number.isFinite(value)&&(!Number.isInteger(value)||Number.isSafeInteger(value)),'Imprecise SQLite value');return [Number.isInteger(value)?'integer':'real',Object.is(value,-0)?'-0':String(value)];}
 need(typeof value==='string','Unsupported SQLite value');return ['text',value];
}
const identifier=name=>{need(/^[a-z][a-z0-9_]*$/.test(name),'Unsafe SQLite identifier');return '"'+name+'"';};
function fingerprint(db){
 const schema=db.prepare("SELECT type,name,tbl_name,sql FROM sqlite_schema WHERE sql IS NOT NULL AND name NOT GLOB 'sqlite_*' ORDER BY type,name").all();
 const tables={},counts={};
 for(const {name}of schema.filter(s=>s.type==='table')){
  const columns=db.prepare('PRAGMA table_xinfo('+identifier(name)+')').all().map(c=>c.name),q=db.prepare('SELECT '+columns.map(identifier).join(',')+' FROM '+identifier(name));q.setReadBigInts(true);
  const rows=q.all().map(row=>canonical(columns.map(c=>typed(row[c])))).sort();tables[name]={columns,rows};counts[name]=rows.length;
 }
 const sequences=[];
 if(db.prepare("SELECT 1 FROM sqlite_schema WHERE name='sqlite_sequence'").get()){const q=db.prepare('SELECT name,seq FROM sqlite_sequence');q.setReadBigInts(true);for(const row of q.all())sequences.push(canonical([typed(row.name),typed(row.seq)]));sequences.sort();}
 return {schema_sha256:hash(canonical(schema)),application_data_sha256:hash(canonical({format:'collect.momo15.fresh-application-state.v1',tables,sequences})),application_table_counts:counts,application_tables:Object.keys(counts).length,role_definitions:counts.admin_account_role_capabilities??0};
}
export function sqliteReferenceAuthorizer(action,one,two){
 if(action===sqlite.SQLITE_ATTACH||action===sqlite.SQLITE_DETACH)return sqlite.SQLITE_DENY;
 if(action===sqlite.SQLITE_FUNCTION&&/^(load_extension|readfile|writefile)$/i.test(two??one??''))return sqlite.SQLITE_DENY;
 if(action===sqlite.SQLITE_PRAGMA){
  const name=String(one).toLowerCase();
  if(two!==null&&two!==undefined){
   if(name==='foreign_keys'&&two==='ON')return sqlite.SQLITE_OK;
   // SQLite's reviewed ALTER TABLE path requests quick_check(table).
   if(['table_xinfo','quick_check'].includes(name)&&/^[a-z][a-z0-9_]*$/.test(two))return sqlite.SQLITE_OK;
   return sqlite.SQLITE_DENY;
  }
  if(!['foreign_key_check','integrity_check','quick_check','foreign_keys'].includes(name))return sqlite.SQLITE_DENY;
 }
 return sqlite.SQLITE_OK;
}
export async function derivePrefixes(root,roles){
 const migrationRoles=Object.fromEntries(Object.entries(roles).filter(([n])=>n.startsWith('migrations/')).map(([n,r])=>[n.slice(11),r.sha256]));
 need(same(migrationRoles,MIGRATIONS),'Local reference accepts only the exact trusted15 migration digests');
 const db=new DatabaseSync(':memory:',{allowExtension:false});db.setAuthorizer(sqliteReferenceAuthorizer);
 try{
  const prefixes={'0':fingerprint(db)};
  for(const [index,name]of Object.keys(roles).filter(n=>n.startsWith('migrations/')).sort().entries()){
   const sql=await read(join(root,name));need(sql.sha256===roles[name].sha256,'Migration changed during prefix derivation');db.exec(sql.bytes.toString('utf8'));
   need(db.prepare('PRAGMA foreign_key_check').all().length===0&&db.prepare('PRAGMA integrity_check').get().integrity_check==='ok','Local migration integrity failure');prefixes[String(index+1)]=fingerprint(db);
  }
  need(prefixes['13'].application_tables===81&&prefixes['13'].role_definitions===63&&prefixes['15'].application_tables===94&&prefixes['15'].role_definitions===67,'Wrong complete13/15 schema or role definitions');
  return {format:'collect.momo15.local-prefixes.v1',origin:'local_Node_SQLite_fresh_reference_only',node:process.version,sqlite:db.prepare('SELECT sqlite_version() AS version').get().version,foreign_key_check:'pass_after_each_prefix',integrity_check:'ok_after_each_prefix',prefixes,target_upgrade_acceptance:false,provider_acceptance:false};
 }finally{db.close();}
}
async function toolchain(runtime){
 runtime=await physical(runtime);const paths=['package.json','package-lock.json'];const versions={};
 for(const [name,pin]of Object.entries(PINS)){const path='node_modules/'+name+'/package.json',pkg=await json(join(runtime,path));need(pkg.version===pin,'Wrong pinned '+name+' version');versions[name]=pin;paths.push(path);}
 paths.push('node_modules/wrangler/bin/wrangler.js','node_modules/wrangler/wrangler-dist/cli.js','node_modules/miniflare/dist/src/index.js','node_modules/esbuild/lib/main.js','node_modules/esbuild/bin/esbuild');
 const binary=await read(process.execPath,160*1024*1024);
 return {node:{version:process.version,platform:process.platform,arch:process.arch,binary_sha256:binary.sha256,binary_bytes:binary.size},versions,files:await records(runtime,paths,32*1024*1024),scope:TOOLCHAIN_SCOPE,complete_transitive_input_qualification:false};
}
async function verifyBundle(bundleDir,root){
 need(same(await files(bundleDir),ARTIFACTS),'Bundle has missing/extra artifact roles');
 const map=await json(join(bundleDir,'index.js.map'));need(map.version===3&&map.sources.length===47&&map.sourcesContent.length===47,'Wrong compiled source-map scope');
 const names=new Set();for(let i=0;i<map.sources.length;i++){
  const s=map.sources[i];need(typeof s==='string'&&s.startsWith('../src/')&&!s.slice(3).split('/').includes('..'),'Unexpected compiled source role');const name=s.slice(3);safe(name);need(!names.has(name),'Duplicate compiled source');names.add(name);
  need(typeof map.sourcesContent[i]==='string'&&hash(map.sourcesContent[i])===(await read(join(root,name))).sha256,'Compiled source-map/source mismatch: '+name);
 }
 const bundle=(await read(join(bundleDir,'index.js'))).bytes.toString('utf8');need(bundle.endsWith('//# sourceMappingURL=index.js.map\n')&&bundle.includes('scheduled(')&&bundle.includes('index_default as default'),'Missing compiled Worker entrypoint');
 return records(bundleDir,ARTIFACTS);
}
async function save(path,bytes){await mkdir(dirname(path),{recursive:true,mode:0o700});await writeFile(path,bytes,{flag:'wx',mode:0o400});}
async function copyRecords(from,to,entries){for(const [name,expected]of Object.entries(entries)){const f=await read(join(from,name));need(same(expected,{sha256:f.sha256,bytes:f.size}),'Input drift while copying: '+name);await save(join(to,name),f.bytes);}}
async function buildProof({backend,bundleDir,buildSourceManifest,buildResult,runtime},roles){
 const manifestFile=await read(buildSourceManifest),resultFile=await read(buildResult),manifest=JSON.parse(manifestFile.bytes),result=JSON.parse(resultFile.bytes);
 const expected=Object.fromEntries(Object.entries(roles).filter(([name])=>!['operations-manifest.json','operations-manifest-momo15.json','scripts/operation_inventory.mjs'].includes(name)).map(([n,r])=>[n,r.sha256]));
 need(Object.keys(expected).length===68&&same(expected,manifest),'Reused build source inputs differ from current68 source roles');
 need(result.exit_code===0&&result.source_inputs===68&&same(result.post_check_source_mismatches,[])&&result.remote_deployment===false,'Build proof is not a completed source-stable local dry run');
 const snapshot=dirname(bundleDir),expectedCommand=['node',join(runtime,'node_modules/wrangler/bin/wrangler.js'),'deploy','--dry-run','--config',join(snapshot,'wrangler.jsonc'),'--outdir',bundleDir];
 // Older proof may spell /var/folders instead of its physical /private/var
 // alias for the exact same CLI. The executable is independently hashed below.
 const command=[...result.command];command[1]=await realpath(command[1]);need(same(command,expectedCommand),'Unexpected reused dry-run command');
 for(const [name,digest]of Object.entries(expected))need((await read(join(snapshot,name))).sha256===digest,'Existing build snapshot drift: '+name);
 return {source_manifest:manifestFile.bytes,result:resultFile.bytes,summary:{source_inputs:68,source_manifest_sha256:manifestFile.sha256,result_sha256:resultFile.sha256,snapshot_and_current_sources_equal:true,source_map_roles:47,artifact_digest_first_captured_at_packet_creation:true,fresh_compilation:false,provenance_scope:PROVENANCE_SCOPE,remote_deployment:false}};
}
export async function captureCandidate(input){
 const backend=await physical(input.backend),bundleDir=await physical(input.bundleDir),runtime=await physical(input.runtime),out=resolve(input.out);
 need(!out.startsWith(backend+'/')&&!backend.startsWith(out+'/'),'Packet must be outside the backend source boundary');
 try{await lstat(out);throw new Error('Output already exists; preserve it and select a new directory');}catch(e){if(e.code!=='ENOENT')throw e;}
 const roles=await sourceRoles(backend),inventory=await validateInventory(backend,roles,{runTrustedProducer:true}),prefixes=await derivePrefixes(backend,roles),tools=await toolchain(runtime),bundle=await verifyBundle(bundleDir,backend),proof=await buildProof({...input,backend,bundleDir,runtime},roles);
 need(roles['package-lock.json'].sha256===tools.files['package-lock.json'].sha256&&roles['package.json'].sha256===tools.files['package.json'].sha256,'Qualified runtime package/lock differ from backend');
 const producer=await read(SELF),qualifierTest=await read(TEST),contentIdentity=hash(canonical({format:'collect.momo15.backend-content.v1',files:roles}));
 await mkdir(out,{mode:0o700});await physical(out);await copyRecords(backend,join(out,'source'),roles);await copyRecords(bundleDir,join(out,'bundle'),bundle);
 await save(join(out,'evidence/build-source-manifest.json'),proof.source_manifest);await save(join(out,'evidence/build-result.json'),proof.result);await save(join(out,'evidence/local-prefixes.json'),rawJSON(prefixes));await save(join(out,'evidence/toolchain.json'),rawJSON(tools));await save(join(out,QUALIFIERS[0]),producer.bytes);await save(join(out,QUALIFIERS[1]),qualifierTest.bytes);
 const payload=await records(out,await files(out));
 const manifest={format:FORMAT,created_at:new Date().toISOString(),scope:'Inert exact71-role backend+compiled Worker local candidate; no source admission, approval inheritance or executor',backend_content_identity:contentIdentity,source_roles:roles,bundle_roles:bundle,qualifier_roles:Object.fromEntries(QUALIFIERS.map(n=>[n,payload[n]])),inventory,build:proof.summary,toolchain:{node:tools.node,versions:tools.versions},runtime_identity:{captured_BUILD_SOURCE_ID:inventory.runtime_build_source_id,matches_backend_content_identity:inventory.runtime_build_source_id===contentIdentity,adopted:false,configuration_bytes_changed:false},acceptance:{...NO_ACCEPTANCE},remaining_gates:[...GATES],files:payload};
 const manifestBytes=rawJSON(manifest);await save(join(out,'candidate.json'),manifestBytes);
 need(same(await sourceRoles(backend),roles),'Source changed during candidate capture');
 return {packet:out,manifest_sha256:hash(manifestBytes),backend_content_identity:contentIdentity,source_roles:71,compiled_bundle_sha256:bundle['index.js'].sha256,acceptance:{...NO_ACCEPTANCE}};
}
export async function verifyCandidate({packet,sha256,backend=null,runtime=null}){
 need(SHA.test(sha256??''),'An external exact candidate SHA256 pin is required');packet=await physical(packet);
 const f=await read(join(packet,'candidate.json'));need(f.sha256===sha256,'Candidate manifest differs from the external SHA256 pin');const manifest=JSON.parse(f.bytes);
 need(manifest.format===FORMAT&&same(manifest.acceptance,NO_ACCEPTANCE)&&same(manifest.remaining_gates,GATES),'Unsupported candidate or promoted acceptance');
 const observed=await records(packet,(await files(packet)).filter(n=>n!=='candidate.json'));need(same(observed,manifest.files),'Packet contains missing/extra/changed roles');
 need(same(manifest.qualifier_roles,Object.fromEntries(QUALIFIERS.map(n=>[n,manifest.files[n]])))&&manifest.qualifier_roles[QUALIFIERS[0]].sha256===(await read(SELF)).sha256&&manifest.qualifier_roles[QUALIFIERS[1]].sha256===(await read(TEST)).sha256,'Candidate verifier/test qualifier differs from current bytes');
 const source=join(packet,'source'),roles=await sourceRoles(source);need(same(roles,manifest.source_roles)&&Object.keys(roles).length===71,'Wrong candidate source role boundary');
 const identity=hash(canonical({format:'collect.momo15.backend-content.v1',files:roles}));need(manifest.backend_content_identity===identity,'Candidate content identity mismatch');
 const inventory=await validateInventory(source,roles);need(same(inventory,manifest.inventory),'Candidate inventory facts differ');
 need(same(manifest.runtime_identity,{captured_BUILD_SOURCE_ID:inventory.runtime_build_source_id,matches_backend_content_identity:inventory.runtime_build_source_id===identity,adopted:false,configuration_bytes_changed:false}),'Runtime identity cannot be silently adopted');
 need(same(await derivePrefixes(source,roles),await json(join(packet,'evidence/local-prefixes.json'))),'Local complete15 prefix facts changed');
 need(same(await verifyBundle(join(packet,'bundle'),source),manifest.bundle_roles),'Compiled bundle role mismatch');
 const tools=await json(join(packet,'evidence/toolchain.json'));need(same(tools.versions,PINS)&&tools.scope===TOOLCHAIN_SCOPE&&tools.complete_transitive_input_qualification===false&&same(manifest.toolchain,{node:tools.node,versions:tools.versions}),'Toolchain facts differ');
 const buildSource=await read(join(packet,'evidence/build-source-manifest.json')),buildResult=await read(join(packet,'evidence/build-result.json')),proof=JSON.parse(buildResult.bytes);
 const expected=Object.fromEntries(Object.entries(roles).filter(([name])=>!['operations-manifest.json','operations-manifest-momo15.json','scripts/operation_inventory.mjs'].includes(name)).map(([n,r])=>[n,r.sha256]));
 need(same(JSON.parse(buildSource.bytes),expected)&&buildSource.sha256===manifest.build.source_manifest_sha256&&buildResult.sha256===manifest.build.result_sha256&&proof.exit_code===0&&proof.remote_deployment===false&&same(proof.post_check_source_mismatches,[]),'Reused build evidence mismatch');
 need(manifest.build.source_inputs===68&&manifest.build.source_map_roles===47&&manifest.build.snapshot_and_current_sources_equal===true&&manifest.build.artifact_digest_first_captured_at_packet_creation===true&&manifest.build.fresh_compilation===false&&manifest.build.provenance_scope===PROVENANCE_SCOPE&&manifest.build.remote_deployment===false,'Invalid build custody scope');
 if(backend)need(same(await sourceRoles(await physical(backend)),roles),'Current backend source drifted from captured candidate');
 if(runtime)need(same(await toolchain(runtime),tools),'Qualified runtime toolchain drifted');
 return {status:'pass',packet,manifest_sha256:sha256,backend_content_identity:identity,source_roles:71,migration_prefixes:16,application_tables:94,role_definitions:67,operation_wires:92,route_families:30,acceptance:{...NO_ACCEPTANCE}};
}
function argumentsFor(argv){
 const [mode,...args]=argv;need(['capture','verify'].includes(mode),'Use capture or verify');const values={};
 const allowed=mode==='capture'?['backend','bundle-dir','build-source-manifest','build-result','runtime','out']:['packet','sha256','backend','runtime'];
 need(args.length%2===0,'Options require explicit values');for(let i=0;i<args.length;i+=2){need(args[i].startsWith('--')&&allowed.includes(args[i].slice(2))&&!Object.hasOwn(values,args[i].slice(2)),'Unknown/duplicate option');values[args[i].slice(2)]=args[i+1];}
 const required=mode==='capture'?allowed:['packet','sha256'];need(required.every(n=>typeof values[n]==='string'&&values[n].length),'Missing required option');return {mode,values};
}
if(process.argv[1]&&resolve(process.argv[1])===SELF){
 try{const {mode,values:v}=argumentsFor(process.argv.slice(2));const result=mode==='capture'?await captureCandidate({backend:v.backend,bundleDir:v['bundle-dir'],buildSourceManifest:v['build-source-manifest'],buildResult:v['build-result'],runtime:v.runtime,out:v.out}):await verifyCandidate({packet:v.packet,sha256:v.sha256,backend:v.backend,runtime:v.runtime});process.stdout.write(JSON.stringify(result,null,2)+'\n');}
 catch(error){process.stderr.write('MoMo15 candidate refused: '+error.message+'\n');process.exitCode=1;}
}
