#!/usr/bin/env node
// Pure local preparation and readback; this module has no provider transport.
import {createHash} from 'node:crypto';
import {lstat,readFile,mkdir,writeFile,realpath} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {RUNTIME_CONFIG_CAPTURE_SQL,SCHEMA_CAPTURE_SQL,parsePublicConfigurationJson} from './public_configuration_apply.mjs';
export {RUNTIME_CONFIG_CAPTURE_SQL,SCHEMA_CAPTURE_SQL};
export const POLICY_CONFIGURATION_KEYS=Object.freeze(['policy:privacy','policy:terms']);
const FORMAT='collect.existing-policy-configuration.plan.v1',MAX_VALUE=256*1024,MAX_SNAPSHOT=512*1024,MAX_TOTAL=1536*1024;
const HASH=/^[a-f0-9]{64}$/,UUID=/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const LEGAL_PATHS=Object.freeze({'policy:privacy':'content/legal/collect_privacy_policy.yaml','policy:terms':'content/legal/collect_terms_of_use.yaml'});
const SOURCE_PATHS=[...Object.values(LEGAL_PATHS),'content/legal/collect_legal_pages_bundle.yaml','scripts/cloudflare/prepare_public_configuration.rb','scripts/cloudflare/prepare_policy_configuration.rb'].sort();
const TARGETS=Object.freeze([
 {account_id:'2209b915a85b1c11cee79b7806c6e73b',database_name:'collect-platform',database_id:'a6a0d284-c445-4fe3-8e64-af5fd42491ae',worker_name:'collect-platform-api',api_origin:'https://api.collect.ikanisa.com'},
 {account_id:'2209b915a85b1c11cee79b7806c6e73b',database_name:'collect-api16-security-stage-20261016',database_id:'59cbe938-2b6b-4505-bf55-5d7d11f2a5ce',worker_name:'collect-api16-security-stage-20261016',api_origin:'https://api16-security-stage.collect.ikanisa.com'},
]);
const sha=value=>createHash('sha256').update(value).digest('hex');
const plain=value=>value!==null&&typeof value==='object'&&!Array.isArray(value)&&[Object.prototype,null].includes(Object.getPrototypeOf(value));
const binary=(a,b)=>Buffer.compare(Buffer.from(a),Buffer.from(b));
const stable=value=>JSON.stringify(value,(_,entry)=>plain(entry)?Object.fromEntries(Object.keys(entry).sort(binary).map(key=>[key,entry[key]])):entry);
function fail(code){const e=new Error('Existing policy configuration refused: '+code);e.code=code;throw e;}
function need(value,code){if(!value)fail(code);}
function exact(value,keys,code){need(plain(value)&&Object.keys(value).length===keys.length&&keys.every(k=>Object.hasOwn(value,k)),code);}
function text(value,max,code,{multiline=false,empty=false}={}){
 need(typeof value==='string'&&(empty||value.length>0)&&Buffer.byteLength(value)<=max&&Buffer.from(value).toString()===value,code);
 need(!(multiline?/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/:/[\u0000-\u001f\u007f]/).test(value),code);return value;
}
function json(raw,max,code){text(raw,max,code,{multiline:true});return parsePublicConfigurationJson(raw,{maxBytes:max});}
function timestamp(value){text(value,24,'timestamp');need(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value)&&Number.isFinite(Date.parse(value))&&new Date(value).toISOString()===value,'timestamp');return value;}
function policy(key,raw){
 const value=json(raw,MAX_VALUE,'policy_json');
 need(plain(value)&&value.kind===key.slice(7)&&value.locale==='en','policy_identity');
 for(const k of ['title','version'])text(value[k],1024,'policy_metadata');
 need(value.content_status==='draft_for_legal_review'&&value.legal_release_approved===false&&HASH.test(value.source_document_sha256),'policy_approval');
 if(Object.hasOwn(value,'provider_approved'))need(value.provider_approved===false,'policy_approval');
 let url;try{url=new URL(value.source_url);}catch{fail('policy_source_url');}
 need(url.origin==='https://collect.ikanisa.com'&&!url.username&&!url.password&&url.pathname==='/'+key.slice(7)&&!url.search&&!url.hash,'policy_source_url');
 need(Array.isArray(value.sections)&&value.sections.length>0&&value.sections.length<=256,'policy_sections');
 for(const section of value.sections){exact(section,['title','body'],'policy_section');text(section.title,MAX_VALUE,'policy_section');text(section.body,MAX_VALUE,'policy_section',{multiline:true});}
 return value;
}
function payloadInput(p){
 exact(p,['schema_version','kind','api_source_id','legal_release_approved','provider_approved','retention_policy_activation','source_inputs','records'],'payload_shape');
 need(p.schema_version===1&&p.kind==='collect_existing_policy_configuration'&&HASH.test(p.api_source_id),'payload_identity');
 need(p.legal_release_approved===false&&p.provider_approved===false&&p.retention_policy_activation===false,'payload_approval');
 need(plain(p.source_inputs)&&stable(Object.keys(p.source_inputs).sort())===stable(SOURCE_PATHS),'source_inputs');
 for(const row of Object.values(p.source_inputs)){exact(row,['sha256','bytes'],'source_role');need(HASH.test(row.sha256)&&Number.isSafeInteger(row.bytes)&&row.bytes>0&&row.bytes<=1024*1024,'source_role');}
 need(Array.isArray(p.records)&&p.records.length===2,'record_count');const records=new Map();
 for(const row of p.records){exact(row,['key','value_json'],'record_shape');need(POLICY_CONFIGURATION_KEYS.includes(row.key)&&!records.has(row.key),'record_key');const value=policy(row.key,row.value_json);need(value.source_document_sha256===p.source_inputs[LEGAL_PATHS[row.key]].sha256,'policy_source_mismatch');records.set(row.key,row.value_json);}
 return {...p,source_inputs:Object.fromEntries(Object.entries(p.source_inputs).sort(([a],[b])=>binary(a,b))),records:POLICY_CONFIGURATION_KEYS.map(key=>({key,value_json:records.get(key)}))};
}
function targetInput(t){
 exact(t,['account_id','database_name','database_id','worker_name','worker_version_id','deployment_id','api_origin','api_source_id'],'target_shape');
 need(TARGETS.some(known=>Object.keys(known).every(k=>t[k]===known[k]))&&UUID.test(t.worker_version_id)&&UUID.test(t.deployment_id)&&HASH.test(t.api_source_id),'target_identity');return {...t};
}
function rowsInput(input){
 need(Array.isArray(input)&&input.length<=10000,'preimage_rows');let previous=null;const rows=[];
 for(const row of input){
  exact(row,['key','value_json','revision','updated_by','updated_at'],'row_shape');text(row.key,256,'row_key');json(row.value_json,MAX_VALUE,'row_json');
  need(typeof row.revision==='string'&&/^(?:0|-?[1-9][0-9]*)$/.test(row.revision),'row_revision');const n=BigInt(row.revision);need(n>=-9223372036854775808n&&n<=9223372036854775807n,'row_revision');
  need(row.updated_by===null||typeof row.updated_by==='string'&&UUID.test(row.updated_by),'row_actor');text(row.updated_at,128,'row_timestamp');need(previous===null||binary(previous,row.key)<0,'row_order_or_duplicate');previous=row.key;
  rows.push({key:row.key,value_json:row.value_json,revision:row.revision,updated_by:row.updated_by,updated_at:row.updated_at});
 }
 need(Buffer.byteLength(JSON.stringify(rows))<=MAX_SNAPSHOT,'preimage_size');return rows;
}
function schemaInput(input){
 exact(input,['rows','sha256'],'schema_shape');need(HASH.test(input.sha256)&&Array.isArray(input.rows)&&input.rows.length>0&&input.rows.length<=4096,'schema_identity');let previous=null;const rows=[];
 for(const row of input.rows){
  exact(row,['type','name','tbl_name','sql'],'schema_row');need(['table','index','trigger','view'].includes(row.type),'schema_type');text(row.name,256,'schema_name');text(row.tbl_name,256,'schema_table');text(row.sql,MAX_VALUE,'schema_sql',{multiline:true});
  need(!row.name.startsWith('_cf_')&&!row.name.startsWith('sqlite_'),'schema_internal');const order=row.type+'\0'+row.name;need(previous===null||binary(previous,order)<0,'schema_order_or_duplicate');previous=order;rows.push({type:row.type,name:row.name,tbl_name:row.tbl_name,sql:row.sql});
 }
 need(rows.some(row=>row.type==='table'&&row.name==='runtime_config'&&row.tbl_name==='runtime_config'),'schema_runtime_config');need(Buffer.byteLength(JSON.stringify(rows))<=MAX_SNAPSHOT&&sha(JSON.stringify(rows))===input.sha256,'schema_hash');return {rows,sha256:input.sha256};
}
const currentState=`SELECT json_group_array(json_object('key',key,'value_json',value_json,'revision',CAST(revision AS TEXT),'updated_by',updated_by,'updated_at',updated_at)) FROM (${RUNTIME_CONFIG_CAPTURE_SQL})`;
const currentSchema=`SELECT json_group_array(json_object('type',type,'name',name,'tbl_name',tbl_name,'sql',sql)) FROM (${SCHEMA_CAPTURE_SQL})`;
const predicate=`((${currentState}) COLLATE BINARY)=?2 AND ((${currentSchema}) COLLATE BINARY)=?1`;
function batch(schema,before,selected,after){
 const shared=[JSON.stringify(schema.rows),JSON.stringify(before)];
 const guard={sql:`SELECT CASE WHEN ${predicate} THEN 1 ELSE json('collect_policy_configuration_guard_failed') END AS policy_guard`,params:shared,expected_guard:1};
 const seed=selected.map((_,i)=>`(?${i*5+3},?${i*5+4},?${i*5+5},?${i*5+6},?${i*5+7})`).join(',');
 const sql=`WITH seed(key,value_json,revision,updated_by,updated_at) AS (VALUES ${seed}),
guard AS MATERIALIZED (SELECT CASE WHEN ${predicate} THEN 1 ELSE json('collect_policy_configuration_guard_failed') END AS passed)
UPDATE runtime_config SET value_json=seed.value_json,revision=CAST(seed.revision AS INTEGER),updated_by=seed.updated_by,updated_at=seed.updated_at
FROM seed CROSS JOIN guard WHERE runtime_config.key=seed.key AND guard.passed=1 RETURNING key;`;
 const params=[...shared,...selected.flatMap(key=>{const row=after.find(row=>row.key===key);return [key,row.value_json,row.revision,row.updated_by,row.updated_at];})];
 need(Buffer.byteLength(sql)<100000&&params.length<=12&&params.reduce((n,v)=>n+(v===null?0:Buffer.byteLength(v)),0)<=MAX_TOTAL,'query_limit');
 const queries=[guard,{sql,params,expected_changes:selected.length,expected_keys:selected}];
 return {atomic_batch_required:true,queries,sha256:sha(stable(queries)),expected_changes:selected.length,automatic_execute:false};
}
export function createPolicyConfigurationUpdatePlan(input){
 exact(input,['payload','target','schema','preimage','selected_keys','updated_at','rollback_updated_at'],'plan_input');exact(input.preimage,['rows'],'preimage_shape');
 const payload=payloadInput(input.payload),target=targetInput(input.target),schema=schemaInput(input.schema),rows=rowsInput(input.preimage.rows);
 need(payload.api_source_id===target.api_source_id,'source_mismatch');
 need(Array.isArray(input.selected_keys)&&input.selected_keys.length>=1&&input.selected_keys.length<=2&&input.selected_keys.every((key,i)=>POLICY_CONFIGURATION_KEYS.includes(key)&&(i===0||binary(input.selected_keys[i-1],key)<0)),'selected_policy_keys');
 const updated_at=timestamp(input.updated_at),rollback_updated_at=timestamp(input.rollback_updated_at);need(updated_at<rollback_updated_at,'rollback_timestamp');
 const byKey=new Map(rows.map(row=>[row.key,row]));need(POLICY_CONFIGURATION_KEYS.every(key=>byKey.has(key)),'existing_policy_required');
 const desired=new Map(payload.records.map(row=>[row.key,row.value_json]));
 for(const key of input.selected_keys){
  const previous=byKey.get(key),oldPolicy=policy(key,previous.value_json),nextPolicy=policy(key,desired.get(key));
  need(['kind','locale','version','content_status','legal_release_approved'].every(k=>oldPolicy[k]===nextPolicy[k]),'legal_metadata_changed');
  need(previous.value_json!==desired.get(key),'selected_policy_unchanged');
  need(BigInt(previous.revision)>=1n&&BigInt(previous.revision)<=9223372036854775805n,'selected_revision_range');
 }
 const selected=[...input.selected_keys];
 const expectedRows=rows.map(row=>selected.includes(row.key)?{...row,value_json:desired.get(row.key),revision:String(BigInt(row.revision)+1n),updated_by:null,updated_at}:row);
 // A compensating restore retains the old body but advances the technical CAS
 // revision again. It does not recreate the original revision (no ABA replay).
 const rollbackRows=rows.map(row=>selected.includes(row.key)?{...row,revision:String(BigInt(row.revision)+2n),updated_by:null,updated_at:rollback_updated_at}:row);
 const normalized={payload,target,schema,preimage:{rows},selected_keys:selected,updated_at,rollback_updated_at};
 const plan={format:FORMAT,input:normalized,payload_sha256:sha(stable(payload)),schema_sha256:schema.sha256,preimage_sha256:sha(JSON.stringify(rows)),expected_postimage_sha256:sha(JSON.stringify(expectedRows)),expected_rollback_sha256:sha(JSON.stringify(rollbackRows)),expected_rows:expectedRows,rollback_rows:rollbackRows,
  update:batch(schema,rows,selected,expectedRows),rollback:batch(schema,expectedRows,selected,rollbackRows),
  unchanged_keys:rows.filter(row=>!selected.includes(row.key)).map(row=>row.key),unselected_changed_policy_keys:POLICY_CONFIGURATION_KEYS.filter(key=>!selected.includes(key)&&byKey.get(key).value_json!==desired.get(key)),
  external_preflight_required:['actual account and D1 UUID/name with matching Worker origin/version/deployment/source','exact deployed schema catalog and full runtime_config row capture','current source-input bytes and immutable reviewed plan hash','Root-owned single mutation intent and qualified D1 atomic-batch result/readback','fresh complete preflight before any separately approved attempt after not_applied'],
  automatic_apply:false,automatic_retry:false,legal_release_approved:false,provider_approved:false,retention_policy_activation:false};
 return {...plan,plan_sha256:sha(stable(plan))};
}
export function validatePolicyConfigurationUpdatePlan(plan){need(plain(plan)&&plan.format===FORMAT,'plan_format');const rebuilt=createPolicyConfigurationUpdatePlan(plan.input);need(stable(plan)===stable(rebuilt),'plan_changed');return rebuilt;}
export function inspectPolicyConfigurationReadback(untrustedPlan,readback){
 const plan=validatePolicyConfigurationUpdatePlan(untrustedPlan);exact(readback,['target','schema','rows'],'readback_shape');
 const target=targetInput(readback.target),schema=schemaInput(readback.schema),rows=rowsInput(readback.rows);
 if(stable(target)!==stable(plan.input.target)||schema.sha256!==plan.schema_sha256)return {outcome:'identity_or_schema_changed',applied_exact:false,automatic_retry:false,needs_reconciliation:true};
 const raw=JSON.stringify(rows),pre=JSON.stringify(plan.input.preimage.rows),post=JSON.stringify(plan.expected_rows),rolled=JSON.stringify(plan.rollback_rows);
 const common={automatic_retry:false,legal_release_approved:false,provider_approved:false,retention_policy_activation:false};
 if(raw===post)return {...common,outcome:'applied_exact',applied_exact:true,unchanged_other_rows:true,changed_policy_keys:plan.input.selected_keys};
 if(raw===pre)return {...common,outcome:'not_applied',applied_exact:false,unchanged_other_rows:true,fresh_external_preflight_before_retry:true};
 if(raw===rolled)return {...common,outcome:'rolled_back_exact',applied_exact:false,unchanged_other_rows:true,old_policy_bodies_restored:true,technical_revisions_advanced:true};
 const selected=new Set(plan.input.selected_keys),unchanged=JSON.stringify(rows.filter(row=>!selected.has(row.key)))===JSON.stringify(plan.input.preimage.rows.filter(row=>!selected.has(row.key)));
 const exactKeys=plan.input.selected_keys.filter(key=>JSON.stringify(rows.find(row=>row.key===key))===JSON.stringify(plan.expected_rows.find(row=>row.key===key)));
 return {...common,outcome:exactKeys.length===selected.size?'applied_rows_present_configuration_changed':'partial_or_conflicting',applied_exact:false,unchanged_other_rows:unchanged,exact_policy_keys:exactKeys,needs_reconciliation:true};
}
async function privateJson(path){const name=resolve(path),s=await lstat(name);need(s.isFile()&&!s.isSymbolicLink()&&s.nlink===1&&(s.mode&0o077)===0&&await realpath(name)===name,'private_input');need(s.size<=4*MAX_TOTAL,'input_size');let raw;try{raw=new TextDecoder('utf-8',{fatal:true,ignoreBOM:true}).decode(await readFile(name));}catch{fail('input_utf8');}return parsePublicConfigurationJson(raw,{maxBytes:4*MAX_TOTAL});}
async function output(path,files){const name=resolve(path);await mkdir(name,{mode:0o700});need(await realpath(name)===name,'output_alias');for(const [file,value]of Object.entries(files))await writeFile(join(name,file),JSON.stringify(value,null,2)+'\n',{flag:'wx',mode:0o600});return name;}
export async function main(argv){
 const [action,...rest]=argv;if(action==='capture-sql'){need(rest.length===0,'arguments');console.log(JSON.stringify({runtime_config:RUNTIME_CONFIG_CAPTURE_SQL,schema:SCHEMA_CAPTURE_SQL}));return;}
 const options=new Map();need(rest.length%2===0,'arguments');for(let i=0;i<rest.length;i+=2){need(/^--[a-z-]+$/.test(rest[i])&&!options.has(rest[i]),'arguments');options.set(rest[i],rest[i+1]);}
 if(action==='plan'){need(options.size===2&&options.has('--input')&&options.has('--out'),'arguments');const plan=createPolicyConfigurationUpdatePlan(await privateJson(options.get('--input')));const directory=await output(options.get('--out'),{'plan.json':plan,'update-batch.json':plan.update,'rollback-batch.json':plan.rollback});console.log(JSON.stringify({prepared:true,plan_sha256:plan.plan_sha256,directory,provider_mutations:false,automatic_apply:false}));return;}
 if(action==='verify-readback'){need(options.size===3&&['--plan','--readback','--out'].every(k=>options.has(k)),'arguments');const result=inspectPolicyConfigurationReadback(await privateJson(options.get('--plan')),await privateJson(options.get('--readback')));await output(options.get('--out'),{'readback.json':result});console.log(JSON.stringify(result));return;}
 fail('Use capture-sql, plan or verify-readback. No execution command exists.');
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href)main(process.argv.slice(2)).catch(error=>{console.error(error.message);process.exitCode=1;});
