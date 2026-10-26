#!/usr/bin/env node
// Local, immutable preparation only. No provider client or remote execution command.
import {createHash} from 'node:crypto';
import {open,lstat,realpath,mkdir,readdir,readlink} from 'node:fs/promises';
import {constants as fsConstants} from 'node:fs';
import {resolve,dirname,join} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {createRequire} from 'node:module';
import {DatabaseSync} from 'node:sqlite';
import {unseal,validatePayload,installSnapshotSql,restoreSql,main as backupMain} from './platform_backup.mjs';
import {applyRecoveryQuarantine} from './recovery_quarantine.mjs';

const FORMAT='collect.atomic-d1-restore.v1',PRIMARY='a6a0d284-c445-4fe3-8e64-af5fd42491ae';
const ACCOUNT='2209b915a85b1c11cee79b7806c6e73b',SHA=/^[a-f0-9]{64}$/;
const UUID=/^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
const MAX=128*1024*1024,MAX_STATEMENTS=4096,MAX_TABLES=256,MAX_ROWS=20000;
const sha=value=>createHash('sha256').update(value).digest('hex');
const required=(ok,message)=>{if(!ok)throw new Error(message);};
const exact=(value,keys)=>value&&typeof value==='object'&&!Array.isArray(value)&&Object.keys(value).length===keys.length&&keys.every(k=>Object.hasOwn(value,k));
const json=raw=>JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(raw));
const canonical=value=>JSON.stringify(value);
const record=raw=>({sha256:sha(raw),bytes:raw.length});
async function physical(path){let part='/';for(const name of resolve(path).split('/').filter(Boolean)){part=join(part,name);required(!(await lstat(part)).isSymbolicLink(),'Physical paths without aliases are required');}return realpath(path);}
async function regular(path,{privateFile=true,max=MAX,independent=true}={}){
 const p=await physical(path),file=await open(p,fsConstants.O_RDONLY|fsConstants.O_NOFOLLOW);
 try{const before=await file.stat();required(before.isFile()&&(!independent||before.nlink===1)&&before.size<=max,'Expected a bounded independent regular file');if(privateFile)required((before.mode&0o077)===0,'Private input permissions are required');
  const raw=await file.readFile(),after=await file.stat(),named=await lstat(p);
  required([after,named].every(s=>s.dev===before.dev&&s.ino===before.ino&&s.size===before.size&&s.mtimeMs===before.mtimeMs&&s.ctimeMs===before.ctimeMs&&s.nlink===before.nlink)&&!named.isSymbolicLink(),'Input changed during capture');return raw;
 }finally{await file.close();}
}
async function exclusive(path,raw){const file=await open(path,'wx',0o600);try{await file.writeFile(raw);await file.sync();}finally{await file.close();}}
async function fresh(path){await physical(dirname(resolve(path)));await mkdir(path,{mode:0o700});required(((await lstat(path)).mode&0o077)===0,'Private output directory required');return physical(path);}
function sourceDatabaseIds(databaseId,provenance){
 required(provenance===null||typeof provenance==='object'&&!Array.isArray(provenance),'Source provenance must remain an explicit object or null');
 const ids=[databaseId];for(const name of ['actual_provider_source_database_id','modeled_database_id']){const value=provenance?.[name];if(value!==null&&value!==undefined){required(UUID.test(value),'Invalid authenticated provenance source UUID');ids.push(value);}}
 return [...new Set(ids)].sort();
}
function targetIdentity(target,sources){
 required(exact(target,['account_id','database_name','database_id'])&&target.account_id===ACCOUNT&&UUID.test(target.database_id)&&/^[a-z][a-z0-9-]{2,62}$/.test(target.database_name),'An exact isolated Ikanisa destination is required');
 required(target.database_id!==PRIMARY&&!sources.includes(target.database_id)&&target.database_name!=='collect-platform','Primary/source destinations are forbidden');
 return target;
}
async function inventory(path,prefix='node_modules'){
 const result=[];for(const entry of await readdir(path,{withFileTypes:true})){const p=join(path,entry.name),name=prefix+'/'+entry.name;if(entry.isDirectory())result.push(...await inventory(p,name));else{required(entry.isFile()||entry.isSymbolicLink(),'Unsupported runtime entry');result.push(name);}}return result.sort();
}
export async function verifyAtomicRuntime(runtime){
 required(exact(runtime,['node_path','dependency_root','manifest_path','manifest_sha256'])&&SHA.test(runtime.manifest_sha256),'Pinned complete runtime inputs are required');
 const manifestRaw=await regular(runtime.manifest_path),manifest=json(manifestRaw);required(sha(manifestRaw)===runtime.manifest_sha256,'Runtime manifest pin differs');
 const node=await physical(runtime.node_path),root=await physical(runtime.dependency_root);required(node===process.execPath,'Use the pinned running Node executable');
 const names=Object.keys(manifest).sort();required(names.length>=5&&names.length<=10000&&names.includes('node')&&names.every(name=>name==='node'||/^node_modules\/[A-Za-z0-9@._+\/-]+$/.test(name)&&!name.split('/').includes('..')),'Invalid runtime manifest paths');
 const actual=await inventory(join(root,'node_modules'));required(canonical(actual)===canonical(names.filter(name=>name!=='node')),'Runtime file inventory differs');
 for(const name of names){const p=name==='node'?node:join(root,name),expected=manifest[name],s=await lstat(p);
  if(exact(expected,['symlink']))required(s.isSymbolicLink()&&await readlink(p)===expected.symlink,'Runtime alias differs');
  else{required(exact(expected,['sha256','bytes'])&&SHA.test(expected.sha256)&&Number.isSafeInteger(expected.bytes)&&expected.bytes>=0&&!s.isSymbolicLink(),'Invalid runtime file record');const raw=await regular(p,{privateFile:false,max:256*1024*1024,independent:false});required(raw.length===expected.bytes&&sha(raw)===expected.sha256,'Runtime file bytes differ');}
 }
 const roles={parser:'node_modules/wrangler/wrangler-dist/cli.js',wrangler:'node_modules/wrangler/package.json',miniflare:'node_modules/miniflare/dist/src/index.js',esbuild:'node_modules/esbuild/lib/main.js'};
 required(Object.values(roles).every(name=>Object.hasOwn(manifest,name)),'Runtime lacks a required locked role');
 required(json(await regular(join(root,roles.wrangler),{privateFile:false})).version==='4.151.0','Use locked Wrangler 4.151.0');
 const parserPath=join(root,roles.parser),split=createRequire(import.meta.url)(parserPath).unstable_splitSqlQuery;required(typeof split==='function','Official locked Wrangler SQL parser unavailable');
 return {split,pin:{...runtime,roles:Object.fromEntries(Object.entries(roles).map(([name,path])=>[name,{path:join(root,path),...manifest[path]}]))},manifest};
}
const catalogSQL="SELECT type,name,tbl_name,sql FROM sqlite_schema WHERE name NOT LIKE '_cf_%' AND (name NOT LIKE 'sqlite_%' OR name='sqlite_sequence') ORDER BY type,name";
const tableRows=rows=>rows.map(row=>[row.type,row.name,row.tbl_name,row.sql]);
function snapshot(db,descriptors){return sha(canonical([tableRows(db.prepare(catalogSQL).all()),descriptors.map(d=>[d.name,db.prepare(d.sql).all().map(row=>row.row).sort()])]));}
function projections(db,quarantined){
 const tables=db.prepare("SELECT name FROM sqlite_schema WHERE type='table' AND (name NOT LIKE 'sqlite_%' OR name='sqlite_sequence') AND name NOT LIKE '_cf_%' ORDER BY name").all();
 required(tables.length>0&&tables.length<=MAX_TABLES,'Atomic table bound exceeded');let total=0;
 return tables.map(({name})=>{required(/^[a-z][a-z0-9_]*$/.test(name),'Unexpected table identifier');
  const count=Math.max(db.prepare('SELECT count(*) AS n FROM "'+name+'"').get().n,quarantined.prepare('SELECT count(*) AS n FROM "'+name+'"').get().n);total+=count;required(total<=MAX_ROWS,'Atomic row bound exceeded');
  const columns=db.prepare('PRAGMA table_info("'+name+'")').all().map(r=>r.name);required(columns.length>0&&columns.every(c=>/^[a-z][a-z0-9_]*$/.test(c)),'Unexpected column identifier');
  const values=columns.map(c=>'json_array(typeof("'+c+'"),CASE WHEN typeof("'+c+'")=\'blob\' THEN lower(hex("'+c+'")) ELSE "'+c+'" END)');
  return {name,rows_bound:count+1,sql:'SELECT json_array('+values.join(',')+') AS row FROM "'+name+'" LIMIT '+(count+1)};
 });
}
function boundedStatements(statements){
 required(Array.isArray(statements)&&statements.length>0&&statements.length<=MAX_STATEMENTS,'Atomic statement bound exceeded');
 let total=0;for(const item of statements){required(exact(item,['sql','params'])&&typeof item.sql==='string'&&Array.isArray(item.params)&&item.params.length<=100,'Invalid fixed statement');
  const size=Buffer.byteLength(item.sql);total+=size;required(size>0&&size<=100000&&total<=64*1024*1024,'Atomic SQL byte bound exceeded');
  required(!/^\s*(?:BEGIN|COMMIT|END|ROLLBACK|SAVEPOINT|RELEASE|ATTACH|DETACH)\b/i.test(item.sql)&&!/^\s*PRAGMA\s+(?:foreign_keys|writable_schema)\s*=/i.test(item.sql),'Unsupported transaction or constraint override');
  required(item.params.every(v=>v===null||typeof v==='string'||typeof v==='number'&&Number.isSafeInteger(v)),'Invalid fixed bound parameter');
 }
 return statements;
}
function preimageGuards(db,descriptors){
 const queries=["SELECT json_group_array(CAST(json_array(type,name,tbl_name,sql) AS TEXT)||'') AS value FROM ("+catalogSQL+")",...descriptors.map(d=>"SELECT json_group_array(CAST(row AS TEXT)||'') AS value FROM (SELECT row FROM ("+d.sql+") ORDER BY row COLLATE BINARY)")];
 const guards=[];
 for(let offset=0;offset<queries.length;offset+=8){const group=queries.slice(offset,offset+8),params=group.map(sql=>db.prepare(sql).get().value);required(params.every(v=>typeof v==='string'&&Buffer.byteLength(v)<=1000000),'Atomic preimage parameter bound exceeded');
  guards.push({sql:"SELECT json(CASE WHEN "+group.map(sql=>'('+sql+')=? COLLATE BINARY').join(' AND ')+" THEN '[]' ELSE 'atomic_preimage_changed' END) AS atomic_preimage_guard",params});
 }
 return guards;
}
function action(statements,requiredState,expectedState){boundedStatements(statements);return {required_state:requiredState,expected_state:expectedState,statement_count:statements.length,statements_sha256:sha(canonical(statements)),statements};}
async function moduleInputs(){const names=['atomic_d1_restore.mjs','platform_backup.mjs','recovery_quarantine.mjs','sql_snapshot_import.mjs'];const result={};for(const name of names)result['scripts/cloudflare/'+name]=record(await regular(fileURLToPath(new URL(name,import.meta.url)),{privateFile:false}));result['deploy/platform-api/src/identity_keys.js']=record(await regular(fileURLToPath(new URL('../../deploy/platform-api/src/identity_keys.js',import.meta.url)),{privateFile:false}));return result;}
function assertPlan(plan,pin){
 required(SHA.test(pin)&&sha(canonical(plan))===pin,'Plan pin differs');
 required(plan?.format===FORMAT&&plan.provider_actions_executed===false&&plan.full_system_recovery_accepted===false,'Unsupported plan');targetIdentity(plan.target,sourceDatabaseIds(plan.archive.database_id,plan.archive.source_provenance));
 for(const name of ['restore','late_failure','quarantine','replay']){const a=plan.actions[name];boundedStatements(a?.statements);required(a.statement_count===a.statements.length&&sha(canonical(a.statements))===a.statements_sha256,'Fixed SQL pin differs');}
 for(const name of ['quarantine','replay'])required(canonical(plan.actions[name].statements.slice(-plan.quarantine_plan.statements.length))===canonical(plan.quarantine_plan.statements),'Action differs from exact quarantine');
}
export async function prepareAtomicD1Restore(input,outDirectory){
 required(exact(input,['archive_path','key_path','qualified_restore_sql_path','qualified_quarantine_plan_path','target','runtime']),'Use the exact atomic preparation fields');
 const runtime=await verifyAtomicRuntime(input.runtime),inputs={};
 for(const key of ['archive_path','key_path','qualified_restore_sql_path','qualified_quarantine_plan_path'])inputs[key]=await regular(input[key]);
 const keyText=inputs.key_path.toString().trim(),key=Buffer.from(keyText,'base64');required(key.length===32&&key.toString('base64')===keyText,'Invalid private recovery key');
 let payload;try{payload=unseal(json(inputs.archive_path),key);}finally{key.fill(0);}
 const files=validatePayload(payload),sourceConfig=json(files['wrangler.json']),quarantine=json(inputs.qualified_quarantine_plan_path),target=targetIdentity(input.target,sourceDatabaseIds(payload.database_id,sourceConfig.synthetic_fixture_provenance??null)),out=await fresh(outDirectory);
 const common=['--archive',input.archive_path,'--key',input.key_path];
 // Reuse exact authenticated schema/profile admission; never trust a claimed receipt.
 await backupMain(['prepare-quarantine',...common,'--operation',quarantine.operation_id,'--at',quarantine.created_at,'--out',join(out,'schema-admission')],{splitSqlQuery:runtime.split});
 required(canonical(json(await regular(join(out,'schema-admission/quarantine-plan.json'))))===canonical(quarantine),'Qualified quarantine plan differs');
 const baseline=new DatabaseSync(':memory:',{enableForeignKeyConstraints:false}),final=new DatabaseSync(':memory:',{enableForeignKeyConstraints:false});
 let plan;
 try{
  installSnapshotSql(baseline,files['database.sql'].toString(),runtime.split);required(baseline.prepare('PRAGMA integrity_check').get().integrity_check==='ok'&&baseline.prepare('PRAGMA foreign_key_check').all().length===0,'Authenticated snapshot is inconsistent');
  const normalized=Buffer.from(restoreSql(baseline));required(normalized.equals(inputs.qualified_restore_sql_path),'Restore SQL differs from exact authenticated archive normalization');
  await backupMain(['verify-readback',...common,'--sql',input.qualified_restore_sql_path,'--out',join(out,'restore-admission')],{splitSqlQuery:runtime.split});
  installSnapshotSql(final,files['database.sql'].toString(),runtime.split);applyRecoveryQuarantine(final,quarantine);
  const descriptors=projections(baseline,final),catalog=tableRows(baseline.prepare(catalogSQL).all()),restored=snapshot(baseline,descriptors),quarantined=snapshot(final,descriptors);
  const emptyGuard={sql:"SELECT json(CASE WHEN NOT EXISTS(SELECT 1 FROM sqlite_schema WHERE name NOT LIKE '_cf_%') THEN '[]' ELSE 'atomic_target_not_empty' END) AS atomic_empty_guard",params:[]};
  const restore=[emptyGuard,...runtime.split(normalized.toString()).map(sql=>({sql,params:[]}))],sourceGuards=preimageGuards(baseline,descriptors),finalGuards=preimageGuards(final,descriptors);
  const guardedQuarantine=[...sourceGuards,...quarantine.statements],late=[...guardedQuarantine,{sql:'INSERT INTO admin_bridge_guards(id,passed) VALUES(?,0)',params:['atomic-late-check:'+quarantine.operation_id]}];
  plan={format:FORMAT,target,archive:{sha256:sha(inputs.archive_path),database_id:payload.database_id,source_id:payload.source_id,captured_at:payload.captured_at,
   source_provenance:sourceConfig.synthetic_fixture_provenance??null,provider_source_capture_asserted_by_this_tool:false},
   input_files:Object.fromEntries(Object.entries(inputs).map(([name,raw])=>[name,{path:resolve(input[name]),...record(raw)}])),
   schema_profile:quarantine.schema_profile??'published9',quarantine_plan:quarantine,runtime:runtime.pin,tool_inputs:await moduleInputs(),
   readback:{catalog_sql:catalogSQL,catalog,descriptors,restored_sha256:restored,quarantined_sha256:quarantined},
   actions:{restore:action(restore,'empty','restored'),late_failure:action(late,'restored','restored'),quarantine:action(guardedQuarantine,'restored','quarantined'),replay:action([...finalGuards,...quarantine.statements],'quarantined','quarantined')},
   external_preconditions:['Fresh authenticated provider account/name/UUID readback must equal target and deny primary/source before each mutation.','Verify complete runtime and generated package hashes immediately before starting only a private loopback remote binding.','Capture complete unfiltered provider SQL after each attempted action; run the unchanged exact snapshot verifier before proceeding.','Unknown outcomes require readback; never automatically retry, rebind or substitute a different plan.'],
   provider_actions_executed:false,RPO_RTO_accepted:false,production_cutover_accepted:false,full_system_recovery_accepted:false};
 }finally{baseline.close();final.close();}
 for(const [name,raw]of Object.entries(inputs))required((await regular(input[name])).equals(raw),'Preparation input changed');
 await verifyAtomicRuntime(input.runtime);required(canonical(await moduleInputs())===canonical(plan.tool_inputs),'Tool source changed during preparation');
 const pin=sha(canonical(plan));assertPlan(plan,pin);
 const worker=Buffer.from('const plan='+canonical(plan)+';\nexport default ('+workerFactory.toString()+')(plan,'+JSON.stringify(pin)+');\n');
 const config={name:'collect-isolated-atomic-recovery',main:'worker.js',account_id:target.account_id,compatibility_date:'2026-10-14',workers_dev:false,preview_urls:false,dev:{ip:'127.0.0.1',inspector_ip:'127.0.0.1',local_protocol:'http'},
  vars:{TARGET_DATABASE_ID:target.database_id,SOURCE_ID:plan.archive.source_id,PLAN_SHA256:pin},d1_databases:[{binding:'DB',database_name:target.database_name,database_id:target.database_id,remote:true}],observability:{enabled:false}};
 const artifacts={'plan.json':Buffer.from(canonical(plan)+'\n'),'worker.js':worker,'wrangler.json':Buffer.from(canonical(config)+'\n')};
 for(const [name,raw]of Object.entries(artifacts))await exclusive(join(out,name),raw);
 const manifest={format:FORMAT,plan_sha256:pin,target,files:Object.fromEntries(Object.entries(artifacts).map(([name,raw])=>[name,record(raw)])),private_token_file_included:false,
  provider_execution_supported_by_this_CLI:false,remote_binding_started:false,full_system_recovery_accepted:false};
 await exclusive(join(out,'package-manifest.json'),Buffer.from(canonical(manifest)+'\n'));
 return {directory:out,plan_sha256:pin,manifest_sha256:sha(canonical(manifest)+'\n'),target,source_id:plan.archive.source_id,schema_profile:plan.schema_profile};
}

// This function is emitted verbatim into the private, source-pinned Worker.
// It receives fixed statements only; the request protocol has no SQL/params fields.
// D1 supports quick_check; the unchanged offline verifier retains integrity_check.
function workerFactory(plan,pin){
 const reply=(value,status=200)=>Response.json(value,{status,headers:{'Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer'}});
 const sha=async value=>[...new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value)))].map(b=>b.toString(16).padStart(2,'0')).join('');
 const keys=(value,names)=>value&&typeof value==='object'&&!Array.isArray(value)&&Object.keys(value).length===names.length&&names.every(name=>Object.hasOwn(value,name));
 let busy=false,checkpoint=null,needsReadback=true;const attempted=new Set();
 async function readback(db){
  const initial=await db.batch([db.prepare(plan.readback.catalog_sql),db.prepare('PRAGMA foreign_keys'),db.prepare('PRAGMA foreign_key_check'),db.prepare('PRAGMA quick_check')]);
  if(initial.some(r=>r.success!==true)||initial[1].results[0]?.foreign_keys!==1||initial[2].results.length||initial[3].results.length!==1||initial[3].results[0].quick_check!=='ok')throw Error('readback_constraint_fence');
  const catalog=initial[0].results.map(r=>[r.type,r.name,r.tbl_name,r.sql]);
  if(catalog.length===0)return {state:'empty',sha256:await sha('empty'),foreign_keys:1,foreign_key_errors:0,quick_check:'ok'};
  if(JSON.stringify(catalog)!==JSON.stringify(plan.readback.catalog))return {state:'conflicting',sha256:await sha(JSON.stringify(catalog)),foreign_keys:1,foreign_key_errors:0,quick_check:'ok'};
  const rows=await db.batch(plan.readback.descriptors.map(d=>db.prepare(d.sql)));if(rows.some(r=>r.success!==true))throw Error('readback_query_fence');
  const projections=rows.map((r,i)=>[plan.readback.descriptors[i].name,r.results.map(row=>row.row).sort()]);
  const digest=await sha(JSON.stringify([catalog,projections]));
  return {state:digest===plan.readback.quarantined_sha256?'quarantined':digest===plan.readback.restored_sha256?'restored':'conflicting',sha256:digest,table_count:rows.length,foreign_keys:1,foreign_key_errors:0,quick_check:'ok'};
 }
 return {async fetch(request,env){
  const url=new URL(request.url);
  if(request.method!=='POST'||request.headers.has('Origin')||request.headers.has('Sec-Fetch-Site')&&request.headers.get('Sec-Fetch-Site')!=='none'||url.search||!['127.0.0.1','localhost','[::1]'].includes(url.hostname)||
   !/^[A-Za-z0-9_-]{32,256}$/.test(env.CAPTURE_TOKEN??'')||request.headers.get('Authorization')!=='Bearer '+env.CAPTURE_TOKEN)return reply({code:'denied'},403);
  if(env.TARGET_DATABASE_ID!==plan.target.database_id||env.SOURCE_ID!==plan.archive.source_id||env.PLAN_SHA256!==pin||await sha(JSON.stringify(plan))!==pin)return reply({code:'binding_or_plan_fence'},409);
  if(!['/readback','/restore','/late_failure','/quarantine','/replay'].includes(url.pathname))return reply({code:'unknown_action'},404);
  let body;try{
   const reader=request.body?.getReader(),chunks=[];let size=0;
   if(reader)for(;;){const {value,done}=await reader.read();if(done)break;size+=value.length;if(size>1024){await reader.cancel();return reply({code:'input_bound'},400);}chunks.push(value);}
   const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}body=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));
  }catch{return reply({code:'input'},400);}
  const name=url.pathname.slice(1),read=name==='readback';
  if(!keys(body,read?['plan_sha256']:['plan_sha256','action_sha256','checkpoint_sha256']))return reply({code:'input'},400);
  if(body.plan_sha256!==pin)return reply({code:'plan_fence'},409);
  if(busy)return reply({code:'operation_busy'},409);busy=true;
  try{
   if(read){checkpoint=await readback(env.DB);needsReadback=false;return reply({plan_sha256:pin,target_database_id:plan.target.database_id,...checkpoint,provider_identity_proven:false,external_full_SQL_readback_required:true});}
   const action=plan.actions[name];
   if(body.action_sha256!==action.statements_sha256||await sha(JSON.stringify(action.statements))!==action.statements_sha256)return reply({code:'fixed_SQL_fence'},409);
   if(attempted.has(name))return reply({code:'already_attempted_readback_required'},409);
   if(needsReadback||!checkpoint||body.checkpoint_sha256!==checkpoint.sha256)return reply({code:'readback_checkpoint_required'},409);
   const actual=await readback(env.DB);
   if(actual.sha256!==checkpoint.sha256||actual.state!==action.required_state){checkpoint=null;needsReadback=true;return reply({code:'target_state_changed_readback_required'},409);}
   attempted.add(name);checkpoint=null;needsReadback=true;
   try{
    // All deferred FK and cyclic MFA writes remain inside this single batch.
    const result=await env.DB.batch(action.statements.map(s=>env.DB.prepare(s.sql).bind(...s.params)));
    if(result.some(r=>r.success!==true))throw Error('batch_result_unknown');
    return reply({code:'batch_acknowledged_readback_required',action:name,plan_sha256:pin,statement_count:action.statement_count,authoritative_outcome_verified:false});
   }catch(error){const message=String(error?.message??error);return reply({code:'batch_error_outcome_unverified',action:name,expected_late_CHECK:name==='late_failure'&&message.includes('CHECK constraint failed: admin_bridge_state'),error_sha256:await sha(message),authoritative_outcome_verified:false,readback_required:true},422);}
  }catch{checkpoint=null;needsReadback=true;return reply({code:'readback_failed_outcome_unverified',readback_required:true},503);}
  finally{busy=false;}
 }};
}
export async function verifyAtomicPackage(directory,manifestPin){
 const out=await physical(directory),raw=await regular(join(out,'package-manifest.json'));required(SHA.test(manifestPin)&&sha(raw)===manifestPin,'Package manifest pin differs');
 const manifest=json(raw);required(manifest.format===FORMAT&&exact(manifest.files,['plan.json','worker.js','wrangler.json']),'Unsupported package manifest');
 for(const [name,expected]of Object.entries(manifest.files)){const bytes=await regular(join(out,name));required(canonical(record(bytes))===canonical(expected),'Package file bytes differ');}
 const plan=json(await regular(join(out,'plan.json')));assertPlan(plan,manifest.plan_sha256);required(canonical(plan.target)===canonical(manifest.target),'Package target differs');
 required(canonical(await moduleInputs())===canonical(plan.tool_inputs),'Tool source differs from preparation');
 await verifyAtomicRuntime({node_path:plan.runtime.node_path,dependency_root:plan.runtime.dependency_root,manifest_path:plan.runtime.manifest_path,manifest_sha256:plan.runtime.manifest_sha256});
 for(const [name,input]of Object.entries(plan.input_files)){const bytes=await regular(input.path);required(canonical(record(bytes))===canonical({sha256:input.sha256,bytes:input.bytes}),'Authenticated input bytes differ: '+name);}
 const config=json(await regular(join(out,'wrangler.json')));required(config.d1_databases?.length===1&&config.d1_databases[0].database_id===plan.target.database_id&&config.account_id===plan.target.account_id&&config.dev?.ip==='127.0.0.1'&&config.dev?.inspector_ip==='127.0.0.1'&&config.vars?.PLAN_SHA256===manifest.plan_sha256,'Binding package differs');
 return {plan,manifest};
}
export async function verifyAtomicReadback({directory,manifest_sha256,archive_path,key_path,sql_path,stage,out_directory}){
 const {plan}=await verifyAtomicPackage(directory,manifest_sha256);required(['restored','quarantined'].includes(stage),'Use an exact restored or quarantined stage');
 required(sha(await regular(archive_path))===plan.archive.sha256&&sha(await regular(key_path))===plan.input_files.key_path.sha256,'Readback archive/key differs');
 const args=[stage==='restored'?'verify-readback':'verify-quarantine-readback','--archive',archive_path,'--key',key_path,'--sql',sql_path,'--out',out_directory];
 if(stage==='quarantined')args.push('--plan',plan.input_files.qualified_quarantine_plan_path.path);
 const runtime=await verifyAtomicRuntime({node_path:plan.runtime.node_path,dependency_root:plan.runtime.dependency_root,manifest_path:plan.runtime.manifest_path,manifest_sha256:plan.runtime.manifest_sha256});
 await backupMain(args,{splitSqlQuery:runtime.split});
 return {stage,all_snapshot_rows_and_schema_verified:true,remote_execution_proven_by_this_offline_check:false,RPO_RTO_accepted:false,full_system_recovery_accepted:false};
}
export async function main(argv){
 const [command,...rest]=argv,options={};for(let i=0;i<rest.length;i+=2){required(rest[i]?.startsWith('--')&&rest[i+1]&&!Object.hasOwn(options,rest[i]),'Use unique named options');options[rest[i]]=rest[i+1];}
 if(command==='prepare'){required(exact(options,['--input','--out']),'prepare requires --input --out');return prepareAtomicD1Restore(json(await regular(options['--input'])),options['--out']);}
 if(command==='verify-package'){required(exact(options,['--package','--pin']),'verify-package requires --package --pin');const {manifest}=await verifyAtomicPackage(options['--package'],options['--pin']);return {verified:true,plan_sha256:manifest.plan_sha256,provider_execution:false};}
 if(command==='verify-readback'){required(exact(options,['--input']),'verify-readback requires --input');return verifyAtomicReadback(json(await regular(options['--input'])));}
 throw Error('Use prepare, verify-package or verify-readback. No provider execution, start, deploy or deletion command exists.');
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href)main(process.argv.slice(2)).then(result=>console.log(JSON.stringify(result))).catch(()=>{console.error('Atomic recovery preparation/verification failed; inspect private local inputs.');process.exitCode=1;});
