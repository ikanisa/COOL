#!/usr/bin/env node
// Backend staging/remediation admission. Source export flags remain unapproved.
// The publication controller, not an adjacent input file, supplies the reviewed
// approval digest and the independent provider readback adapter. There is no
// CLI that manufactures that authority or accepts arbitrary provider commands.
import {createHash,randomUUID} from 'node:crypto';
import {constants} from 'node:fs';
import {open,lstat,realpath,readdir,mkdir,unlink} from 'node:fs/promises';
import {spawn} from 'node:child_process';
import {basename,dirname,isAbsolute,join,relative,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {createRequire} from 'node:module';

const ROOT=fileURLToPath(new URL('../../',import.meta.url));
const SHA=/^[a-f0-9]{64}$/,UUID=/^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
const ACCOUNT='2209b915a85b1c11cee79b7806c6e73b';
const PRIMARY='a6a0d284-c445-4fe3-8e64-af5fd42491ae';
// Initial reviewed artifact scope. A successor handler/bundle/qualification needs
// explicit review/admission; internally consistent caller metadata is not trust.
export const currentBackendProfile=Object.freeze({parent_source_id:'a8a2eca222ae64a46b2ccf58079658ea11a913720a927a2b001c7f946d8cdf56',parent_manifest_sha256:'a66623c625660856d21276920f05a22d07cb68f031bd363efb56af8e69e8f663',publication_receipt_sha256:'27c3af16b2a7b138b892306339e334e9e836a13fd2fabf680dba01f3a7886a8c',bundle_sha256:'0d0194e10db454dd375928ce1905e015d321cd700b108f3a8815fc937999c568',bundle_bytes:513240,operations_sha256:'2aee70cb5da8315f062b65cd6459b521ccf25e156d1981d16539984d97d9f7b3',qualification_sha256:'51cc8664a6c874f40b46e4de5042cc27c8a604369dfcd1bef70ea8050b13c6d3'});
const PINS=Object.freeze({
 'scripts/qa/collect_release_candidate.py':'f390f86b85e8b8f7020e5c55e5aa0dbd753d6eed3510aa490881e54196b410c8',
 'scripts/cloudflare/approved_toolchain.mjs':'5fadc724f1c1d25f811b868349f9f5a3eb3daa65d568861ca4bf493cae445535',
 'scripts/cloudflare/recovery_quarantine.mjs':'9bd47a779602e31f8ee7be5dc6a082af010f40fff389f7ee87798d04873deaf9',
});
const NO_APPROVAL={trusted_source_verified:false,reviewed:false,frozen:false,owner_approved:false,signed:false,production_release_accepted:false};
const ACTIONS=['migrate_current11','deploy_bundle'];
const need=(ok,message)=>{if(!ok)throw new Error(message);};
export const sha256=raw=>createHash('sha256').update(raw).digest('hex');
export function canonical(value){
 if(Array.isArray(value))return '['+value.map(canonical).join(',')+']';
 if(value!==null&&typeof value==='object')return '{'+Object.keys(value).sort().map(k=>JSON.stringify(k)+':'+canonical(value[k])).join(',')+'}';
 need(value!==undefined&&typeof value!=='bigint'&&(typeof value!=='number'||Number.isFinite(value)),'Unsupported canonical value');return JSON.stringify(value);
}
const equal=(a,b)=>canonical(a)===canonical(b);
function digest(value,label){need(SHA.test(value??''),label+' must be an explicit lowercase SHA256');return value;}
function keys(value,names,label){need(value!==null&&typeof value==='object'&&!Array.isArray(value)&&equal(Object.keys(value).sort(),[...names].sort()),label+' has unknown or missing fields');}
function utc(value,label){need(typeof value==='string'&&new Date(Date.parse(value)).toISOString()===value,label+' must be a canonical UTC timestamp');return Date.parse(value);}
function safeName(value,label){need(typeof value==='string'&&/^[a-z0-9][a-z0-9-]{2,62}$/.test(value),label+' is invalid');return value;}
function relativeName(value){need(typeof value==='string'&&value.length<=256&&!value.startsWith('/')&&value.split('/').every(p=>/^[A-Za-z0-9_.-]+$/.test(p)&&p!=='.'&&p!=='..'),'Unsafe package/source path');return value;}
async function physical(path){
 need(typeof path==='string'&&isAbsolute(path)&&path.length<=4096&&!/[\x00-\x1f\x7f]/.test(path),'Use an explicit absolute physical path');
 let part='/';for(const name of resolve(path).split('/').filter(Boolean)){part=join(part,name);need(!(await lstat(part)).isSymbolicLink(),'Aliased input is not admitted');}return realpath(path);
}
async function read(path,max=4*1024*1024,{systemPython=false}={}){
 path=await physical(path);const f=await open(path,constants.O_RDONLY|constants.O_NOFOLLOW);
 try{const before=await f.stat();need(before.isFile()&&(before.nlink===1||systemPython&&path==='/usr/bin/python3'&&before.uid===0&&(before.mode&0o022)===0)&&before.size<=max,'Input must be a bounded independent regular file');const raw=await f.readFile(),after=await f.stat(),named=await lstat(path);
  need([after,named].every(s=>s.ino===before.ino&&s.dev===before.dev&&s.size===before.size&&s.mtimeMs===before.mtimeMs&&s.ctimeMs===before.ctimeMs)&&!named.isSymbolicLink(),'Input changed while reading');return {path,raw,sha256:sha256(raw),bytes:raw.length,mode:before.mode&0o7777};
 }finally{await f.close();}
}
function parse(raw,label){try{return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(raw));}catch{throw new Error(label+' is not strict UTF8 JSON');}}
async function json(path){const file=await read(path);return {...file,value:parse(file.raw,path)};}
async function durable(path,raw,mode=0o400){
 await mkdir(dirname(path),{recursive:true,mode:0o700});const f=await open(path,'wx',mode);try{await f.writeFile(raw);await f.sync();}finally{await f.close();}
 const d=await open(dirname(path),'r');try{await d.sync();}finally{await d.close();}
}
async function privateDirectory(path,{create=false}={}){
 if(create){need(isAbsolute(path),'Use an absolute package destination');await physical(dirname(path));need(basename(path)!=='.'&&basename(path)!=='..','Unsafe package destination');await mkdir(path,{mode:0o700});}path=await physical(path);const s=await lstat(path);need(s.isDirectory()&&s.uid===process.getuid()&&(s.mode&0o077)===0,'An owned private physical directory is required');return path;
}
async function pinnedSupport(){const result={};for(const [name,pin]of Object.entries(PINS)){const f=await read(join(ROOT,name));need(f.sha256===pin,'Reviewed backend support source changed: '+name);result[name]={sha256:pin,bytes:f.bytes};}return result;}
async function runLocal(binary,args,{cwd=ROOT,env=process.env,max=4*1024*1024}={}){
 return new Promise((done,reject)=>{const child=spawn(binary,args,{cwd,env,stdio:['ignore','pipe','pipe'],shell:false});let output=[],errors=[],size=0,timedOut=false,escalation=null;
  const terminate=()=>{child.kill('SIGTERM');if(escalation===null){escalation=setTimeout(()=>child.kill('SIGKILL'),5000);escalation.unref();}},timer=setTimeout(()=>{timedOut=true;terminate();},120000);timer.unref();const cleanup=()=>{clearTimeout(timer);if(escalation!==null)clearTimeout(escalation);};
  const take=dest=>raw=>{size+=raw.length;if(size>max){terminate();return;}dest.push(raw);};child.stdout.on('data',take(output));child.stderr.on('data',take(errors));child.once('error',error=>{cleanup();reject(error);});child.once('close',(code,signal)=>{cleanup();if(timedOut)reject(new Error('Bounded command deadline exceeded; independent readback required'));else if(size>max)reject(new Error('Bounded command output exceeded'));else done({code,signal,stdout:Buffer.concat(output),stderr:Buffer.concat(errors)});});
 });
}
export async function verifySourceExport(candidatePath,expectedManifestSha256){
 await pinnedSupport();const candidate=await physical(candidatePath),manifest=await json(join(candidate,'.collect-release-candidate.json'));
 need(manifest.sha256===digest(expectedManifestSha256,'Export manifest'),'Unbound immutable source export');
 const m=manifest.value;need(m.capture_classification==='strict_unapproved_source_export'&&m.retain_source_drift===false&&m.source_current_tree_accepted===false,'A strict coherent source export is required');
 need(equal(m.approvals,NO_APPROVAL),'Source export approvals must all remain false');
 const drift=m.observed_source_drift;need(drift&&['selected_files','excluded_upstream_fixtures','indexed_absence_paths'].every(k=>Array.isArray(drift[k])&&drift[k].length===0),'Drifting source export is not admitted');
 need(candidate!==m.source_root&&!candidate.startsWith(m.source_root+'/'),'Use an export outside its mutable source tree');
 // Reuse the existing complete bytes/modes/extras verifier; do not reconstruct
 // its source-selection, credential screening or private-file exclusions here.
 const python=await read('/usr/bin/python3',256*1024*1024,{systemPython:true});
 const result=await runLocal(python.path,[join(ROOT,'scripts/qa/collect_release_candidate.py'),'verify','--candidate',candidate,'--expected-manifest-sha256',expectedManifestSha256],{env:{PATH:'/usr/bin:/bin',HOME:process.env.HOME??'/tmp',PYTHONDONTWRITEBYTECODE:'1'}});
 const checked=parse(result.stdout,'Existing export verifier response');need(result.code===0&&checked.status==='pass'&&equal(checked.approvals,NO_APPROVAL),'Existing immutable export verifier refused source');
 return {path:candidate,manifest_sha256:manifest.sha256,source_manifest_sha256:m.source_manifest_sha256,manifest:m,verification:checked,python:{path:python.path,sha256:python.sha256,bytes:python.bytes}};
}
// Explicit alternative for the backend-only original ARC05 scope. This neither
// changes nor bypasses the whole-product verifier above. It admits only the
// independently pinned retained API16 cohort, not arbitrary selected source.
export async function verifyBackendSourceAdmission(admissionPath,reviewedAdmissionSha256){
 digest(reviewedAdmissionSha256,'Independent reviewed backend-source admission pin');await pinnedSupport();const file=await json(admissionPath);need(file.sha256===reviewedAdmissionSha256,'Backend-source admission differs from independent review pin');const packet=file.value;
 keys(packet,['format','scope','parent_api_source_id','source_root','parent_candidate_manifest','qualification','operations_manifest','bundle','files','source_capture','approvals'],'Backend-source admission');
 need(packet.format==='collect.api16.backend-source-admission.v1'&&packet.scope==='backend_only'&&packet.parent_api_source_id===currentBackendProfile.parent_source_id,'Unsupported bounded backend-source scope');need(equal(packet.approvals,NO_APPROVAL),'Backend-source approval flags must remain false');
 const sourceRoot=await physical(packet.source_root);need((await lstat(sourceRoot)).isDirectory()&&!file.path.startsWith(sourceRoot+'/'),'Admission map must be outside the bounded source directory');
 const references={};for(const [name,pin]of [['parent_candidate_manifest',currentBackendProfile.parent_manifest_sha256],['qualification',currentBackendProfile.qualification_sha256],['operations_manifest',currentBackendProfile.operations_sha256]]){keys(packet[name],['path','sha256'],name);const referenced=await json(packet[name].path);need(packet[name].sha256===pin&&referenced.sha256===pin,'Unreviewed bounded-source '+name);references[name]=referenced;}
 keys(packet.bundle,['path','sha256','bytes'],'Bounded bundle');const bundle=await read(packet.bundle.path,16*1024*1024);need(packet.bundle.sha256===currentBackendProfile.bundle_sha256&&packet.bundle.bytes===currentBackendProfile.bundle_bytes&&bundle.sha256===packet.bundle.sha256&&bundle.bytes===packet.bundle.bytes,'Bounded bundle differs from actual API16 artifact');
 keys(packet.source_capture,['origin','parent_publication_receipt'],'Bounded provenance');need(packet.source_capture.origin==='retained_published_API16_parent','Unsupported source provenance');const receiptRef=packet.source_capture.parent_publication_receipt;keys(receiptRef,['path','sha256'],'Publication receipt reference');const receipt=await json(receiptRef.path);need(receiptRef.sha256===currentBackendProfile.publication_receipt_sha256&&receipt.sha256===receiptRef.sha256&&receipt.value.all_pass===true&&receipt.value.source_id===currentBackendProfile.parent_source_id&&receipt.value.actual_main_sha256===currentBackendProfile.bundle_sha256,'Bounded source lacks pinned actual publication provenance');
 const manifest=references.parent_candidate_manifest.value;need(manifest.source_id===currentBackendProfile.parent_source_id&&Object.keys(manifest.files??{}).length===57,'Incomplete retained backend parent manifest');need(packet.files&&equal(Object.keys(packet.files).sort(),Object.keys(manifest.files).sort()),'Bounded source must contain exactly the57 actual parent roles');
 const directories=new Set();for(const name of Object.keys(manifest.files)){const parts=name.split('/');for(let i=1;i<parts.length;i++)directories.add(parts.slice(0,i).join('/'));}let total=0;const observed=await recursiveFiles(sourceRoot,directories);need(equal(observed,manifest.files),'Bounded source has extra/missing/changed/private roles');
 for(const [name,expected]of Object.entries(packet.files)){relativeName(name);keys(expected,['sha256','bytes','mode'],'Bounded source role');need(name.startsWith('src/')||name.startsWith('migrations/')||['operations-manifest.json','package-lock.json','package.json','scripts/operation_inventory.mjs','wrangler.jsonc'].includes(name),'Private/unrecognized bounded source role');need(equal({sha256:expected.sha256,bytes:expected.bytes},manifest.files[name])&&Number.isInteger(expected.mode)&&expected.mode>=0&&expected.mode<=0o777&&(expected.mode&0o022)===0,'Bounded role metadata differs from retained parent');const role=await read(join(sourceRoot,name));need(role.sha256===expected.sha256&&role.bytes===expected.bytes&&role.mode===expected.mode,'Bounded source role bytes/mode changed: '+name);total+=role.bytes;}
 need(total<=4*1024*1024&&references.operations_manifest.path===join(sourceRoot,'operations-manifest.json'),'Bounded source size or operations provenance mismatch');need(equal(await recursiveFiles(sourceRoot,directories),manifest.files),'Bounded source namespace changed during admission');
 return {path:sourceRoot,backend_path:sourceRoot,backend_roles:packet.files,admission_kind:'api16_backend_only',admission_manifest_path:file.path,manifest_sha256:file.sha256,source_manifest_sha256:sha256(canonical(packet.files)+'\n'),verification:{scope:'Exact57 retained API16 backend roles/modes/historical publication provenance only',source_role_count:57,bytes:total,whole_product_verified:false,approvals:{...NO_APPROVAL}},bound_artifact_paths:{release_manifest:references.parent_candidate_manifest.path,operations_manifest:references.operations_manifest.path,qualification:references.qualification.path,bundle:bundle.path},provenance_receipt_sha256:receipt.sha256};
}
export function validateTarget(target){
 keys(target,['account_id','worker_name','database_name','database_id','r2_bucket','origin','admin_origin'],'Target');
 need(target.account_id===ACCOUNT,'Wrong Cloudflare account');safeName(target.worker_name,'Worker');safeName(target.database_name,'D1 name');safeName(target.r2_bucket,'R2 bucket');
 need(target.worker_name!=='collect-platform-api'&&target.database_name!=='collect-platform'&&target.r2_bucket!=='collect-platform-private'&&UUID.test(target.database_id)&&target.database_id!==PRIMARY,'Only a distinct isolated staging/remediation target is supported');
 const productionHosts=new Set(['collect.ikanisa.com','www.collect.ikanisa.com','api.collect.ikanisa.com','admin.collect.ikanisa.com','platform-admin.collect.ikanisa.com']);
 for(const key of ['origin','admin_origin']){const url=new URL(target[key]);need(url.protocol==='https:'&&url.origin===target[key]&&!url.username&&!url.password&&!productionHosts.has(url.hostname),'Use an exact isolated HTTPS origin');}
 return target;
}
export function validateStageConfig(config,target,sourceId){
 validateTarget(target);const allowed=['name','main','compatibility_date','compatibility_flags','account_id','workers_dev','preview_urls','observability','vars','d1_databases','r2_buckets','routes','triggers'];
 need(config&&Object.keys(config).every(k=>allowed.includes(k)),'Unsupported configuration capability');
 need(config.name===target.worker_name&&config.account_id===target.account_id&&config.main==='bundle/index.js','Target config name/account/explicit bundle entry mismatch');
 need(config.compatibility_date==='2026-10-14'&&equal(config.compatibility_flags??[],[]),'Unsupported compatibility date or flags');
 need(equal(config.observability,{enabled:true}),'Unsupported observability configuration');
 need(config.preview_urls===false&&typeof config.workers_dev==='boolean'&&equal(config.routes??[],config.workers_dev?[]:[{pattern:new URL(target.origin).host,custom_domain:true}]),'Target exposure must have exactly its approved isolated route');
 need(equal(config.triggers??{crons:[]},{crons:[]}),'Current backend has no scheduler; new scheduler scope is unsupported');
 need(equal(config.d1_databases,[{binding:'DB',database_name:'collect-platform',database_id:target.database_id,migrations_dir:'migrations'}]),'D1 binding/approved fixed CLI alias mismatch');
 need(equal(config.r2_buckets,[{binding:'PRIVATE_MEDIA',bucket_name:target.r2_bucket}]),'R2 binding mismatch');
 need(config.vars&&Object.getPrototypeOf(config.vars)===Object.prototype&&config.vars.BUILD_SOURCE_ID===digest(sourceId,'Source ID'),'Source ID configuration mismatch');
 need(config.vars.APP_ENVIRONMENT==='staging'&&config.vars.ENVIRONMENT==='staging','This slice admits staging/remediation only');
 for(const [name,value]of Object.entries(config.vars)){need(/^[A-Z][A-Z0-9_]{0,79}$/.test(name)&&typeof value==='string'&&value.length<=2048&&!/[\x00-\x1f\x7f]/.test(value),'Invalid public configuration variable');need(!/(?:SECRET|PASSWORD|PRIVATE_KEY|TOKEN)$/.test(name),'Secret values do not belong in the release package');}
 need((config.vars.ALLOWED_ORIGINS??'').split(',').every(x=>[target.origin,target.admin_origin].includes(x))&&config.vars.ADMIN_ORIGIN===target.admin_origin,'Origin configuration is outside target scope');
 need(config.vars.ADMIN_ORIGINS===undefined||config.vars.ADMIN_ORIGINS.split(',').every(x=>x===target.admin_origin),'Admin origin configuration is outside target scope');
 need(config.vars.TURNSTILE_HOSTNAME===undefined||config.vars.TURNSTILE_HOSTNAME===new URL(target.origin).hostname,'Challenge hostname is outside target scope');
 return config;
}
function projection(config){const {main,...rest}=config;return rest;}
export function stagingSourceIdentity(parentIdentityRecords,config){const normalized=structuredClone(config);delete normalized.vars.BUILD_SOURCE_ID;const raw=Buffer.from(canonical(normalized)),records={...parentIdentityRecords,'wrangler.normalized.json':{sha256:sha256(raw),bytes:raw.length}};return {source_id:sha256(canonical(records)),records};}
export const migrationFingerprintDefinition='collect.backend.fresh-application-state.v2';
// Direct sqlite_master rows may be supplied by the trusted provider reader to
// retain actual stored SQL instead of an export writer's CREATE TABLE spelling.
// Never strip constraint/index/trigger SQL or call a semantic mismatch harmless.
export const migrationSchemaQuery="SELECT type,name,tbl_name,sql FROM sqlite_schema WHERE sql IS NOT NULL AND name NOT GLOB 'sqlite_*' ORDER BY type,name";
// Exact observed schemas: current hosted D1 _cf_KV and retained actual API16
// d1_migrations (also produced by the pinned Wrangler4.151 migration template).
// A provider-looking prefix or familiar table name never grants an exclusion.
export const providerBookkeepingSchemas=Object.freeze({
 _cf_KV:'CREATE TABLE _cf_KV (\n        key TEXT PRIMARY KEY,\n        value BLOB\n      ) WITHOUT ROWID',
 d1_migrations:'CREATE TABLE "d1_migrations"(\n\t\tid         INTEGER PRIMARY KEY AUTOINCREMENT,\n\t\tname       TEXT UNIQUE,\n\t\tapplied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL\n)',
});
const identifier=value=>{need(typeof value==='string'&&/^[a-z][a-z0-9_]*$/.test(value),'Unsupported application identifier');return '"'+value+'"';};
function typedValue(value){if(value===null)return ['null'];if(value instanceof Uint8Array)return ['blob',Buffer.from(value).toString('hex')];if(typeof value==='bigint')return ['integer',value.toString()];if(typeof value==='number'){need(Number.isFinite(value)&&(!Number.isInteger(value)||Number.isSafeInteger(value)),'Imprecise application-data value');return [Number.isInteger(value)?'integer':'real',Object.is(value,-0)?'-0':String(value)];}need(typeof value==='string','Unknown application-data type');return ['text',value];}
function admitBookkeeping(rows,{actualProvider=false}={}){
 const provider=new Set(),application=[];
 for(const row of rows){keys(row,['type','name','tbl_name','sql'],'Schema row');need(['table','index','trigger','view'].includes(row.type)&&typeof row.sql==='string','Schema row is incomplete');const known=Object.hasOwn(providerBookkeepingSchemas,row.name),onProvider=Object.hasOwn(providerBookkeepingSchemas,row.tbl_name);
  if(known||onProvider||/^_cf_/i.test(row.name)||/^_cf_/i.test(row.tbl_name)){
   need(known&&row.type==='table'&&row.name===row.tbl_name&&row.sql===providerBookkeepingSchemas[row.name]&&!provider.has(row.name),'Unreviewed provider bookkeeping object or schema');provider.add(row.name);
  }else{identifier(row.name);identifier(row.tbl_name);application.push(row);}
 }
 if(actualProvider)need(provider.has('_cf_KV'),'Complete actual provider schema must retain the observed _cf_KV table');
 return {provider,application};
}
export function migrationStateFingerprint(db,{schemaRows=null}={}){
 const local=admitBookkeeping(db.prepare(migrationSchemaQuery).all());let schema=local.application;
 if(schemaRows!==null){need(Array.isArray(schemaRows),'Complete actual sqlite_master rows required');const actual=admitBookkeeping(schemaRows,{actualProvider:true});need(actual.provider.has('d1_migrations')===local.provider.has('d1_migrations'),'Actual migration bookkeeping coverage differs from complete SQL readback');schema=[...actual.application].sort((a,b)=>a.type<b.type?-1:a.type>b.type?1:a.name<b.name?-1:a.name>b.name?1:0);need(equal(schema.map(({type,name,tbl_name})=>({type,name,tbl_name})),local.application.map(({type,name,tbl_name})=>({type,name,tbl_name}))),'Actual schema object coverage differs from complete SQL readback');}
 const tableRows=local.application.filter(row=>row.type==='table').map(({name})=>({name})).sort((a,b)=>a.name<b.name?-1:a.name>b.name?1:0),tables={},counts={};
 for(const {name}of tableRows){const quoted=identifier(name),columns=db.prepare('PRAGMA table_xinfo('+quoted+')').all().map(c=>c.name);need(columns.length>0,'Application table column coverage missing');const stmt=db.prepare('SELECT '+columns.map(identifier).join(',')+' FROM '+quoted);stmt.setReadBigInts(true);const rows=stmt.all().map(row=>canonical(columns.map(column=>typedValue(row[column])))).sort();tables[name]={columns,rows};counts[name]=rows.length;}
 let sequences=[];if(db.prepare("SELECT 1 FROM sqlite_schema WHERE name='sqlite_sequence'").get()){const stmt=db.prepare('SELECT name,seq FROM sqlite_sequence');stmt.setReadBigInts(true);for(const row of stmt.all()){need(typeof row.name==='string'&&!/^_cf_/i.test(row.name),'Unreviewed provider-prefix sequence');if(row.name==='d1_migrations'){need(local.provider.has('d1_migrations'),'Unvalidated migration bookkeeping sequence');continue;}sequences.push(canonical([typedValue(row.name),typedValue(row.seq)]));}sequences.sort();}
 return {definition:migrationFingerprintDefinition,schema_sha256:sha256(canonical(schema)),application_data_sha256:sha256(canonical({format:migrationFingerprintDefinition,tables,sequences})),application_table_counts:counts,application_sequence_count:sequences.length};
}
async function deriveCompatibility(base,migrations){
 const {DatabaseSync}=await import('node:sqlite'),db=new DatabaseSync(':memory:');
 try{const prefixes={'0':migrationStateFingerprint(db)};let number=0;for(const name of Object.keys(migrations).sort()){const sql=await read(join(base,name));need(sql.sha256===migrations[name],'Migration changed during prefix derivation');db.exec(new TextDecoder('utf-8',{fatal:true}).decode(sql.raw));need(db.prepare('PRAGMA foreign_key_check').all().length===0&&db.prepare('PRAGMA integrity_check').get().integrity_check==='ok','Local migration reference failed integrity');prefixes[String(++number)]=migrationStateFingerprint(db);}const evidence={format:'collect.backend.current11-prefix-model.v1',profile:'candidate11',node_version:process.version,input_migrations:migrations,bookkeeping_schema_sha256:Object.fromEntries(Object.entries(providerBookkeepingSchemas).map(([k,v])=>[k,sha256(v)])),prefixes,origin:'local_Node_SQLite_reference_only',provider_acceptance:false};return {evidence,compatibility:{schema_profile:'candidate11',fingerprint_definition:migrationFingerprintDefinition,schema_after_sha256:prefixes['11'].schema_sha256,application_data_after_sha256:prefixes['11'].application_data_sha256,schema_prefix_sha256:Object.fromEntries(Object.entries(prefixes).map(([k,v])=>[k,v.schema_sha256])),application_data_prefix_sha256:Object.fromEntries(Object.entries(prefixes).map(([k,v])=>[k,v.application_data_sha256])),evidence_sha256:sha256(canonical(evidence)+'\n')}};
 }finally{db.close();}
}
async function recursiveFiles(root,allowedDirectories=null){const output={};async function walk(base,prefix=''){for(const entry of await readdir(base,{withFileTypes:true})){need(!entry.isSymbolicLink(),'Source tree alias');const name=prefix+entry.name;if(entry.isDirectory()){need(allowedDirectories===null||allowedDirectories.has(name),'Unexpected bounded source directory');await walk(join(base,entry.name),name+'/');}else{need(entry.isFile(),'Unknown source node');const f=await read(join(base,entry.name));output[name]={sha256:f.sha256,bytes:f.bytes};}}}await walk(root);return output;}
async function reviewBackendSource(source,releaseFile,operationsFile,qualificationFile){
 const release=releaseFile.value,base=source.backend_path??join(source.path,'deploy/platform-api');need(release.source_id===currentBackendProfile.parent_source_id&&operationsFile.sha256===currentBackendProfile.operations_sha256&&qualificationFile.sha256===currentBackendProfile.qualification_sha256,'Unreviewed backend source/inventory/qualification profile');need(release.source_id_definition==='SHA256 of canonical sorted compact JSON of source identity records; configuration is sorted compact JSON with BUILD_SOURCE_ID omitted','Unsupported source identity recipe');
 const files=release.files;need(files&&Object.keys(files).length>0,'Incomplete source role manifest');const observed={};
 for(const [name,record]of Object.entries(files)){relativeName(name);need(name.startsWith('src/')||name.startsWith('migrations/')||['operations-manifest.json','package-lock.json','package.json','scripts/operation_inventory.mjs','wrangler.jsonc'].includes(name),'Unknown backend role');const f=await read(join(base,name));need(equal(record,{sha256:f.sha256,bytes:f.bytes}),'Backend source role changed: '+name);need((source.backend_roles?.[name]??source.manifest?.source_files['deploy/platform-api/'+name])?.sha256===f.sha256,'Backend role is not in admitted immutable source');observed[name]=record;}
 for(const folder of ['src','migrations']){const tree=await recursiveFiles(join(base,folder));need(equal(tree,Object.fromEntries(Object.entries(observed).filter(([k])=>k.startsWith(folder+'/')).map(([k,v])=>[k.slice(folder.length+1),v]))),'Incomplete backend '+folder+' manifest');}
 const sourceConfig=(await json(join(base,'wrangler.jsonc'))).value,normalized=structuredClone(sourceConfig);delete normalized.vars.BUILD_SOURCE_ID;const normalizedRaw=Buffer.from(canonical(normalized));const identities={...observed};delete identities['wrangler.jsonc'];identities['wrangler.normalized.json']={sha256:sha256(normalizedRaw),bytes:normalizedRaw.length};
 need(equal(identities,release.source_id_inputs)&&sha256(canonical(identities))===release.source_id&&sourceConfig.vars.BUILD_SOURCE_ID===release.source_id,'Unbound backend source identity');
 need(observed['operations-manifest.json']?.sha256===operationsFile.sha256,'Operation inventory is not source-bound');const inventory=operationsFile.value;
 need(inventory.schema_version===1&&inventory.service==='collect-platform-api'&&inventory.registration_is_provider_availability===false&&inventory.whole_endpoint_acceptance===false&&inventory.operations?.length===89&&inventory.route_families?.length===10,'Unsupported current operation inventory');
 const src=Object.fromEntries(Object.entries(observed).filter(([k])=>k.startsWith('src/')).map(([k,v])=>[k.slice(4),v.sha256]));need(equal(src,inventory.source_sha256),'Incomplete handler source inventory');
 const {quarantineSchemaProfiles}=await import('./recovery_quarantine.mjs'),migrations=Object.fromEntries(Object.entries(observed).filter(([k])=>k.startsWith('migrations/')).map(([k,v])=>[k,v.sha256]));
 need(equal(migrations,quarantineSchemaProfiles.candidate11.digests),'Unsupported future/changed migration or recovery scope');need(equal(inventory.migrations_sha256,Object.fromEntries(Object.entries(migrations).map(([k,v])=>[k.slice(11),v]))),'Migration inventory mismatch');
 const routes=new Set();for(const op of inventory.operations){need(['rpc','function'].includes(op.kind)&&typeof op.name==='string'&&op.method==='POST'&&typeof op.path==='string'&&!routes.has(op.path)&&src[op.source],'Unclosed/duplicate handler registration');routes.add(op.path);}for(const family of inventory.route_families)need(src[family.source],'Unclosed route family');
 const q=qualificationFile.value;need(q.local_qualification_only===true&&q.api_source_id===release.source_id&&q.full_suite_before_after_equal===true&&q.suite_tests>0&&q.suite_test_files>0&&equal([...q.sealed_candidate_roles_bound_to_suite].sort(),Object.keys(observed).filter(k=>k!=='wrangler.jsonc').sort()),'Incomplete source-bound qualification');
 need(sourceConfig.compatibility_date==='2026-10-14'&&equal(sourceConfig.compatibility_flags??[],[])&&equal(sourceConfig.triggers??{crons:[]},{crons:[]}),'Unsupported source compatibility/scheduler');
 return {source_id:release.source_id,files:observed,migrations,inventory,base,scheduler:{crons:[],scheduled_handler:false,scope:'Known source-bound current backend; new scheduler requires review'}};
}
export function validateSnapshot(snapshot,{target,mode,now=Date.now(),fresh=true}={}){
 keys(snapshot,['format','origin','target','observed_at','complete','raw_readback_sha256','database','worker','r2','preserved'],'Provider snapshot');
 need(snapshot.format==='collect.backend.provider-snapshot.v1'&&snapshot.origin===(mode==='simulation'?'simulated_transport':'actual_cloudflare_readback')&&snapshot.complete===true,'Incomplete or wrong-origin provider readback');need(equal(snapshot.target,target),'Provider target changed');
 const time=utc(snapshot.observed_at,'Readback time');if(fresh)need(time<=now+30000&&now-time<=60000,'Provider readback is not fresh');digest(snapshot.raw_readback_sha256,'Full provider readback');
 keys(snapshot.database,['migrations_sha256','schema_sha256','application_data_sha256','full_data_sha256','foreign_key_violations'],'D1 snapshot');need(snapshot.database.migrations_sha256&&typeof snapshot.database.migrations_sha256==='object'&&!Array.isArray(snapshot.database.migrations_sha256)&&Object.keys(snapshot.database.migrations_sha256).length<=11,'Migration readback missing or unbounded');for(const [name,hash]of Object.entries(snapshot.database.migrations_sha256)){need(/^migrations\/\d{4}_[a-z0-9_]+\.sql$/.test(name),'Malformed migration readback');digest(hash,'Migration readback');}digest(snapshot.database.schema_sha256,'Schema');digest(snapshot.database.application_data_sha256,'Complete normalized application data');digest(snapshot.database.full_data_sha256,'Complete D1 data');need(snapshot.database.foreign_key_violations===0,'D1 foreign-key violation');
 keys(snapshot.r2,['inventory_sha256','object_count'],'R2 snapshot');digest(snapshot.r2.inventory_sha256,'Complete R2 inventory');need(Number.isSafeInteger(snapshot.r2.object_count)&&snapshot.r2.object_count>=0,'R2 count invalid');
 need(snapshot.preserved&&equal(Object.keys(snapshot.preserved).sort(),['financial','immutable_history','object_bodies'].sort()),'Complete invariant projections required');for(const value of Object.values(snapshot.preserved))digest(value,'Preserved invariant');
 if(snapshot.worker!==null){keys(snapshot.worker,['source_id','bundle_sha256','configuration_sha256','version_id','deployment_id','traffic_percent','secret_names'],'Worker readback');for(const name of ['source_id','bundle_sha256','configuration_sha256'])digest(snapshot.worker[name],name);need(UUID.test(snapshot.worker.version_id)&&UUID.test(snapshot.worker.deployment_id)&&snapshot.worker.traffic_percent===100,'Ambiguous/partial Worker deployment');need(Array.isArray(snapshot.worker.secret_names)&&equal(snapshot.worker.secret_names,[...new Set(snapshot.worker.secret_names)].sort())&&snapshot.worker.secret_names.every(s=>/^[A-Z][A-Z0-9_]{0,79}$/.test(s)),'Secret-role readback invalid');}
 return snapshot;
}
function prefixOfKnown(actual,known){const names=Object.keys(known).sort(),entries=Object.entries(actual);return entries.length<=names.length&&equal(Object.keys(actual).sort(),names.slice(0,entries.length))&&entries.every(([k,v])=>known[k]===v);}
function stateProjection(snapshot){const {observed_at,raw_readback_sha256,...state}=snapshot;return state;}
export function classifyReadback(plan,action,before,after,expectedWorker=plan.baseline.worker){
 need(ACTIONS.includes(action),'Unknown operation');if(!equal(after.preserved,plan.baseline.preserved)||!equal(after.r2,plan.baseline.r2))return 'conflict';
 const db=after.database,migrations=plan.source.migrations,current=equal(db.migrations_sha256,migrations)&&db.schema_sha256===plan.compatibility.schema_after_sha256&&db.application_data_sha256===plan.compatibility.application_data_after_sha256;
 if(action==='migrate_current11'){
  if(!equal(after.worker,expectedWorker))return 'conflict';
  if(current)return 'verified';
  if(equal(stateProjection(before),stateProjection(after)))return 'not_applied';
  const count=String(Object.keys(db.migrations_sha256).length);return prefixOfKnown(db.migrations_sha256,migrations)&&db.schema_sha256===plan.compatibility.schema_prefix_sha256[count]&&db.application_data_sha256===plan.compatibility.application_data_prefix_sha256[count]?'partial':'conflict';
 }
 if(!current||!equal(db,before.database))return 'conflict';const worker=after.worker;
 if(worker&&worker.source_id===plan.source.source_id&&worker.bundle_sha256===plan.artifacts.bundle.sha256&&worker.configuration_sha256===plan.configuration_projection_sha256&&equal(worker.secret_names,plan.expected_secret_names))return 'verified';
 return equal(stateProjection(before),stateProjection(after))?'not_applied':'conflict';
}
export async function prepareBackendRelease(input,outputPath,env=process.env,trustedSource=null){
 const bounded=Object.hasOwn(input,'backend_source_manifest');keys(input,[...(bounded?['backend_source_manifest']:['source_export','source_manifest_sha256']),'release_manifest','operations_manifest','qualification','bundle','target_config','target','baseline','recovery','expected_secret_names','created_at','evidence_mode'],'Preparation');
 utc(input.created_at,'Plan time');need(['provider','simulation'].includes(input.evidence_mode),'Declare evidence mode');const target=validateTarget(input.target),support=await pinnedSupport(),source=bounded?await verifyBackendSourceAdmission(input.backend_source_manifest,trustedSource?.reviewed_backend_source_sha256):await verifySourceExport(input.source_export,input.source_manifest_sha256);
 if(bounded)for(const [name,path]of Object.entries(source.bound_artifact_paths))need(await physical(input[name])===path,'Bounded preparation must use its admitted '+name+' artifact');
 const release=await json(input.release_manifest),operations=await json(input.operations_manifest),qualification=await json(input.qualification),reviewed=await reviewBackendSource(source,release,operations,qualification);
 const targetFile=await json(input.target_config);need(targetFile.raw.equals(Buffer.from(canonical(targetFile.value)+'\n')),'Target config must be canonical JSON (no duplicate keys)');const stagingIdentity=stagingSourceIdentity(release.value.source_id_inputs,targetFile.value);validateStageConfig(targetFile.value,target,stagingIdentity.source_id);need(stagingIdentity.source_id!==reviewed.source_id,'Changed staging configuration requires a distinct source ID');
 const baseline=validateSnapshot(input.baseline,{target,mode:input.evidence_mode,fresh:false});need(baseline.worker===null&&Object.keys(baseline.database.migrations_sha256).length===0&&baseline.r2.object_count===0,'Initial scope requires a fresh isolated target');
 keys(input.recovery,['database_rollback','worker_rollback','roll_forward','evidence_sha256'],'Recovery');need(input.recovery.database_rollback==='forbidden_no_destructive_down_migration'&&input.recovery.worker_rollback==='unavailable_fresh_target_has_no_previous_worker'&&input.recovery.roll_forward==='same_current11_and_bundle_after_independent_readback_and_new_bound_approval','Unsupported/unreviewed rollback or roll-forward');digest(input.recovery.evidence_sha256,'Recovery evidence');
 need(equal(input.expected_secret_names,[]),'First deployment of the fresh target requires zero secret roles; provisioning/fixtures are a separate epoch');
 const bundle=await read(input.bundle,16*1024*1024);need(bundle.sha256===currentBackendProfile.bundle_sha256&&bundle.bytes===currentBackendProfile.bundle_bytes,'Bundle is outside the reviewed source/artifact profile');const out=await privateDirectory(resolve(outputPath),{create:true}),files={};
 const put=async(name,raw)=>{relativeName(name);await durable(join(out,name),raw);files[name]={sha256:sha256(raw),bytes:raw.length};};
 try{
  await put('wrangler.json',targetFile.raw);await put('bundle/index.js',bundle.raw);
  for(const name of Object.keys(reviewed.migrations).sort())await put(name,(await read(join(reviewed.base,name))).raw);
  for(const [name,file]of Object.entries({release,operations,qualification}))await put('evidence/'+name+'.json',file.raw);
  const {approvedCommand}=await import('./approved_toolchain.mjs');const admitted=await approvedCommand(['check','deploy','--bundle',join(out,'bundle/index.js'),'--config',join(out,'wrangler.json')],env);
  const derived=await deriveCompatibility(reviewed.base,reviewed.migrations);need(baseline.database.schema_sha256===derived.compatibility.schema_prefix_sha256['0']&&baseline.database.application_data_sha256===derived.compatibility.application_data_prefix_sha256['0'],'Fresh target contains unreviewed schema/application/authority state');await put('evidence/compatibility.json',Buffer.from(canonical(derived.evidence)+'\n'));
  // The already admitted parser only resolves and parses source. It never imports
  // app code or runs the handler inventory as JavaScript during preflight.
  const esbuild=createRequire(import.meta.url)(join(admitted.runtime.dependency_root,'node_modules/esbuild/lib/main.js'));let closure;
  try{const result=await esbuild.build({entryPoints:[join(reviewed.base,'src/index.js')],absWorkingDir:reviewed.base,bundle:true,write:false,metafile:true,format:'esm',platform:'browser',logLevel:'silent',logOverride:{'unsupported-dynamic-import':'warning'}});need(result.warnings.length===0&&Object.values(result.metafile.outputs).every(v=>v.imports.length===0),'Unresolved backend imports');closure=Object.keys(result.metafile.inputs).map(p=>relative(join(reviewed.base,'src'),resolve(reviewed.base,p)).split('\\').join('/')).sort();need(closure.every(p=>!p.startsWith('../')&&reviewed.inventory.source_sha256[p]),'Backend imports escape the bound source');for(const item of [...reviewed.inventory.operations,...reviewed.inventory.route_families])need(closure.includes(item.source),'Exported handler is missing from compiled import closure: '+item.source);
  }finally{esbuild.stop();}
  const self=await read(fileURLToPath(import.meta.url));const plan={format:'collect.backend.release-plan.v1',created_at:input.created_at,scope:'staging_remediation',evidence_mode:input.evidence_mode,target,
   source:{admission_kind:source.admission_kind??'whole_product_strict',...(bounded?{admission_manifest_path:source.admission_manifest_path,backend_path:source.backend_path,provenance_receipt_sha256:source.provenance_receipt_sha256,whole_product_verified:false}:{}),export_path:source.path,export_manifest_sha256:source.manifest_sha256,source_manifest_sha256:source.source_manifest_sha256,parent_api_source_id:reviewed.source_id,source_id:stagingIdentity.source_id,staging_source_identity_records:stagingIdentity.records,files:reviewed.files,migrations:reviewed.migrations,import_closure:closure,operations_sha256:operations.sha256,operation_count:89,route_family_count:10,scheduler:reviewed.scheduler,export_approvals:{...NO_APPROVAL}},
   artifacts:{bundle:{sha256:bundle.sha256,bytes:bundle.bytes},configuration:{sha256:targetFile.sha256,bytes:targetFile.bytes}},configuration_projection_sha256:sha256(canonical(projection(targetFile.value))),
   qualification:{sha256:qualification.sha256,source_bound_roles:qualification.value.sealed_candidate_roles_bound_to_suite,suite_tests:qualification.value.suite_tests},compatibility:derived.compatibility,recovery:input.recovery,baseline,expected_secret_names:input.expected_secret_names,
   operations:ACTIONS,files,support:{...support,'scripts/cloudflare/backend_release.mjs':{sha256:self.sha256,bytes:self.bytes}},toolchain:admitted,
   approval_supplied:false,production_go:false,provider_acceptance:false,scope_limits:['No new schema/profile or destructive database rollback','No keys, secret values, OTP delivery or policy activation','Staging/remediation approval is separate from whole production acceptance','Provider readback adapter and reviewed approval pin belong to the trusted publisher']};
  await durable(join(out,'plan.json'),Buffer.from(canonical(plan)+'\n'));return {package_path:out,plan_sha256:sha256(canonical(plan)+'\n'),plan};
 }catch(error){await durable(join(out,'preparation-failed.json'),Buffer.from(canonical({status:'refused',reason:error.message,provider_actions:0})+'\n'));throw error;}
}
export async function verifyBackendPlan(packagePath,expectedPlanSha256,env=process.env){
 const out=await privateDirectory(packagePath),file=await json(join(out,'plan.json'));need(file.sha256===digest(expectedPlanSha256,'Reviewed plan')&&file.raw.equals(Buffer.from(canonical(file.value)+'\n')),'Plan changed or is unbound');const plan=file.value;
 need(plan.format==='collect.backend.release-plan.v1'&&plan.scope==='staging_remediation'&&plan.approval_supplied===false&&plan.production_go===false&&equal(plan.operations,ACTIONS),'Unsupported release plan');validateTarget(plan.target);
 const support=await pinnedSupport(),self=await read(fileURLToPath(import.meta.url));need(equal(plan.support,{...support,'scripts/cloudflare/backend_release.mjs':{sha256:self.sha256,bytes:self.bytes}}),'Backend plan tool changed');
 for(const [name,record]of Object.entries(plan.files)){relativeName(name);const f=await read(join(out,name),16*1024*1024);need(equal(record,{sha256:f.sha256,bytes:f.bytes}),'Immutable package changed: '+name);}
 const observed=await recursiveFiles(out);delete observed['plan.json'];need(equal(observed,plan.files),'Package has extra or missing files');
 need(['whole_product_strict','api16_backend_only'].includes(plan.source.admission_kind),'Unknown source-admission path');const source=plan.source.admission_kind==='api16_backend_only'?await verifyBackendSourceAdmission(plan.source.admission_manifest_path,plan.source.export_manifest_sha256):await verifySourceExport(plan.source.export_path,plan.source.export_manifest_sha256);need(source.path===plan.source.export_path&&source.source_manifest_sha256===plan.source.source_manifest_sha256,'Source manifest changed');if(plan.source.admission_kind==='api16_backend_only')need(source.backend_path===plan.source.backend_path&&source.provenance_receipt_sha256===plan.source.provenance_receipt_sha256&&plan.source.whole_product_verified===false,'Bounded source scope/provenance changed');const config=(await json(join(out,'wrangler.json'))).value;validateStageConfig(config,plan.target,plan.source.source_id);
 const {approvedCommand}=await import('./approved_toolchain.mjs');const toolchain=await approvedCommand(['check','deploy','--bundle',join(out,'bundle/index.js'),'--config',join(out,'wrangler.json')],env);need(equal(toolchain,plan.toolchain),'Admitted command/runtime/config/bundle differs from plan');
 return {package_path:out,plan_sha256:file.sha256,plan};
}
export function validateApproval(approval,reviewedApprovalSha256,planSha256,plan,{action,recovery=null,now=Date.now()}={}){
 digest(reviewedApprovalSha256,'Independent reviewed approval pin');need(sha256(canonical(approval)+'\n')===reviewedApprovalSha256,'Approval does not match the independently supplied review pin');
 keys(approval,['format','approval_id','scope','plan_sha256','source_id','bundle_sha256','target_sha256','operations','issued_at','expires_at','review_evidence_sha256','recovery'],'Approval');
 need(approval.format==='collect.backend.release-approval.v1'&&UUID.test(approval.approval_id)&&approval.scope==='staging_remediation','Unsupported approval scope');need(approval.plan_sha256===planSha256&&approval.source_id===plan.source.source_id&&approval.bundle_sha256===plan.artifacts.bundle.sha256&&approval.target_sha256===sha256(canonical(plan.target)),'Stale source/artifact/target approval');
 const issued=utc(approval.issued_at,'Approval issue time'),expires=utc(approval.expires_at,'Approval expiry');need(issued<=now&&expires>now&&expires-issued<=86400000,'Stale, future or unbounded approval');digest(approval.review_evidence_sha256,'Separate review evidence');need(Array.isArray(approval.operations)&&approval.operations.length>0&&equal(approval.operations,[...new Set(approval.operations)].sort())&&approval.operations.every(a=>ACTIONS.includes(a))&&approval.operations.includes(action),'Operation outside reviewed approval');need(equal(approval.recovery,recovery),'Recovery approval is not bound to the prior intent and readback');return approval;
}
async function journalEvents(dir,planSha256){
 const names=(await readdir(dir)).filter(n=>n!=='.lock').sort(),events=[];let previous=null;
 for(let i=0;i<names.length;i++){need(names[i]===String(i+1).padStart(6,'0')+'.json','Unknown/gapped journal record');const f=await json(join(dir,names[i]));need(f.raw.equals(Buffer.from(canonical(f.value)+'\n'))&&f.value.sequence===i+1&&f.value.previous_sha256===previous&&f.value.plan_sha256===planSha256,'Journal integrity failure');events.push({...f.value,record_sha256:f.sha256});previous=f.sha256;}
 return events;
}
async function withJournal(journalPath,planSha256,fn){
 const dir=await privateDirectory(journalPath),lock=join(dir,'.lock');let owned=false,reclaimed=null;
 try{try{await durable(lock,Buffer.from(canonical({pid:process.pid,plan_sha256:planSha256,nonce:randomUUID()})+'\n'),0o600);owned=true;}catch(error){if(error.code!=='EEXIST')throw error;const held=await json(lock);need(held.value.plan_sha256===planSha256&&Number.isSafeInteger(held.value.pid)&&held.value.pid>0,'Unknown journal owner');let dead=false;try{process.kill(held.value.pid,0);}catch(signalError){dead=signalError.code==='ESRCH';}need(dead,'Another publication controller owns this journal');const again=await read(lock);need(again.sha256===held.sha256,'Journal lock changed');await unlink(lock);reclaimed={sha256:held.sha256,value:held.value};await durable(lock,Buffer.from(canonical({pid:process.pid,plan_sha256:planSha256,nonce:randomUUID(),reclaimed_lock_sha256:held.sha256})+'\n'),0o600);owned=true;}
  const events=await journalEvents(dir,planSha256);const append=async(event)=>{const item={...event,sequence:events.length+1,previous_sha256:events.at(-1)?.record_sha256??null,plan_sha256:planSha256,recorded_at:new Date().toISOString()},raw=Buffer.from(canonical(item)+'\n');await durable(join(dir,String(item.sequence).padStart(6,'0')+'.json'),raw);const result={...item,record_sha256:sha256(raw)};events.push(result);return result;};if(reclaimed)await append({type:'dead_controller_lock_reclaimed',previous_lock:reclaimed,provider_effects_inferred:false});return await fn(events,append);
 }finally{if(owned)await unlink(lock);}
}
function controllerContract(controller){need(controller&&typeof controller.readback==='function'&&['provider','simulation'].includes(controller.mode),'A trusted independent publication readback controller is required');need(controller.mode!=='simulation'||typeof controller.transport==='function','Simulation cannot launch a real provider command');digest(controller.reviewed_approval_sha256,'Independent reviewed approval pin');}
async function getReadback(controller,plan,phase){return validateSnapshot(await controller.readback({target:plan.target,phase,plan}),{target:plan.target,mode:controller.mode});}
function lastOutcome(events,intent){return events.filter(e=>e.type==='readback'&&e.intent_sha256===intent.record_sha256).at(-1);}
async function reconcileIntent(controller,plan,intent,events,append){
 // A later journaled deployment legitimately changes the Worker after migration.
 // Bind that exact already-verified version rather than downgrading a completed
 // migration, or accepting an unrelated current Worker merely by artifact hash.
 const laterDeploy=events.filter(e=>e.type==='readback'&&e.action==='deploy_bundle'&&e.status==='verified'&&e.sequence>intent.sequence).at(-1);
 const expectedWorker=intent.action==='migrate_current11'&&laterDeploy?laterDeploy.snapshot.worker:plan.baseline.worker;
 try{const snapshot=await getReadback(controller,plan,'reconcile'),status=classifyReadback(plan,intent.action,intent.before,snapshot,expectedWorker);return await append({type:'readback',intent_sha256:intent.record_sha256,action:intent.action,status,snapshot,origin:controller.mode,automatic_retry:false});}
 catch(error){return append({type:'readback_unavailable',intent_sha256:intent.record_sha256,action:intent.action,status:'unknown',reason:error.message,automatic_retry:false});}
}
async function fixedCommand(plan,packagePath,action,env){const {approvedCommand}=await import('./approved_toolchain.mjs');return approvedCommand(['check',action==='migrate_current11'?'migrate:remote':'deploy',...(action==='deploy_bundle'?['--bundle',join(packagePath,'bundle/index.js')]:[]),'--config',join(packagePath,'wrangler.json')],env);}
async function transport(command,env){
 const childEnv={...env,PATH:dirname(command.node.path)+':/usr/bin:/bin:/usr/sbin:/sbin',WRANGLER_SEND_METRICS:'false',WRANGLER_HIDE_BANNER:'true'};delete childEnv.NODE_OPTIONS;delete childEnv.NODE_PATH;delete childEnv.ESBUILD_BINARY_PATH;
 const result=await runLocal(command.node.path,command.command.argv,{cwd:command.command.cwd,env:childEnv});return {exit_code:result.code,signal:result.signal,stdout_sha256:sha256(result.stdout),stdout_bytes:result.stdout.length,stderr_sha256:sha256(result.stderr),stderr_bytes:result.stderr.length};
}
export async function reconcileBackendRelease({package_path,plan_sha256,journal_path,controller,env=process.env}){
 controllerContract(controller);const {plan}=await verifyBackendPlan(package_path,plan_sha256,env);need(controller.mode===plan.evidence_mode,'Evidence origin changed');
 return withJournal(journal_path,plan_sha256,async(events,append)=>{const intents=events.filter(e=>e.type==='intent');const results=[];for(const intent of intents)results.push(await reconcileIntent(controller,plan,intent,events,append));return {status:'readback_only',results,provider_mutations:0,automatic_retry:false,provider_acceptance:false,authority_scope:'Trusted publisher adapter projections; independent raw provider evidence remains required'};});
}
export async function executeBackendOperation({package_path,plan_sha256,journal_path,action,approval,controller,recovery=null,env=process.env}){
 controllerContract(controller);need(ACTIONS.includes(action),'Unknown backend operation');const {plan}=await verifyBackendPlan(package_path,plan_sha256,env);need(controller.mode===plan.evidence_mode,'Evidence origin changed');validateApproval(approval,controller.reviewed_approval_sha256,plan_sha256,plan,{action,recovery});
 return withJournal(journal_path,plan_sha256,async(events,append)=>{
  const previous=events.filter(e=>e.type==='intent'&&e.action===action).at(-1);
  if(previous&&recovery===null){const readback=await reconcileIntent(controller,plan,previous,events,append);return {status:readback.status,attempted:false,reason:'Existing intent requires readback; it is never resent',readback,provider_acceptance:false};}
  if(recovery!==null){keys(recovery,['intent_sha256','readback_sha256'],'Recovery binding');need(previous&&recovery.intent_sha256===previous.record_sha256,'Recovery intent mismatch');const outcome=lastOutcome(events,previous);need(outcome&&outcome.record_sha256===recovery.readback_sha256&&['partial','not_applied'].includes(outcome.status),'Recovery requires exact reconciled non-success outcome');need(!events.some(e=>e.type==='intent'&&e.approval_sha256===controller.reviewed_approval_sha256),'Recovery approval was already consumed');}
  const before=await getReadback(controller,plan,'before_operation');need(equal(before.preserved,plan.baseline.preserved)&&equal(before.r2,plan.baseline.r2),'Target invariant/data/object changes require independent recovery review');
  if(action==='migrate_current11'){
   need(equal(before.worker,plan.baseline.worker),'Worker changed before schema prerequisite');
   if(recovery===null)need(equal(stateProjection(before),stateProjection(plan.baseline)),'Fresh target preimage changed');
   else{const outcome=lastOutcome(events,previous),count=Object.keys(before.database.migrations_sha256).length;need(equal(stateProjection(before),stateProjection(outcome.snapshot))&&prefixOfKnown(before.database.migrations_sha256,plan.source.migrations)&&before.database.schema_sha256===plan.compatibility.schema_prefix_sha256[String(count)]&&before.database.application_data_sha256===plan.compatibility.application_data_prefix_sha256[String(count)]&&!equal(before.database.migrations_sha256,plan.source.migrations),'Partial migration state changed or is already complete');}
  }else{
   need(equal(before.database.migrations_sha256,plan.source.migrations)&&before.database.schema_sha256===plan.compatibility.schema_after_sha256&&before.database.application_data_sha256===plan.compatibility.application_data_after_sha256,'Approved current11 migration prerequisite is not satisfied');
   const migration=events.filter(e=>e.type==='intent'&&e.action==='migrate_current11').at(-1),outcome=migration&&lastOutcome(events,migration);need(outcome?.status==='verified'&&equal(before.database,outcome.snapshot.database),'Migration completion/readback or database data fence changed');
   if(recovery===null)need(equal(before.worker,plan.baseline.worker),'Worker baseline changed');else need(equal(stateProjection(before),stateProjection(lastOutcome(events,previous).snapshot)),'Deployment recovery preimage changed');
  }
  const command=await fixedCommand(plan,package_path,action,env);validateApproval(approval,controller.reviewed_approval_sha256,plan_sha256,plan,{action,recovery});validateSnapshot(before,{target:plan.target,mode:controller.mode});const intent=await append({type:'intent',operation_id:randomUUID(),action,approval_sha256:controller.reviewed_approval_sha256,recovery,before,command,command_sha256:sha256(canonical(command)),origin:controller.mode});
  // From this durable intent onward, no exception is interpreted as no effect.
  // Always retain the attempted operation and read back before any possible new
  // separately approved recovery attempt. No CLI output is treated as readback.
  let result;try{result=await (controller.transport??transport)(command,env);await append({type:'command_returned',intent_sha256:intent.record_sha256,action,result});}catch(error){result={outcome:'unknown',reason:error.message};await append({type:'command_lost_reply',intent_sha256:intent.record_sha256,action,result});}
  const readback=await reconcileIntent(controller,plan,intent,events,append);return {status:readback.status,attempted:true,origin:controller.mode,intent_sha256:intent.record_sha256,command_result:result,readback,automatic_retry:false,provider_acceptance:false,authority_scope:'Trusted publisher adapter projections; independent raw provider evidence remains required'};
 });
}
if(process.argv[1]&&pathToFileURL(resolve(process.argv[1])).href===import.meta.url){
 process.stderr.write('Use the reviewed publication controller API. This module has no unattended mutation or approval-pin CLI.\n');process.exitCode=2;
}
