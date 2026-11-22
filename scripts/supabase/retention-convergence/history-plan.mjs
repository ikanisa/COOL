// Read-only, non-executable history plan. It never connects, writes SQL, makes
// migration files or records versions. The live project needs a separately
// qualified executor, fenced state and reviewed branch-specific migration set.
import {createHash} from 'node:crypto';
import {canonical} from '../../../supabase/functions/_shared/storage/protocol.js';
import {pinnedBranchInputs} from './ordered-chain-fixture.mjs';

const PROJECT='rrlduytparvsjfmegalh',FORMAT='collect.managed-history-candidate.v1';
const sha=value=>createHash('sha256').update(value).digest('hex');
const exact=(o,keys)=>o!==null&&typeof o==='object'&&!Array.isArray(o)&&Object.getPrototypeOf(o)===Object.prototype&&
 Object.keys(o).sort().join('\0')===[...keys].sort().join('\0');
const fail=code=>{const error=Error(code);error.code=code;throw error;};
const ALT=Object.freeze({
 '20261114110000_burimunsi_native_retention_positive_links.sql':{
  version:'20261114110001',name:'burimunsi_native_retention_positive_links_managed_convergence'},
 '20261114110200_storage_iceberg_retention_census.sql':{
  version:'20261114110201',name:'storage_iceberg_retention_census_managed_convergence'},
});
const FORWARD={version:'20261114110400',name:'burimunsi_retention_bounded_user_id'};
const parseName=value=>{const match=/^(\d{14})_([a-z0-9_]+)\.sql$/.exec(value);if(!match)fail('history_candidate_source_invalid');return {version:match[1],name:match[2]};};

/**
 * observedJson is canonical JSON of exactly the 14 observed rows with keys
 * {version,name,statement_count,source_sha256}, ordered by version. The caller
 * supplies a separately pinned hash of those exact bytes. Inputs and result are
 * operational metadata; this function cannot attest their provenance.
 */
export async function planManagedHistory(observedJson,expectedObservedSha256){
 if(typeof observedJson!=='string'||Buffer.byteLength(observedJson)>32768||
  !/^[a-f0-9]{64}$/.test(expectedObservedSha256??'')||sha(observedJson)!==expectedObservedSha256)fail('history_candidate_observation_invalid');
 let observed;try{observed=JSON.parse(observedJson);}catch{fail('history_candidate_observation_invalid');}
 if(canonical(observed)!==observedJson||!Array.isArray(observed)||observed.length!==14)fail('history_candidate_observation_invalid');
 const inputs=await pinnedBranchInputs(),sources=inputs.migrations;
 if(sources.length!==65)fail('history_candidate_source_invalid');
 for(let index=0;index<14;index++){
  const row=observed[index],source=sources[index],identity=parseName(source.name);
  if(!exact(row,['version','name','statement_count','source_sha256'])||row.version!==identity.version||
   row.name!==identity.name||row.statement_count!==1||row.source_sha256!==source.sha256)fail('history_candidate_observation_changed');
 }
 const actions=sources.slice(14).map(source=>{
  const original=parseName(source.name),alternative=ALT[source.name],variant=inputs.variants[source.name];
  if(Boolean(alternative)!==Boolean(variant))fail('history_candidate_source_invalid');
  return {version:alternative?.version??original.version,name:alternative?.name??original.name,
   source_version:original.version,source_name:original.name,source_sha256:source.sha256,
   executable_path:variant?'scripts/supabase/retention-convergence/'+variant.name:'supabase/migrations/'+source.name,
   executable_sha256:variant?.sha256??source.sha256,kind:variant?'branch_candidate':'original_source',
   work_in_progress:['20261114110100','20261114110300'].includes(original.version)};
 });
 actions.push({version:FORWARD.version,name:FORWARD.name,source_version:null,source_name:null,source_sha256:null,
  executable_path:'scripts/supabase/retention-convergence/'+inputs.forward.name,executable_sha256:inputs.forward.sha256,
  kind:'forward_candidate',work_in_progress:false});
 const sourceVersions=new Set(sources.map(x=>parseName(x.name).version)),seen=new Set();
 for(let index=0;index<actions.length;index++){
  const action=actions[index];
  if(!/^\d{14}$/.test(action.version)||seen.has(action.version)||
   (index>0&&actions[index-1].version>=action.version)||
   (action.kind!=='original_source'&&sourceVersions.has(action.version)))fail('history_candidate_version_collision');
  seen.add(action.version);
 }
 const originalsExcluded=Object.keys(ALT).map(name=>({file:name,...parseName(name)}));
 if(originalsExcluded.some(x=>seen.has(x.version)))fail('history_candidate_original_misrecorded');
 return {format:FORMAT,project_ref:PROJECT,status:'analysis_only',
  observed_history_sha256:expectedObservedSha256,observed_history_count:14,source_file_count:65,
  pending_action_count:actions.length,excluded_divergent_originals:originalsExcluded,actions,
  history_written:false,execution_supported:false,source_directory_push_safe:false,production_authorized:false,
  limitations:['Distinct candidate versions need independently reviewed files and an executor','Both Admin migrations remain work in progress','Managed catalogue, fence, backup and data transfer remain unqualified','Existing local and planned managed histories remain distinct']};
}
