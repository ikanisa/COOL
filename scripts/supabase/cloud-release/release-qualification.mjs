// Local, socket-only/cached-only release evidence. No remote mutations.
import {spawnSync} from 'node:child_process';
import {readFileSync,lstatSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {ROOT,record} from './access.mjs';
import {SOURCE} from './migrations.mjs';
import {captureRuntimeSnapshot,checkSnapshot} from './runtime-plan.mjs';

const sha=x=>createHash('sha256').update(x).digest('hex');
export const QUALIFICATION_FILES=Object.freeze([
 'scripts/supabase/cloud-release/runtime-plan.mjs','scripts/supabase/cloud-release/runtime-plan.test.mjs',
 'scripts/supabase/cloud-release/imported-history-guard.sql','scripts/supabase/cloud-release/imported-history-guard.test.mjs',
 'scripts/supabase/cloud-release/imported-history-read.sql','scripts/supabase/cloud-release/imported-history-read.test.mjs',
 'scripts/supabase/cloud-release/initial-account-bootstrap.sql','scripts/supabase/cloud-release/initial-account-bootstrap.mjs',
 'scripts/supabase/cloud-release/initial-account-bootstrap.test.mjs','scripts/supabase/cloud-release/source-env.mjs',
 'scripts/supabase/cloud-release/release-runtime.mjs','scripts/supabase/cloud-release/release-runtime.test.mjs','scripts/supabase/cloud-release/release-qualification.mjs',
 'scripts/supabase/cloud-data-transfer/maintenance.mjs','scripts/supabase/cloud-data-transfer/compile.mjs',
 'scripts/supabase/cloud-data-transfer/lineage.sql'
]);
const TESTS=Object.freeze([
 {id:'runtime_plan',args:['--test','scripts/supabase/cloud-release/runtime-plan.test.mjs']},
 {id:'history_guard',args:['scripts/supabase/cloud-release/imported-history-guard.test.mjs']},
 {id:'history_read',args:['scripts/supabase/cloud-release/imported-history-read.test.mjs']},
 {id:'account_bootstrap',args:['scripts/supabase/cloud-release/initial-account-bootstrap.test.mjs']},
 {id:'fence_release',args:['--test','scripts/supabase/cloud-release/release-runtime.test.mjs']},
 {id:'native_ingress',args:['--test','supabase/functions/_shared/tests/native-direct-supabase-ingress.test.mjs',
  'supabase/functions/_shared/tests/native-direct-supabase-handler.test.mjs',
  'supabase/functions/_shared/tests/native-direct-supabase-commands.test.mjs']}
]);
export function qualificationFileHashes(){return Object.fromEntries(QUALIFICATION_FILES.map(path=>[path,sha(readFileSync(join(SOURCE,path)))]));}
export function qualificationName(sourceSha,files=qualificationFileHashes()){
 if(!/^[a-f0-9]{64}$/.test(sourceSha??''))throw Error('invalid_source_sha');
 return `runtime-qualification-${sourceSha.slice(0,16)}-${sha(JSON.stringify(files)).slice(0,16)}.json`;
}
export function runLocalQualification({spawn=spawnSync}={}){
 const snapshot=captureRuntimeSnapshot(),typecheck=checkSnapshot(snapshot),before=qualificationFileHashes(),tests=[];
 for(const item of TESTS){
  const result=spawn('node',item.args,{cwd:SOURCE,encoding:'utf8',timeout:180000,maxBuffer:4*1024*1024});
  if(result.error||result.status!==0||result.signal)throw Error('qualification_failed_'+item.id);
  tests.push({id:item.id,status:'passed'});
 }
 if(JSON.stringify(before)!==JSON.stringify(qualificationFileHashes())||captureRuntimeSnapshot().sourceSha!==snapshot.sourceSha)
  throw Error('qualification_inputs_changed');
 return {format:'collect.cloud-release-qualification.v1',sourceSha256:snapshot.sourceSha,files:before,typecheck,tests,
  scopes:['owned socket-only PG17 fixtures','synthetic native handlers','cached-only typecheck'],
  notProofOf:['hosted end-to-end login','provider delivery','actual monetary posting'],at:new Date().toISOString()};
}
export function verifyQualification(evidence,sourceSha){
 if(!evidence||evidence.format!=='collect.cloud-release-qualification.v1'||evidence.sourceSha256!==sourceSha||
  evidence.typecheck?.status!=='passed'||evidence.typecheck?.sourceSha256!==sourceSha||
  !Array.isArray(evidence.tests)||evidence.tests.length!==TESTS.length||
  TESTS.some((t,i)=>evidence.tests[i]?.id!==t.id||evidence.tests[i]?.status!=='passed')||
  JSON.stringify(evidence.files)!==JSON.stringify(qualificationFileHashes()))throw Error('qualification_unverified');
 return true;
}
export function saveQualification(evidence){
 verifyQualification(evidence,evidence.sourceSha256);
 const name=qualificationName(evidence.sourceSha256,evidence.files),path=join(ROOT,name);
 try{const s=lstatSync(path);if(!s.isFile()||s.isSymbolicLink()||s.uid!==process.getuid()||(s.mode&0o077)!==0)throw Error('qualification_file_unsafe');
  const old=JSON.parse(readFileSync(path,'utf8'));verifyQualification(old,evidence.sourceSha256);return path;
 }catch(e){if(e.code!=='ENOENT')throw e;}
 record(name,evidence);return path;
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 const evidence=runLocalQualification(),path=saveQualification(evidence);
 console.log(JSON.stringify({status:'qualified_locally',sourceSha256:evidence.sourceSha256,tests:evidence.tests,path}));
}
