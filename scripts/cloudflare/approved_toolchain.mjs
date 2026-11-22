#!/usr/bin/env node
// Tool selection only. Source/artifact/target approval still belongs to the publisher.
import {createHash} from 'node:crypto';
import {open,lstat,realpath,readdir} from 'node:fs/promises';
import {constants} from 'node:fs';
import {spawn} from 'node:child_process';
import {dirname,isAbsolute,join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {createRequire} from 'node:module';

const sha=raw=>createHash('sha256').update(raw).digest('hex');
const required=(value,message)=>{if(!value)throw new Error(message);};
const apiRoot=fileURLToPath(new URL('../../deploy/platform-api/',import.meta.url));
// This reviewed profile is independent of the caller's manifest or PATH. A new
// platform, Node build, lockfile or vendor tree requires a separately reviewed pin.
export const approvedProfile=Object.freeze({
 id:'collect-node24.19.0-wrangler4.151.0-darwin-arm64-v1',platform:'darwin',arch:'arm64',
 node_version:'v24.19.0',node_sha256:'c3ec5c451750ec57acabfbc05c26de2fcad6dda84ab1b117a5c1eefaae28cbef',
 node_bytes:121304480,wrangler_version:'4.151.0',runtime_entries:1653,
 runtime_manifest_sha256:'ac8cd687ba9a7e6376f1884687fd9e4ab9594244a32de989ff5a0274476357f1',
 package_lock_sha256:'ac952e6c528c621591e62babb357501431fa030ac4e094596916a9ed4bc909b4',
});
const supportPins=Object.freeze({
 'scripts/cloudflare/atomic_d1_restore.mjs':'cfd27db9f87d3150f04b2a363bfaf0f5ee4515c463b7c9127fad10c51e1c5fb3',
 'scripts/cloudflare/platform_backup.mjs':'da4479894d2c5fa967d3ccd7e4b829e82a37cff9e8a265418ed79e45ce4cb708',
 'scripts/cloudflare/recovery_quarantine.mjs':'edf10e39d3df145ac3938fc9f6c2fbd37ab7500450d31ef8a8b2b332a73e74a1',
 'deploy/platform-api/src/identity_keys.js':'c0c9fbfb48b44c72c7192acd3853644349a000ba3e7fbf62fdc11037d5f6d4f7',
 'deploy/platform-api/src/core.js':'18ce95c133a4895d13475338089fb00c9ba4c9283ee72c7d4d6f88ae8ea8723e',
});
// Explicit successor support selection leaves the historical default pins intact.
const auth17SupportPins=Object.freeze({
 ...supportPins,
 'scripts/cloudflare/platform_backup.mjs':'bec0686c830eecc8c63a01ed4173113ff3d2fb752f975edb6f21942afad2d196',
 'scripts/cloudflare/recovery_quarantine.mjs':'776712f3be7a3750b1747c6b553d49e1c2c19ae8b6d81654dde22b855c83f506',
});
// Snapshot importer successor: historical/default profile maps above stay exact.
const snapshotSupportPins=Object.freeze({
 ...auth17SupportPins,
 'scripts/cloudflare/platform_backup.mjs':'8ade1b0dffc1eac284e05f8df925543747ebf0beebc52799d0552c5f4aa1bd7f',
 'scripts/cloudflare/atomic_d1_restore.mjs':'8d991daf660f46b4fa3a7c61987e45f95b4c9bce954ebd2093163ac777fa5827',
 'scripts/cloudflare/sql_snapshot_import.mjs':'50d1dbdd95fc35fab6efb4226f0975e696629120a4f92639f2eb6588ce1dbbbc',
});
export function reviewedSupportPins(profile=null){
 required(profile===null||profile==='auth17-candidate-v1'||profile==='auth17-snapshot-v2','Unknown reviewed support profile');
 return profile===null?supportPins:profile==='auth17-candidate-v1'?auth17SupportPins:snapshotSupportPins;
}
const sourceRoot=fileURLToPath(new URL('../../',import.meta.url));
function locator(value,label){required(typeof value==='string'&&value.length>0&&value.length<=4096&&isAbsolute(value)&&!/[\x00-\x1f\x7f]/.test(value),label+' must be an explicit absolute physical path');return resolve(value);}
async function physical(value){let part='/';for(const name of value.split('/').filter(Boolean)){part=join(part,name);required(!(await lstat(part)).isSymbolicLink(),'Physical paths without aliases are required');}return realpath(value);}
async function regular(value,{max=1024*1024,privateFile=false}={}){
 const path=await physical(value),file=await open(path,constants.O_RDONLY|constants.O_NOFOLLOW);
 try{const before=await file.stat();required(before.isFile()&&before.nlink===1&&before.size<=max,'A bounded independent regular input is required');if(privateFile)required((before.mode&0o077)===0&&before.uid===process.getuid(),'A private owned runtime manifest is required');
  const raw=await file.readFile(),after=await file.stat(),named=await lstat(path);
  required([after,named].every(s=>s.dev===before.dev&&s.ino===before.ino&&s.size===before.size&&s.mtimeMs===before.mtimeMs&&s.ctimeMs===before.ctimeMs&&s.nlink===before.nlink)&&!named.isSymbolicLink(),'Input changed during admission');return {path,raw};
 }finally{await file.close();}
}
export function parseApprovedCommand(argv){
 const args=[...argv];let checkOnly=args[0]==='check';if(checkOnly)args.shift();const action=args.shift();
 required(action==='deploy'||action==='migrate:remote','Use check (optional), then deploy or migrate:remote');
 let config=join(apiRoot,'wrangler.jsonc'),bundle=null,dryRun=false,outdir=null,supportProfile=null;const seen=new Set();
 while(args.length){const flag=args.shift();required(!seen.has(flag),'Duplicate command option');seen.add(flag);
  if(flag==='--support-profile'){supportProfile=args.shift();required(typeof supportProfile==='string','Explicit support profile required');reviewedSupportPins(supportProfile);}
  else if(flag==='--check'){required(!checkOnly,'Duplicate check option');checkOnly=true;}
  else if(flag==='--config')config=locator(args.shift(),'Config');
  else if(flag==='--bundle'){required(action==='deploy','Bundle is available only for deploy');bundle=locator(args.shift(),'Bundle');}
  else if(flag==='--dry-run'){required(action==='deploy','Dry-run is available only for deploy');dryRun=true;}
  else if(flag==='--outdir'){required(action==='deploy','Outdir is available only for deploy');outdir=locator(args.shift(),'Outdir');}
  else throw new Error('Unsupported command option');
 }
 required(dryRun===(outdir!==null),'Deploy dry-run requires an explicit empty private outdir');
 required(action!=='deploy'||bundle!==null&&seen.has('--config'),'Deploy requires explicit physical --bundle and --config from the reviewed immutable export');
 return {action,checkOnly,config,bundle,dryRun,outdir,...(supportProfile===null?{}:{supportProfile})};
}
export function assertReviewedHost({platform,arch,nodeVersion}){
 required(platform===approvedProfile.platform&&arch===approvedProfile.arch,'No reviewed toolchain profile exists for this host');
 required(nodeVersion===approvedProfile.node_version,'Use the reviewed Node v24.19.0 build');
}
export function reviewedWranglerVersion(raw){let version;try{version=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(raw)).version;}catch{throw new Error('Wrangler metadata is malformed or unknown');}required(version===approvedProfile.wrangler_version,'Use the reviewed Wrangler 4.151.0; unknown versions are denied');return version;}
export async function approvedCommand(argv,env=process.env){
 const request=parseApprovedCommand(argv);
 // esbuild reads the real process environment, while the admitted child receives
 // the caller environment. Neither may select a parser outside the pinned tree.
 required([process.env,env].every(input=>input.ESBUILD_BINARY_PATH===undefined||input.ESBUILD_BINARY_PATH===''),'ESBUILD_BINARY_PATH overrides are not admitted');
 assertReviewedHost({platform:process.platform,arch:process.arch,nodeVersion:process.version});
 const root=await physical(locator(env.COLLECT_APPROVED_DEPENDENCY_ROOT,'Approved dependency root'));
 const manifest=await regular(locator(env.COLLECT_APPROVED_RUNTIME_MANIFEST,'Approved runtime manifest'),{privateFile:true});
 required(sha(manifest.raw)===approvedProfile.runtime_manifest_sha256,'Runtime manifest is not the independently approved profile');
 const metadata=await regular(join(root,'node_modules/wrangler/package.json'));
 const version=reviewedWranglerVersion(metadata.raw);
 const node=await regular(process.execPath,{max:256*1024*1024});
 required(node.raw.length===approvedProfile.node_bytes&&sha(node.raw)===approvedProfile.node_sha256,'Running Node binary differs from the approved build');
 const lock=await regular(join(apiRoot,'package-lock.json'));
 required(sha(lock.raw)===approvedProfile.package_lock_sha256,'Committed package lock differs from the approved profile');
 const support={};for(const [name,pin]of Object.entries(reviewedSupportPins(request.supportProfile??null))){const input=await regular(join(sourceRoot,name));required(sha(input.raw)===pin,'Reviewed toolchain support source differs or is missing');support[name]={sha256:pin,bytes:input.raw.length};}
 // Import the existing recovery admission only after its bytes, Node and caller
 // metadata have been admitted. Never execute an unknown CLI to ask its version.
 const {verifyAtomicRuntime}=await import('./atomic_d1_restore.mjs');
 const runtime=await verifyAtomicRuntime({node_path:node.path,dependency_root:root,manifest_path:manifest.path,manifest_sha256:approvedProfile.runtime_manifest_sha256});
 required(Object.keys(runtime.manifest).length===approvedProfile.runtime_entries,'Approved runtime inventory count differs');
 const config=await regular(request.config),outdir=request.outdir===null?null:await physical(request.outdir);
 if(outdir!==null){const stat=await lstat(outdir);required(stat.isDirectory()&&stat.uid===process.getuid()&&(stat.mode&0o077)===0&&(await readdir(outdir)).length===0,'Dry-run outdir must be an owned empty private directory');}
 let bundle=null;if(request.bundle!==null){const input=await regular(request.bundle,{max:16*1024*1024}),esbuild=createRequire(import.meta.url)(join(root,'node_modules/esbuild/lib/main.js'));
  try{const text=new TextDecoder('utf-8',{fatal:true}).decode(input.raw),parsed=await esbuild.build({stdin:{contents:text,sourcefile:input.path,loader:'js'},absWorkingDir:dirname(input.path),bundle:false,write:false,metafile:true,format:'esm',platform:'neutral',logLevel:'silent',logOverride:{'unsupported-dynamic-import':'warning'}});
   required(parsed.warnings.length===0&&[...Object.values(parsed.metafile.inputs),...Object.values(parsed.metafile.outputs)].every(item=>item.imports.length===0),'Deploy bundle must be self-contained; source-module imports are not admitted');
  }finally{esbuild.stop();}
  bundle={path:input.path,sha256:sha(input.raw),bytes:input.raw.length,unresolved_imports:0};
 }
 const cli=join(root,'node_modules/wrangler/bin/wrangler.js');
 const command=request.action==='deploy'?['deploy',bundle.path,'--no-bundle','--strict','--config',config.path,...(request.dryRun?['--dry-run','--outdir',outdir]:[])]:['d1','migrations','apply','collect-platform','--remote','--config',config.path];
 return {format:'collect.approved-toolchain.command.v1',profile:approvedProfile.id,check_only:request.checkOnly,
  node:{path:node.path,version:process.version,sha256:sha(node.raw),bytes:node.raw.length},
  wrangler:{path:cli,version,sha256:runtime.manifest['node_modules/wrangler/bin/wrangler.js'].sha256},
  runtime:{dependency_root:root,manifest_path:manifest.path,manifest_sha256:approvedProfile.runtime_manifest_sha256,entries:approvedProfile.runtime_entries},
  source:{package_lock_sha256:approvedProfile.package_lock_sha256,support_inputs:support,...(request.supportProfile?{support_profile:request.supportProfile}:{})},
  config:{path:config.path,sha256:sha(config.raw),bytes:config.raw.length},
  bundle,
  command:{action:request.action,argv:[cli,...command],cwd:apiRoot,local_artifact_output:outdir},
  provider_actions_executed:false,source_artifact_target_approval_supplied_by_guard:false};
}
export async function main(argv,env=process.env){
 const plan=await approvedCommand(argv,env);process.stdout.write(JSON.stringify({status:'admitted',...plan})+'\n');
 if(plan.check_only)return 0;
 // No shell/PATH CLI resolution or NODE_OPTIONS/NODE_PATH is inherited by the
 // admitted child. Credentials and mutation approval remain operator obligations.
 const childEnv={...env,PATH:dirname(plan.node.path)+':/usr/bin:/bin:/usr/sbin:/sbin',WRANGLER_SEND_METRICS:'false',WRANGLER_HIDE_BANNER:'true'};delete childEnv.NODE_OPTIONS;delete childEnv.NODE_PATH;delete childEnv.ESBUILD_BINARY_PATH;
 try{return await new Promise((done,reject)=>{const child=spawn(plan.node.path,plan.command.argv,{cwd:plan.command.cwd,env:childEnv,stdio:'inherit',shell:false});child.once('error',reject);child.once('exit',(code,signal)=>{if(signal)reject(new Error('Tool outcome requires provider readback after signal '+signal));else{process.stdout.write(JSON.stringify({status:'command_exited',exit_code:code??1,provider_outcome:'readback_required_before_retry'})+'\n');done(code??1);}});});}
 catch(error){error.providerCommandStarted=true;throw error;}
}
if(process.argv[1]&&pathToFileURL(resolve(process.argv[1])).href===import.meta.url){
 try{process.exitCode=await main(process.argv.slice(2));}catch(error){process.stderr.write(JSON.stringify({status:error.providerCommandStarted?'unknown_outcome':'denied',reason:error.message,provider_command_started:error.providerCommandStarted===true,provider_outcome:error.providerCommandStarted?'readback_required_before_retry':'not_started'})+'\n');process.exitCode=1;}
}
