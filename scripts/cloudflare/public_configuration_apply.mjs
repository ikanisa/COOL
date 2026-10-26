#!/usr/bin/env node
// Pure local preparation/readback. This module never opens a provider connection.
import {createHash} from 'node:crypto';
import {lstat,readFile,mkdir,writeFile,realpath} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {pathToFileURL} from 'node:url';

export const PUBLIC_CONFIGURATION_KEYS=Object.freeze([
 'get_collection_type_catalog','get_public_runtime_config','list_account_request_reasons','policy:privacy','policy:terms',
]);
export const RUNTIME_CONFIG_CAPTURE_SQL='SELECT key,value_json,CAST(revision AS TEXT) AS revision,updated_by,updated_at FROM runtime_config ORDER BY key COLLATE BINARY';
export const SCHEMA_CAPTURE_SQL="SELECT type,name,tbl_name,sql FROM sqlite_schema WHERE sql IS NOT NULL AND name NOT GLOB '_cf_*' AND name NOT GLOB 'sqlite_*' ORDER BY type COLLATE BINARY,name COLLATE BINARY";
const HASH=/^[a-f0-9]{64}$/,UUID=/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const FORMAT='collect.public-configuration.plan.v1',MAX_VALUE=256*1024,MAX_SNAPSHOT=512*1024,MAX_TOTAL=1536*1024;
const keysSql=PUBLIC_CONFIGURATION_KEYS.map(key=>"'"+key+"'").join(',');
const sha=value=>createHash('sha256').update(value).digest('hex');
const plain=value=>value!==null&&typeof value==='object'&&!Array.isArray(value)&&[Object.prototype,null].includes(Object.getPrototypeOf(value));
const binary=(a,b)=>Buffer.compare(Buffer.from(a),Buffer.from(b));
const stable=value=>JSON.stringify(value,(_,entry)=>plain(entry)?Object.fromEntries(Object.keys(entry).sort(binary).map(key=>[key,entry[key]])):entry);
function fail(code){const error=new Error('Public configuration input refused: '+code);error.code=code;throw error;}
function need(condition,code){if(!condition)fail(code);}
function exact(value,keys,code){need(plain(value)&&Object.keys(value).length===keys.length&&keys.every(key=>Object.hasOwn(value,key)),code);}
function text(value,max,code,{empty=false,multiline=false}={}){
 need(typeof value==='string'&&(empty||value.length>0)&&Buffer.byteLength(value)<=max&&Buffer.from(value).toString()===value,code);
 need(!(multiline?/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/:/[\u0000-\u001f\u007f]/).test(value),code);
 return value;
}
function decoded(value,depth=0){
 need(depth<=24,'json_depth');
 if(typeof value==='string')text(value,MAX_TOTAL,'json_string',{empty:true,multiline:true});
 else if(typeof value==='number')need(Number.isFinite(value),'json_number');
 else if(Array.isArray(value)){need(value.length<=10000,'json_array');for(const item of value)decoded(item,depth+1);}
 else if(plain(value)){need(Object.keys(value).length<=10000,'json_object');for(const [key,item]of Object.entries(value)){text(key,1024,'json_key');decoded(item,depth+1);}}
 else need(value===null||typeof value==='boolean','json_type');
}
// Native JSON parsing supplies grammar/type semantics. This bounded lexical pass
// additionally refuses duplicate object keys, including escaped-key aliases.
export function parsePublicConfigurationJson(raw,{maxBytes=MAX_TOTAL}={}){
 text(raw,maxBytes,'json_utf8',{multiline:true});let cursor=0;
 const space=()=>{while(/[\t\n\r ]/.test(raw[cursor]??'')&&cursor<raw.length)cursor++;};
 const string=()=>{const start=cursor++;while(cursor<raw.length){const char=raw[cursor++];if(char==='"')return JSON.parse(raw.slice(start,cursor));if(char==='\\')cursor++;}fail('json_string');};
 const value=depth=>{
  need(depth<=24,'json_depth');space();const char=raw[cursor];
  if(char==='"'){string();return;}
  if(char==='{'||char==='['){
   const object=char==='{',end=object?'}':']',seen=new Set();cursor++;space();if(raw[cursor]===end){cursor++;return;}
   while(cursor<raw.length){
    if(object){space();need(raw[cursor]==='"','json_key');const key=string();need(!seen.has(key),'json_duplicate_key');seen.add(key);space();need(raw[cursor++]===':','json_separator');}
    value(depth+1);space();const next=raw[cursor++];if(next===end)return;need(next===',','json_separator');
   }fail('json_structure');
  }
  const start=cursor;while(cursor<raw.length&&!/[\t\n\r ,}\]]/.test(raw[cursor]))cursor++;need(cursor>start,'json_primitive');
 };
 try{value(0);space();need(cursor===raw.length,'json_trailing');const result=JSON.parse(raw);decoded(result);return result;}catch(error){if(error.code)throw error;fail('json_invalid');}
}
function jsonText(value,max,code){text(value,max,code,{multiline:true});return parsePublicConfigurationJson(value,{maxBytes:max});}
function strings(object,names,code){need(plain(object),code);for(const name of names)text(object[name],MAX_VALUE,code,{multiline:name==='body'||name==='regulatory_footer_note'});}
function options(list,code){
 need(Array.isArray(list)&&list.length>0&&list.length<=128,code);const seen=new Set();
 for(const entry of list){strings(entry,['key','label'],code);need(/^[a-z][a-z0-9_]{0,100}$/.test(entry.key)&&!seen.has(entry.key),code);seen.add(entry.key);}
 return seen;
}
function payloadValue(key,raw){
 const value=jsonText(raw,MAX_VALUE,'record_json');
 if(key==='get_public_runtime_config'){
  need(plain(value),'runtime_type');strings(value.brand,['display_name','legal_name','public_url','admin_url','app_download_url','regulatory_footer_note'],'runtime_brand');
  for(const name of ['public_url','admin_url','app_download_url']){let url;try{url=new URL(value.brand[name]);}catch{fail('runtime_url');}need(url.protocol==='https:'&&!url.username&&!url.password,'runtime_url');}
  need(Array.isArray(value.support_channels)&&value.support_channels.length>0&&value.support_channels.length<=16,'runtime_channels');const seen=new Set();
  for(const channel of value.support_channels){strings(channel,['key','value'],'runtime_channel');need(!seen.has(channel.key),'runtime_channel');seen.add(channel.key);if(Object.hasOwn(channel,'display_value'))text(channel.display_value,1024,'runtime_channel');}
  need(seen.has('support.whatsapp')&&seen.has('support.email'),'runtime_channels');
 }else if(key==='get_collection_type_catalog'){
  need(plain(value)&&value.country_code==='RW'&&value.locale==='en','catalog_locale');need(Array.isArray(value.types)&&value.types.length===5,'catalog_types');const seen=new Set();
  for(const item of value.types){
   strings(item,['key','label','short_purpose','icon_key','default_category_subtype','default_purpose_template_key'],'catalog_item');
   need(['ikimina','sport','church','wedding','other'].includes(item.key)&&!seen.has(item.key),'catalog_item');seen.add(item.key);
   need(options(item.subtypes,'catalog_subtypes').has(item.default_category_subtype)&&options(item.purpose_templates,'catalog_purposes').has(item.default_purpose_template_key),'catalog_defaults');
  }
 }else if(key==='list_account_request_reasons')options(value,'reason_options');
 else{
  need(plain(value)&&value.kind===key.slice(7)&&value.locale==='en','policy_kind');strings(value,['title','version'],'policy_metadata');
  need(Array.isArray(value.sections)&&value.sections.length>0&&value.sections.length<=256,'policy_sections');for(const section of value.sections)strings(section,['title','body'],'policy_section');
  need(value.content_status==='draft_for_legal_review'&&value.legal_release_approved===false&&HASH.test(value.source_document_sha256),'policy_approval');
  let sourceUrl;try{sourceUrl=new URL(value.source_url);}catch{fail('policy_source_url');}need(sourceUrl.protocol==='https:'&&!sourceUrl.username&&!sourceUrl.password,'policy_source_url');
  if(Object.hasOwn(value,'provider_approved'))need(value.provider_approved===false,'policy_approval');
 }
 return raw;
}
function payloadInput(payload){
 exact(payload,['schema_version','kind','api_source_id','legal_release_approved','provider_approved','retention_policy_activation','source_inputs','records'],'payload_shape');
 need(payload.schema_version===1&&payload.kind==='collect_public_configuration_seed'&&HASH.test(payload.api_source_id),'payload_identity');
 need(payload.legal_release_approved===false&&payload.provider_approved===false&&payload.retention_policy_activation===false,'payload_approval');
 need(plain(payload.source_inputs)&&Object.keys(payload.source_inputs).length>0&&Object.keys(payload.source_inputs).length<=256,'source_inputs');
 for(const [path,row]of Object.entries(payload.source_inputs)){
  need(/^[A-Za-z0-9_.-]+(?:\/[A-Za-z0-9_.-]+)*$/.test(path)&&path.split('/').every(part=>part!=='.'&&part!=='..'),'source_path');
  exact(row,['sha256','bytes'],'source_role');need(HASH.test(row.sha256)&&Number.isSafeInteger(row.bytes)&&row.bytes>0&&row.bytes<=8*1024*1024,'source_role');
 }
 need(Array.isArray(payload.records)&&payload.records.length===5,'record_count');const records=new Map();
 for(const row of payload.records){exact(row,['key','value_json'],'record_shape');need(PUBLIC_CONFIGURATION_KEYS.includes(row.key)&&!records.has(row.key),'record_key');records.set(row.key,payloadValue(row.key,row.value_json));}
 return {...payload,source_inputs:Object.fromEntries(Object.entries(payload.source_inputs).sort(([a],[b])=>binary(a,b))),records:PUBLIC_CONFIGURATION_KEYS.map(key=>({key,value_json:records.get(key)}))};
}
function targetInput(target){
 exact(target,['account_id','database_name','database_id','api_source_id'],'target_shape');need(/^[a-f0-9]{32}$/.test(target.account_id)&&/^[a-z][a-z0-9-]{0,62}$/.test(target.database_name)&&UUID.test(target.database_id)&&HASH.test(target.api_source_id),'target_identity');return {...target};
}
function orderedRows(input){
 need(Array.isArray(input)&&input.length<=10000,'preimage_rows');let previous=null;const rows=[];
 for(const row of input){
  exact(row,['key','value_json','revision','updated_by','updated_at'],'row_shape');text(row.key,256,'row_key');jsonText(row.value_json,MAX_VALUE,'row_json');
  need(typeof row.revision==='string'&&/^(?:0|-?[1-9][0-9]*)$/.test(row.revision),'row_revision');const revision=BigInt(row.revision);need(revision>=-9223372036854775808n&&revision<=9223372036854775807n,'row_revision');
  need(row.updated_by===null||typeof row.updated_by==='string'&&UUID.test(row.updated_by),'row_actor');text(row.updated_at,128,'row_timestamp');
  need(previous===null||binary(previous,row.key)<0,'row_order_or_duplicate');previous=row.key;
  rows.push({key:row.key,value_json:row.value_json,revision:row.revision,updated_by:row.updated_by,updated_at:row.updated_at});
 }
 need(Buffer.byteLength(JSON.stringify(rows))<=MAX_SNAPSHOT,'preimage_size');return rows;
}
function schemaInput(schema){
 exact(schema,['rows','sha256'],'schema_shape');need(HASH.test(schema.sha256)&&Array.isArray(schema.rows)&&schema.rows.length>0&&schema.rows.length<=4096,'schema_identity');
 let previous=null;const rows=[];
 for(const row of schema.rows){
  exact(row,['type','name','tbl_name','sql'],'schema_row');need(['table','index','trigger','view'].includes(row.type),'schema_type');text(row.name,256,'schema_name');text(row.tbl_name,256,'schema_table');text(row.sql,MAX_VALUE,'schema_sql',{multiline:true});
  need(!row.name.startsWith('_cf_')&&!row.name.startsWith('sqlite_'),'schema_internal');const order=row.type+'\0'+row.name;need(previous===null||binary(previous,order)<0,'schema_order_or_duplicate');previous=order;
  rows.push({type:row.type,name:row.name,tbl_name:row.tbl_name,sql:row.sql});
 }
 need(rows.some(row=>row.type==='table'&&row.name==='runtime_config'&&row.tbl_name==='runtime_config'),'schema_runtime_config');
 const raw=JSON.stringify(rows);need(Buffer.byteLength(raw)<=MAX_SNAPSHOT&&sha(raw)===schema.sha256,'schema_hash');return {rows,sha256:schema.sha256};
}
const currentState=`SELECT json_group_array(json_object('key',key,'value_json',value_json,'revision',CAST(revision AS TEXT),'updated_by',updated_by,'updated_at',updated_at)) FROM (${RUNTIME_CONFIG_CAPTURE_SQL})`;
const currentSchema=`SELECT json_group_array(json_object('type',type,'name',name,'tbl_name',tbl_name,'sql',sql)) FROM (${SCHEMA_CAPTURE_SQL})`;
function guardSql(stateParam,schemaParam){return `guard AS MATERIALIZED (SELECT CASE WHEN
 ((${currentState}) COLLATE BINARY)=${stateParam} AND ((${currentSchema}) COLLATE BINARY)=${schemaParam}
 THEN 1 ELSE json('collect_public_configuration_guard_failed') END AS passed)`;}
function queries(input,expectedRows){
 const schema=JSON.stringify(input.schema.rows),preimage=JSON.stringify(input.preimage.rows),at=input.updated_at;
 const seed=PUBLIC_CONFIGURATION_KEYS.map((key,i)=>"('"+key+"',?"+(i+4)+')').join(',\n');
 const insertSql=`WITH seed(key,value_json) AS (VALUES ${seed}),\n${guardSql('?2','?1')}
INSERT INTO runtime_config(key,value_json,revision,updated_by,updated_at)
SELECT seed.key,CASE WHEN guard.passed=1 THEN seed.value_json ELSE json('collect_public_configuration_guard_failed') END,1,NULL,?3
FROM seed CROSS JOIN guard;`;
 const insertParams=[schema,preimage,at,...input.payload.records.map(row=>row.value_json)];
 const rollbackSql=`WITH seed(key) AS (VALUES ${PUBLIC_CONFIGURATION_KEYS.map(key=>"('"+key+"')").join(',')}),\n${guardSql('?2','?1')}
DELETE FROM runtime_config WHERE key IN (SELECT seed.key FROM seed CROSS JOIN guard WHERE guard.passed=1) RETURNING key;`;
 const rollbackParams=[schema,JSON.stringify(expectedRows)];
 need(Buffer.byteLength(insertSql)<100000&&Buffer.byteLength(rollbackSql)<100000&&insertParams.length===8,'query_limit');
 need(insertParams.reduce((size,value)=>size+Buffer.byteLength(value),0)<=MAX_TOTAL,'parameter_size');
 return {insert:{sql:insertSql,params:insertParams,sha256:sha(stable({sql:insertSql,params:insertParams})),expected_changes:5},
  rollback:{sql:rollbackSql,params:rollbackParams,sha256:sha(stable({sql:rollbackSql,params:rollbackParams})),expected_changes:5,execute:false}};
}
export function createPublicConfigurationPlan(input){
 exact(input,['payload','target','schema','preimage','updated_at'],'plan_input');exact(input.preimage,['rows'],'preimage_shape');
 const payload=payloadInput(input.payload),target=targetInput(input.target),schema=schemaInput(input.schema),rows=orderedRows(input.preimage.rows);
 need(payload.api_source_id===target.api_source_id,'source_mismatch');
 need(rows.every(row=>!PUBLIC_CONFIGURATION_KEYS.includes(row.key)),'public_key_already_present');
 text(input.updated_at,24,'timestamp');need(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(input.updated_at)&&Number.isFinite(Date.parse(input.updated_at))&&new Date(input.updated_at).toISOString()===input.updated_at,'timestamp');
 const normalized={payload,target,schema,preimage:{rows},updated_at:input.updated_at};
 const expectedRows=[...rows,...payload.records.map(row=>({...row,revision:'1',updated_by:null,updated_at:input.updated_at}))].sort((a,b)=>binary(a.key,b.key));
 const plan={format:FORMAT,input:normalized,payload_sha256:sha(stable(payload)),schema_sha256:schema.sha256,
  preimage_sha256:sha(JSON.stringify(rows)),expected_postimage_sha256:sha(JSON.stringify(expectedRows)),expected_rows:expectedRows,
  ...queries(normalized,expectedRows),external_preflight_required:['actual account and D1UUID/name','deployed Worker version/source identity','qualified source/schema identity','source-input bytes and immutable reviewed plan hash'],
  automatic_apply:false,automatic_retry:false,legal_release_approved:false,provider_approved:false,retention_policy_activation:false};
 return {...plan,plan_sha256:sha(stable(plan))};
}
export function validatePublicConfigurationPlan(plan){
 need(plain(plan)&&plan.format===FORMAT,'plan_format');const rebuilt=createPublicConfigurationPlan(plan.input);need(stable(plan)===stable(rebuilt),'plan_changed');return rebuilt;
}
export function inspectPublicConfigurationReadback(untrustedPlan,readback){
 const plan=validatePublicConfigurationPlan(untrustedPlan);exact(readback,['target','schema','rows'],'readback_shape');
 const target=targetInput(readback.target),schema=schemaInput(readback.schema),rows=orderedRows(readback.rows);
 if(stable(target)!==stable(plan.input.target)||schema.sha256!==plan.schema_sha256)return {outcome:'identity_or_schema_changed',applied_exact:false,automatic_retry:false};
 const observed=JSON.stringify(rows),before=JSON.stringify(plan.input.preimage.rows),after=JSON.stringify(plan.expected_rows);
 if(observed===after)return {outcome:'applied_exact',applied_exact:true,unchanged_prior_rows:true,public_rows:5,automatic_retry:false,legal_release_approved:false};
 if(observed===before)return {outcome:'not_applied',applied_exact:false,unchanged_prior_rows:true,public_rows:0,automatic_retry:false,fresh_external_preflight_before_retry:true};
 const publicRows=rows.filter(row=>PUBLIC_CONFIGURATION_KEYS.includes(row.key)),unchanged=JSON.stringify(rows.filter(row=>!PUBLIC_CONFIGURATION_KEYS.includes(row.key)))===before;
 const exactKeys=publicRows.filter(row=>JSON.stringify(row)===JSON.stringify(plan.expected_rows.find(expected=>expected.key===row.key))).map(row=>row.key);
 return {outcome:publicRows.length===5&&exactKeys.length===5?'applied_rows_present_configuration_changed':'partial_or_conflicting',applied_exact:false,
  public_rows:publicRows.length,exact_public_keys:exactKeys,unchanged_prior_rows:unchanged,automatic_retry:false,needs_reconciliation:true};
}
async function privateJson(path){
 const name=resolve(path),s=await lstat(name);need(s.isFile()&&!s.isSymbolicLink()&&s.nlink===1&&(s.mode&0o077)===0&&await realpath(name)===name,'private_input');
 need(s.size<=4*MAX_TOTAL,'input_size');let raw;try{raw=new TextDecoder('utf-8',{fatal:true,ignoreBOM:true}).decode(await readFile(name));}catch{fail('input_utf8');}return parsePublicConfigurationJson(raw,{maxBytes:4*MAX_TOTAL});
}
async function output(path,files){
 const name=resolve(path);await mkdir(name,{mode:0o700});need(await realpath(name)===name,'output_alias');
 for(const [file,value]of Object.entries(files))await writeFile(join(name,file),JSON.stringify(value,null,2)+'\n',{flag:'wx',mode:0o600});return name;
}
export async function main(argv){
 const [action,...rest]=argv;
 if(action==='capture-sql'){need(rest.length===0,'arguments');console.log(JSON.stringify({runtime_config:RUNTIME_CONFIG_CAPTURE_SQL,schema:SCHEMA_CAPTURE_SQL}));return;}
 const options=new Map();need(rest.length%2===0,'arguments');for(let i=0;i<rest.length;i+=2){need(/^--[a-z-]+$/.test(rest[i])&&!options.has(rest[i]),'arguments');options.set(rest[i],rest[i+1]);}
 if(action==='plan'){
  need(options.size===2&&options.has('--input')&&options.has('--out'),'arguments');const plan=createPublicConfigurationPlan(await privateJson(options.get('--input')));
  const directory=await output(options.get('--out'),{'plan.json':plan,'insert-query.json':plan.insert,'rollback-query.json':plan.rollback});
  console.log(JSON.stringify({prepared:true,plan_sha256:plan.plan_sha256,directory,provider_mutations:false,automatic_apply:false}));return;
 }
 if(action==='verify-readback'){
  need(options.size===3&&['--plan','--readback','--out'].every(key=>options.has(key)),'arguments');
  const result=inspectPublicConfigurationReadback(await privateJson(options.get('--plan')),await privateJson(options.get('--readback')));
  await output(options.get('--out'),{'readback.json':result});console.log(JSON.stringify(result));return;
 }
 fail('Use capture-sql, plan or verify-readback. No execution command exists.');
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href)main(process.argv.slice(2)).catch(error=>{console.error(error.message);process.exitCode=1;});
