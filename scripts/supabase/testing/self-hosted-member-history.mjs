// Source-bound receipts for the current self-hosted additive history profile.
// Historical current14/current16 receipts have separate formats and runners.
import {createHash} from 'node:crypto';
import {readFile,readdir,realpath,mkdir,open,lstat} from 'node:fs/promises';
import {resolve,dirname,join,isAbsolute} from 'node:path';
import {fileURLToPath} from 'node:url';
import {EXACT_CURRENT16} from './curated-platform-fixture.mjs';
import {CURRENT_ADDITIONS,CURRENT_MIGRATION_COUNT,reviewedCurrentMigrations} from './self-hosted-current-schema.mjs';

export const HISTORY_PACKET_FORMAT='collect.selfhost.actual-member-history-sql.v3';
export const HISTORY_INPUTS_FORMAT='collect.selfhost.history.inputs.v3';
export const HISTORY_PROFILE='reviewed_current_chain_member_history_v3';
export const HISTORY_ADDITIONS=CURRENT_ADDITIONS;
const ROOT=resolve(dirname(fileURLToPath(import.meta.url)),'../../..');
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const need=(ok,code)=>{if(!ok)throw new Error(code);};

export async function snapshotSelfHostedHistorySources(root=ROOT){
 need(isAbsolute(root)&&await realpath(root)===root,'PHYSICAL_HISTORY_SOURCE_REQUIRED');
 await reviewedCurrentMigrations(root);
 const roles=[];
 async function visit(directory,pattern){
  for(const item of await readdir(join(root,directory),{withFileTypes:true})){
   if(item.name==='tests')continue;
   const role=directory+'/'+item.name;
   need(!item.isSymbolicLink(),'LINKED_HISTORY_SOURCE_REFUSED');
   if(item.isDirectory())await visit(role,pattern);
   else if(item.isFile()&&pattern.test(item.name))roles.push(role);
  }
 }
 await visit('supabase/functions/_shared',/\.(?:js|mjs)$/);
 await visit('lib/shared/models',/\.dart$/);
 roles.push(...[...EXACT_CURRENT16,...HISTORY_ADDITIONS].map(name=>'supabase/migrations/'+name),
  'scripts/supabase/testing/self-hosted-backend-runtime.ts',
  'scripts/supabase/testing/self-hosted-member-history.mjs',
  'scripts/supabase/testing/self-hosted-member-history.test.mjs',
  'scripts/supabase/testing/self-hosted-fixture.mjs',
  'scripts/supabase/testing/self-hosted-current-schema.mjs',
  'scripts/supabase/testing/reviewed-self-hosted-migrations.mjs',
  'deploy/self-hosted/migrations.lock.json',
  'scripts/supabase/testing/curated-platform-fixture.mjs',
  'scripts/supabase/testing/member-realtime-fixture-plan.json',
  'scripts/supabase/testing/member-realtime-interface.sql',
  'supabase/tests/sql/00_local_auth_fixture.sql',
  'supabase/functions/deno.json','supabase/functions/deno.lock',
  'lib/core/data/exact_json_values.dart',
  'lib/shared/repositories/collect_repository_live_reader.dart',
  'test/self_hosted_member_history_sql_receipts_test.dart',
  '.fvmrc','pubspec.yaml','pubspec.lock');
 const files=[];
 for(const role of [...new Set(roles)].sort()){
  const path=join(root,role);
  need(await realpath(path)===path,'LINKED_HISTORY_SOURCE_REFUSED');
  const bytes=await readFile(path);
  files.push({role,bytes:bytes.length,sha256:sha(bytes)});
 }
 return {format:HISTORY_INPUTS_FORMAT,profile:HISTORY_PROFILE,files,
  source_sha256:sha(JSON.stringify(files)),
  scope:'Exact local SQL/domain and Dart consumer source; synthetic native PostgreSQL, not managed Auth or production acceptance.'};
}

export async function verifySelfHostedHistorySources(inputs,root=ROOT){
 const actual=await snapshotSelfHostedHistorySources(root);
 need(JSON.stringify(actual)===JSON.stringify(inputs),'SELFHOST_HISTORY_SOURCE_CHANGED');
 return actual;
}

async function writeExclusive(path,value){
 const file=await open(path,'wx',0o600);
 try{await file.writeFile(JSON.stringify(value,null,2)+'\n');await file.sync();}
 finally{await file.close();}
}

export async function startSelfHostedHistoryCapture(output,root=ROOT){
 need(typeof output==='string'&&isAbsolute(output)&&resolve(output)===output&&
  await realpath(dirname(output))===dirname(output),'PHYSICAL_HISTORY_OUTPUT_PARENT_REQUIRED');
 try{await lstat(output);need(false,'FRESH_HISTORY_OUTPUT_REQUIRED');}
 catch(error){if(error.code!=='ENOENT')throw error;}
 const inputs=await snapshotSelfHostedHistorySources(root);
 await mkdir(output,{mode:0o700});
 await writeExclusive(join(output,'INPUTS.json'),inputs);
 return {output,root,inputs,inputsSha:sha(await readFile(join(output,'INPUTS.json')))};
}

export function validateSelfHostedHistoryPacket(packet){
 need(packet?.format===HISTORY_PACKET_FORMAT&&packet.profile===HISTORY_PROFILE,
  'CURRENT_SELFHOST_HISTORY_PROFILE_REQUIRED');
 need(packet.fixture?.baseline==='current16'&&packet.fixture?.synthetic_only===true&&
  packet.fixture?.normal_runtime_role==='collect_runtime'&&packet.fixture?.financial_rows_directly_seeded===true&&
  packet.fixture?.financial_posting_acceptance===false&&packet.fixture?.historical_packet===false,
  'EXACT_SELFHOST_HISTORY_FIXTURE_SCOPE_REQUIRED');
 need(Array.isArray(packet.fixture.additive_migrations)&&
  packet.fixture.additive_migrations.map(item=>item.name).join(',')===HISTORY_ADDITIONS.join(',')&&
  packet.fixture.additive_migrations.every(item=>/^[a-f0-9]{64}$/.test(item.sha256)),
  'EXACT_SELFHOST_ADDITIVE_MIGRATIONS_REQUIRED');
 need(packet.fixture.migration_count===CURRENT_MIGRATION_COUNT&&packet.fixture.complete_reviewed_chain===true&&
  packet.fixture.deployment_binding_acceptance===false,'EXACT_CURRENT_SCHEMA_SCOPE_REQUIRED');
 need(packet.provider_calls===0&&packet.hosted_acceptance===false&&packet.production_acceptance===false&&
  packet.managed_auth_acceptance===false&&packet.actual_runtime_transactions_commit===true,
  'NO_EXTERNAL_HISTORY_ACCEPTANCE_REQUIRED');
 need(/^[a-f0-9]{64}$/.test(packet.source_inputs_sha256)&&/^[a-f0-9]{64}$/.test(packet.source_sha256)&&
  Array.isArray(packet.requests)&&packet.requests.length>0&&Array.isArray(packet.pages)&&packet.pages.length>0&&
  Number.isSafeInteger(packet.SQL_statement_count)&&packet.SQL_statement_count>0,
  'ACTUAL_SELFHOST_HISTORY_RECEIPTS_REQUIRED');
 need(packet.pages.every(page=>page?.contract_version===2&&page.response?.contract_version===2&&
  Number.isSafeInteger(page.request_id)&&page.request_id>=0&&page.request_id<packet.requests.length&&
  JSON.stringify(page.response)===JSON.stringify(packet.requests[page.request_id].response?.body)),
  'ACTUAL_SELFHOST_HISTORY_REQUEST_BINDING_REQUIRED');
 return packet;
}

export async function finishSelfHostedHistoryCapture(capture,{fixture,pages,balances,requests,statements,runtimeIdentities,cases}){
 await verifySelfHostedHistorySources(capture.inputs,capture.root);
 const packet=validateSelfHostedHistoryPacket({format:HISTORY_PACKET_FORMAT,profile:HISTORY_PROFILE,
  source_inputs_sha256:capture.inputsSha,source_sha256:capture.inputs.source_sha256,
  fixture:{...fixture,baseline:'current16',historical_packet:false,synthetic_only:true,
   migration_count:CURRENT_MIGRATION_COUNT,complete_reviewed_chain:true,deployment_binding_acceptance:false,
   normal_runtime_role:'collect_runtime',financial_rows_directly_seeded:true,financial_posting_acceptance:false},
  pages,balances,requests,SQL_statement_count:statements.length,runtime_identities:runtimeIdentities,cases,
  actual_runtime_transactions_commit:true,provider_calls:0,hosted_acceptance:false,
  managed_auth_acceptance:false,production_acceptance:false});
 await writeExclusive(join(capture.output,'ACTUAL-SQL-STATEMENTS.json'),statements);
 await writeExclusive(join(capture.output,'ACTUAL-HISTORY-PACKET.json'),packet);
 const hashes={packet:sha(await readFile(join(capture.output,'ACTUAL-HISTORY-PACKET.json'))),
  sql:sha(await readFile(join(capture.output,'ACTUAL-SQL-STATEMENTS.json')))};
 await writeExclusive(join(capture.output,'DEFINES.json'),{
  SELFHOST_HISTORY_PACKET:'ACTUAL-HISTORY-PACKET.json',SELFHOST_HISTORY_PACKET_SHA256:hashes.packet,
  SELFHOST_HISTORY_INPUTS:'INPUTS.json',SELFHOST_HISTORY_INPUTS_SHA256:capture.inputsSha,
  SELFHOST_HISTORY_SQL:'ACTUAL-SQL-STATEMENTS.json',SELFHOST_HISTORY_SQL_SHA256:hashes.sql,
  SELFHOST_HISTORY_SOURCE_SHA256:capture.inputs.source_sha256});
 await verifySelfHostedHistorySources(capture.inputs,capture.root);
 const result={format:'collect.selfhost.history.capture.v3',status:'PASS',profile:HISTORY_PROFILE,
  source_sha256:capture.inputs.source_sha256,packet_sha256:hashes.packet,inputs_sha256:capture.inputsSha,
  sql_sha256:hashes.sql,requests:requests.length,pages:pages.length,sql_statements:statements.length,
  historical_current14_or_current16_acceptance:false,provider_calls:0,hosted_acceptance:false,production_acceptance:false};
 await writeExclusive(join(capture.output,'RESULT.json'),result);
 return result;
}
