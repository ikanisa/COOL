// Preserve the strict historical fixture inventories in a private temporary
// source copy. The active Cloud tree is never modified and later migrations
// are neither executed nor represented as covered by these historical tests.
import {createHash} from 'node:crypto';
import {spawn} from 'node:child_process';
import {cp,lstat,mkdir,mkdtemp,readFile,realpath,readdir,rm,symlink} from 'node:fs/promises';
import {isAbsolute,join,relative,resolve,sep} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';

const ROOT=resolve(import.meta.dirname,'../../..');
const LOCK='supabase/managed-migration-history/source-migrations.lock.json';
const LOCK_SHA='17d63e907cc992d62be67224319f5596c150bd1f51d5c05aa54dc250ef50aa64';
const EXTRA=Object.freeze({
 '20261113130900_burimunsi_native_sms_posting.sql':'6fa1438824f9d5455903353573c508d697e11aabae9ec41df2d456fb0ab43d71',
 '20261114101000_burimunsi_native_sms_post_retry.sql':'836e5e925a03c5bbb0bb858a31e689912ecf0386f350b0fbe8d4c0209f6d329a',
 '20261114102000_burimunsi_native_event_identity.sql':'d05349ffd4a3cc93d8e641869dd2feecb4890de80d4944f95addd3d3fed535d0',
 '20261114110000_burimunsi_native_retention_positive_links.sql':'91dcc2eba2f302b85a18517a16ba2aed8aac863c3575eef2358eb29d826218e1',
 '20261114110100_collect_admin_mfa_authority.sql':'460721da7d7ea30c9255c684da477d05adea9f469b2d988a476338608c2d963d',
 '20261114110200_storage_iceberg_retention_census.sql':'643064893448da9b70e52be4d87fedc7125757f3c050c27fbc5b683689beb8b8',
 '20261114110300_collect_admin_mfa_intent_recovery.sql':'ba10d574db42eae6c981c4fb037a6d93929f6f27f4dd0b574fb5af008f33259a',
});
const ROOTS=['scripts/supabase','scripts/self_hosted','supabase','deploy/collect-sms','deploy/self-hosted',
 'lib/shared/models','lib/core/data/exact_json_values.dart','lib/shared/repositories/collect_repository_live_reader.dart',
 'test/self_hosted_member_history_sql_receipts_test.dart','.github/workflows/supabase.yml','.fvmrc','pubspec.yaml','pubspec.lock'];
const DEPS=['scripts/supabase/node_modules','deploy/collect-sms/node_modules','supabase/functions/node_modules'];
const skip=new Set(['node_modules','.git','.temp','.dart_tool','.gradle','build','coverage','outputs','reports','__pycache__','.DS_Store']);
const hash=x=>createHash('sha256').update(x).digest('hex');
const need=(x,code)=>{if(!x)throw Error(code);};
const safePath=p=>typeof p==='string'&&isAbsolute(p)&&resolve(p)===p&&!/[\x00-\x1f\x7f]/.test(p);

export async function withPinnedHistory(count,callback){
 need([58,65].includes(count)&&typeof callback==='function','historical_fixture_mode_invalid');
 need(await realpath(ROOT)===ROOT,'historical_source_not_physical');
 const raw=await readFile(join(ROOT,LOCK)),lock=JSON.parse(raw.toString('utf8'));
 need(hash(raw)===LOCK_SHA&&lock.format==='collect.selfhost.migrations.v1'&&lock.original_count===16&&lock.migrations.length===58,'historical_lock_changed');
 need(hash(await readFile(join(ROOT,'deploy/self-hosted/migrations.lock.json')))===LOCK_SHA,'historical_source_lock_changed');
 const wanted=new Map(lock.migrations.map(row=>[row.name,row.sha256]));
 if(count===65)for(const [name,digest] of Object.entries(EXTRA))wanted.set(name,digest);
 need(wanted.size===count&&[...wanted].every(([name,digest])=>/^\d{14}_[a-z0-9_]+\.sql$/.test(name)&&/^[a-f0-9]{64}$/.test(digest)),'historical_migration_list_invalid');
 const base=process.platform==='darwin'?'/private/tmp':'/tmp';need(await realpath(base)===base,'historical_temp_not_physical');
 const stage=await mkdtemp(join(base,'collect-pinned-history-'));
 try{
  for(const role of ROOTS){const from=join(ROOT,role),to=join(stage,role);await mkdir(resolve(to,'..'),{recursive:true,mode:0o700});
   await cp(from,to,{recursive:true,force:false,errorOnExist:true,filter:async source=>{
    const rel=relative(ROOT,source);if(rel==='supabase/migrations'||rel.startsWith('supabase/migrations'+sep))return false;
    if(rel.split(sep).some(part=>skip.has(part)||part.startsWith('._')))return false;
    const s=await lstat(source);need(!s.isSymbolicLink(),'historical_source_symlink_refused');return true;
   }});
  }
  const migrations=join(stage,'supabase/migrations');await mkdir(migrations,{recursive:true,mode:0o700});
  for(const [name,digest] of wanted){const source=join(ROOT,'supabase/migrations',name),s=await lstat(source);
   need(s.isFile()&&!s.isSymbolicLink()&&await realpath(source)===source,'historical_migration_not_physical');
   const bytes=await readFile(source);need(hash(bytes)===digest,'historical_migration_changed');
   await cp(source,join(migrations,name),{force:false,errorOnExist:true});}
  need((await readdir(migrations)).length===count,'historical_inventory_changed');
  for(const dep of DEPS){const source=join(ROOT,dep);let s;try{s=await lstat(source);}catch(e){if(e.code==='ENOENT')continue;throw e;}
   need(s.isDirectory()&&!s.isSymbolicLink(),'historical_dependency_not_physical');await mkdir(resolve(join(stage,dep),'..'),{recursive:true});await symlink(source,join(stage,dep),'dir');}
  const value=await callback(stage);return value;
 }finally{await rm(stage,{recursive:true,force:true});}
}

async function child(stage,args){
 const temp=process.platform==='darwin'?'/private/tmp':'/tmp';
 const p=spawn(process.execPath,args,{cwd:stage,env:{...process.env,TMPDIR:temp},stdio:'inherit',shell:false});
 const forward=signal=>{if(p.exitCode===null&&p.signalCode===null)p.kill(signal);};
 const term=()=>forward('SIGTERM'),interrupt=()=>forward('SIGINT');process.on('SIGTERM',term);process.on('SIGINT',interrupt);
 try{return await new Promise((done,reject)=>{p.once('error',reject);p.once('close',(code,signal)=>done({code,signal}));});}
 finally{process.removeListener('SIGTERM',term);process.removeListener('SIGINT',interrupt);}
}
async function main(args){
 const mode=args[0];let count,command;
 if(mode==='--native'&&args.length===1){count=58;command=['scripts/supabase/testing/current-self-hosted-native.mjs'];}
 else if(mode==='--source58'&&args.length===1){count=58;command=['--test','--test-concurrency=1',
  'scripts/supabase/testing/current-self-hosted-native.test.mjs','scripts/supabase/testing/self-hosted-member-history.test.mjs',
  'scripts/supabase/testing/admit-self-hosted-history.test.mjs'];}
 else if(mode==='--history-admit'&&args.length===3&&safePath(args[1])&&safePath(args[2])){count=58;command=['scripts/supabase/testing/admit-self-hosted-history.mjs',args[1],args[2]];}
 else if(mode==='--retention65'&&args.length===1){count=65;command=['--test','--test-concurrency=1','scripts/supabase/retention-convergence/ordered-chain-fixture.test.mjs','scripts/supabase/retention-convergence/deferred-mfa/ordered-deferred-fixture.test.mjs'];}
 else if(mode==='--verify58'&&args.length===1){count=58;command=null;}
 else if(mode==='--verify65'&&args.length===1){count=65;command=null;}
 else throw Error('historical_fixture_mode_invalid');
 const status=await withPinnedHistory(count,async stage=>{
  if(!command){
   if(count===58){const module=await import(pathToFileURL(join(stage,'scripts/supabase/testing/self-hosted-current-schema.mjs')).href);
    need((await module.reviewedCurrentMigrations(stage)).length===58,'historical_fixture_verification_failed');}
   else{const module=await import(pathToFileURL(join(stage,'scripts/supabase/retention-convergence/deferred-mfa/ordered-deferred-fixture.mjs')).href);
    need((await module.pinnedBranchInputs()).migrations.length===65,'historical_fixture_verification_failed');}
   return {code:0,signal:null};
  }
  return child(stage,command);
 });
 if(status.code!==0)throw Error('historical_fixture_failed');
 if(!command)console.log(JSON.stringify({status:'historical_fixture_verified',migrationCount:count,activeCloudTreeChanged:false,productionAcceptance:false}));
}
if(process.argv[1]&&fileURLToPath(import.meta.url)===resolve(process.argv[1])){
 try{await main(process.argv.slice(2));}catch(e){console.error(JSON.stringify({status:'historical_fixture_refused',code:/^[a-z_]+$/.test(e.message??'')?e.message:'historical_fixture_failed'}));process.exitCode=1;}
}
