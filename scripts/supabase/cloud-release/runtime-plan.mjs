// Read-only production preparation. No secret or function mutation is performed.
// Secret values only live in a private in-memory proposal and are never logged.
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {lstatSync,mkdtempSync,mkdirSync,readFileSync,realpathSync,rmSync,writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname,join,relative,resolve,sep} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {management,PROJECT} from './access.mjs';
import {SOURCE,profile} from './migrations.mjs';
import {readSourceEnvironment} from './source-env.mjs';

const sha=value=>createHash('sha256').update(value).digest('hex');
const SLUGS=Object.freeze(['collect-api','admin-api','collect-jobs']);
const SOURCE_ROOT=resolve(SOURCE,'supabase');
const CLOUD_ORIGIN=`https://${PROJECT}.supabase.co`;
const LOCKED_NPM=new Set(['npm:/nodemailer@10.1.7','npm:/postgres@3.4.7']);
const protectedCloudSecrets=Object.freeze(['DATA_ENCRYPTION_KEY','DATA_KEY_ID','DATA_DECRYPTION_KEYS_JSON',
 'SESSION_ENCRYPTION_KEY','SESSION_KEY_ID','SESSION_DECRYPTION_KEYS_JSON','COLLECT_JOB_TOKEN','AUTH_TOKEN_HASH_SECRET',
 'BURIMUNSI_PIN_PEPPER_BASE64','BURIMUNSI_PIN_PEPPER_ID','BURIMUNSI_CURSOR_KEY_BASE64','BURIMUNSI_DEFAULT_STAFF_PIN',
 'COLLECT_NOTICE_SMTP_PASSWORD']);
const requiredCloudSecrets=Object.freeze(['DATA_ENCRYPTION_KEY','DATA_KEY_ID','SESSION_ENCRYPTION_KEY','SESSION_KEY_ID',
 'COLLECT_JOB_TOKEN','BURIMUNSI_PIN_PEPPER_BASE64','BURIMUNSI_PIN_PEPPER_ID','BURIMUNSI_CURSOR_KEY_BASE64']);

// These values install a direct Supabase Cloud profile. Native automated
// financial work and advanced OCR remain held pending their own data, source,
// policy and scheduler evidence; the planned final enablement is explicit.
export function desiredPublicConfig(sourceSha){
 if(!/^[a-f0-9]{64}$/.test(sourceSha??''))throw Error('invalid_source_sha');
 const p=JSON.parse(profile);
 if(PROJECT!=='rrlduytparvsjfmegalh'||p.supabase_origin!==CLOUD_ORIGIN||p.mode!=='managed'||p.environment!=='production'||
  [p.member_api_origin,p.admin_origin,p.public_origin,p.google_callback_origin].some(x=>x!==CLOUD_ORIGIN))throw Error('unexpected_cloud_profile');
 return Object.freeze({
  COLLECT_DEPLOYMENT_PROFILE:profile,COLLECT_DEPLOYMENT_PROFILE_SHA256:sha(profile),BUILD_SOURCE_ID:sourceSha,
  APP_ENVIRONMENT:'production',ADMIN_ORIGIN:p.admin_origin,ADMIN_ORIGINS:p.admin_origin,ALLOWED_ORIGINS:p.supabase_origin,
  COLLECT_NATIVE_INGRESS_MODE:'supabase_direct_v1',BURIMUNSI_NATIVE_ENABLED:'true',
  BURIMUNSI_SMS_OBSERVATIONS_ENABLED:'true',BURIMUNSI_ADMIN_SMS_OBSERVATIONS_ENABLED:'true',
  BURIMUNSI_OBSERVATION_HINTS_ENABLED:'true',BURIMUNSI_NATIVE_UPLOADS_ENABLED:'true',
  BURIMUNSI_NATIVE_AUTO_RECORDS_ENABLED:'true',BURIMUNSI_STAFF_PIN_PHONE_PRESERVATION_ENABLED:'true',
  COLLECT_ADMIN_DYNAMIC_OWNER_AUTH_ENABLED:'true',COLLECT_ADMIN_OWNER_IDENTITY_ENABLED:'true',
  COLLECT_ADMIN_TOTP_ENABLED:'true',COLLECT_ADMIN_EMAIL_OTP_TTL_SECONDS:'1800',
  AUTH_MEMBER_REGISTRATION_ENABLED:'false',COLLECT_ANONYMOUS_AUTH_ENABLED:'false',COLLECT_GOOGLE_AUTH_ENABLED:'false',
  MOMO_PROCESSING_PAUSED:'true',COLLECT_JOBS_MODE:'maintenance_only',
  BURIMUNSI_NATIVE_WORKERS_ENABLED:'false',BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED:'false',
  BURIMUNSI_SMART_ONBOARDING_ADVANCED_ENABLED:'false'
 });
}

function safeRelative(root,file){
 const canonical=realpathSync(file),base=realpathSync(root),rel=relative(base,canonical);
 if(!rel||rel.startsWith('..'+sep)||rel==='..'||resolve(base,rel)!==canonical||rel.split(sep).some(x=>x==='..'||x==='')||
  lstatSync(file).isSymbolicLink()||!lstatSync(file).isFile())throw Error('unsafe_source_file');
 return rel.split(sep).join('/');
}
function loadGraph(root,slug,run){
 const functionRoot=join(root,'functions');
 const text=run('deno',['info','--json','--frozen-lockfile',`${slug}/index.ts`],{cwd:functionRoot,encoding:'utf8',maxBuffer:16*1024*1024});
 const graph=JSON.parse(text);
 if(!Array.isArray(graph.roots)||graph.roots.length!==1||graph.roots[0]!==pathToFileURL(join(functionRoot,slug,'index.ts')).href||
  !Array.isArray(graph.modules)||graph.errors?.length||graph.modules.some(m=>m.error))throw Error('source_graph_invalid');
 const paths=[],external=[];
 for(const item of graph.modules){
  if(item.specifier.startsWith('file:')){
   const file=fileURLToPath(item.specifier),path=safeRelative(root,file);
   if(path.includes('/tests/')||!(/\.(?:js|mjs|ts|json)$/.test(path)))throw Error('unexpected_source_graph_file');
   paths.push(path);
  }else if(LOCKED_NPM.has(item.specifier))external.push(item.specifier);
  else throw Error('unapproved_external_dependency');
 }
 if(!paths.includes(`functions/${slug}/index.ts`))throw Error('entrypoint_missing');
 return {paths:[...new Set(paths)].sort(),external:[...new Set(external)].sort()};
}

// Encapsulate the exact captured bytes. Callers get only copies or FormData;
// a source file changing later cannot silently change the proposed payload.
class FrozenRuntimeSnapshot {
 #files;#graphs;#manifest;#digest;
 constructor(files,graphs){
  this.#files=new Map([...files].map(([p,b])=>[p,Buffer.from(b)]));
  this.#graphs=Object.fromEntries(SLUGS.map(slug=>[slug,{paths:[...graphs[slug].paths],external:[...graphs[slug].external]}]));
  const manifest={format:'collect.cloud-runtime-source.v1',project:PROJECT,
   files:[...this.#files].sort(([a],[b])=>a.localeCompare(b)).map(([path,b])=>({path,size:b.length,sha256:sha(b)})),
   functions:SLUGS.map(slug=>({slug,entrypoint:`functions/${slug}/index.ts`,files:this.#graphs[slug].paths,external:this.#graphs[slug].external}))};
  this.#manifest=JSON.stringify(manifest);this.#digest=sha(this.#manifest);
 }
 get sourceSha(){return this.#digest;}
 summary(){const m=JSON.parse(this.#manifest);return {sourceSha256:this.#digest,manifest:m,totalBytes:m.files.reduce((n,f)=>n+f.size,0)};}
 copyFile(path){const b=this.#files.get(path);if(!b)throw Error('unknown_snapshot_file');return Buffer.from(b);}
 makeForm(slug){
  if(!SLUGS.includes(slug))throw Error('unknown_function');
  const form=new FormData();form.append('metadata',JSON.stringify({name:slug,entrypoint_path:`functions/${slug}/index.ts`,verify_jwt:false}));
  // Upload the entire immutable union to each function so relative paths and
  // the one source identity match all three entrypoints.
  for(const [path,b] of [...this.#files].sort(([a],[b])=>a.localeCompare(b)))
   form.append('file',new Blob([b],{type:'application/octet-stream'}),path);
  return form;
 }
}

export function captureRuntimeSnapshot({root=SOURCE_ROOT,run=execFileSync}={}){
 root=realpathSync(root);const graphs={};
 for(const slug of SLUGS)graphs[slug]=loadGraph(root,slug,run);
 const names=new Set(['functions/deno.json','functions/deno.lock',...Object.values(graphs).flatMap(g=>g.paths)]),files=new Map();
 for(const path of [...names].sort()){
  const file=join(root,path);if(safeRelative(root,file)!==path)throw Error('source_path_changed');
  files.set(path,readFileSync(file));
 }
 const lock=JSON.parse(files.get('functions/deno.lock').toString('utf8'));
 for(const specifier of [...new Set(Object.values(graphs).flatMap(g=>g.external))]){
  const expected=specifier.replace('npm:/','');
  if(!lock.npm?.[expected]?.integrity)throw Error('unlocked_npm_dependency');
 }
 return new FrozenRuntimeSnapshot(files,graphs);
}

// Type-check the exact in-memory snapshot, using only already-cached modules;
// the temp tree is owned, never mounted into a runtime, and always removed.
export function checkSnapshot(snapshot,{run=execFileSync}={}){
 const dir=mkdtempSync(join(tmpdir(),'collect-cloud-snapshot-'));
 try{
  for(const {path} of snapshot.summary().manifest.files){const target=join(dir,path);mkdirSync(dirname(target),{recursive:true});writeFileSync(target,snapshot.copyFile(path),{flag:'wx',mode:0o600});}
  run('deno',['check','--frozen','--cached-only',...SLUGS.map(x=>`${x}/index.ts`)],{cwd:join(dir,'functions'),encoding:'utf8',stdio:'pipe',maxBuffer:8*1024*1024});
  return {status:'passed',mode:'cached-only',sourceSha256:snapshot.sourceSha};
 }finally{rmSync(dir,{recursive:true,force:true});}
}


// JSON/stringification never reveal values. Call mutationBody() explicitly in
// the integrating process only after the parent has qualified the cutover.
export class SecretProposal {
 #changes;#view;
 constructor(changes,view){this.#changes=changes.map(x=>Object.freeze({...x}));this.#view=structuredClone(view);}
 publicView(){return structuredClone(this.#view);}
 mutationBody(){return this.#changes.map(x=>({...x}));}
 toJSON(){return this.publicView();}
}
export function prepareSecretProposal({cloudRows,localEnv,sourceSha}){
 if(!Array.isArray(cloudRows)||!localEnv||typeof localEnv!=='object')throw Error('configuration_inventory_invalid');
 const remote=new Map();
 for(const row of cloudRows){if(!row||typeof row.name!=='string'||! /^[A-Z][A-Z0-9_]*$/.test(row.name)||typeof row.value!=='string'||! /^[a-f0-9]{64}$/.test(row.value)||remote.has(row.name))throw Error('cloud_secret_metadata_invalid');remote.set(row.name,row.value);}
 const config=desiredPublicConfig(sourceSha),changes=[],settings=[];
 for(const [name,value] of Object.entries(config)){
  const status=!remote.has(name)?'missing':remote.get(name)===sha(value)?'matches':'different';
  settings.push({name,status});if(status!=='matches')changes.push({name,value});
 }
 const protectedStatus=protectedCloudSecrets.map(name=>({name,cloud:remote.has(name)?'present':'missing',
  local:typeof localEnv[name]==='string'&&localEnv[name]!==''?'present':'absent',
  same:remote.has(name)&&typeof localEnv[name]==='string'&&localEnv[name]!==''?remote.get(name)===sha(localEnv[name]):null}));
 const missingRequired=requiredCloudSecrets.filter(name=>!remote.has(name));
 const ai=typeof localEnv.OPENAI_API_KEY==='string'&&localEnv.OPENAI_API_KEY.trim()===localEnv.OPENAI_API_KEY&&localEnv.OPENAI_API_KEY.length>=20;
 if(!remote.has('OPENAI_API_KEY')&&ai)changes.push({name:'OPENAI_API_KEY',value:localEnv.OPENAI_API_KEY});
 const aiState=remote.has('OPENAI_API_KEY')?'cloud_present':ai?'proposed_from_source':'missing';
 const model=typeof localEnv.MOMO_AI_MODEL==='string'&&/^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$/.test(localEnv.MOMO_AI_MODEL)?localEnv.MOMO_AI_MODEL:null;
 return new SecretProposal(changes,{project:PROJECT,sourceSha256:sourceSha,settings,protectedSecrets:protectedStatus,
  requiredCloudSecretsMissing:missingRequired,openAiKey:aiState,changeNames:changes.map(x=>x.name).sort(),
  nativeAutomationTransition:{proposedConfig:model?{MOMO_AI_ENABLED:'true',MOMO_AI_MODEL:model,BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED:'true'}:null,
   readyToApply:false,requires:['imported-history guard and fresh-recapture dedup evidence','approved model/provider and valid key','qualified scheduler dispatch and observed operation']},
  rosterOcrTransition:{readyToApply:false,requires:['new source-bound and collection-specific approval','native JPEG decoder identity and build qualification','approved provider/model and explicit consent']},
  holds:['automatic SMS processing requires imported-history protection, provider/model and scheduler qualification',
   'advanced roster OCR requires new source-bound policy approval',
   'native work grants and scheduler activation require independent qualification',
   'validate Cloud database target, bucket, scheduler token, and mail transport without exposing credentials']});
}

export async function inspectRuntimePlan({snapshot,cloudRows,localEnv}={}){
 snapshot??=captureRuntimeSnapshot();
 cloudRows??=(await management('secrets')).json();
 localEnv??=readSourceEnvironment();
 return {snapshot,proposal:prepareSecretProposal({cloudRows,localEnv,sourceSha:snapshot.sourceSha}),check:checkSnapshot(snapshot)};
}

if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 const result=await inspectRuntimePlan();
 // Print status and names only; never proposal.mutationBody() or env values.
 console.log(JSON.stringify({snapshot:result.snapshot.summary(),typecheck:result.check,configuration:result.proposal.publicView()}));
}
