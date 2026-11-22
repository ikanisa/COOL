// Synthetic test data only; never import this helper into the live runner.
import {createHash} from 'node:crypto';
import {chmod,mkdtemp,readFile,rm} from 'node:fs/promises';
import {join} from 'node:path';
import {runPreflight} from './preflight.mjs';
import {makePlanSynthetic} from './capture-plan.mjs';
import authRef from '../managed-auth-archive/REFERENCE.json' with {type:'json'};
import storageRef from '../managed-storage-archive-v2/REFERENCE.json' with {type:'json'};
import {syntheticSnapshot as authSnapshot,syntheticValue as authValue} from '../managed-auth-archive/native-definition.mjs';
import {syntheticSnapshot as storageSnapshot,syntheticValue as storageValue} from '../managed-storage-archive-v2/native-definition.mjs';
import {sealAuthTable} from '../managed-auth-archive/auth.mjs';
import {sealStorageMetadataTable} from '../managed-storage-archive-v2/storage.mjs';

const sha=x=>createHash('sha256').update(x).digest('hex');
const project={project_ref:'rrlduytparvsjfmegalh',organization_id:'ghnjnepwvwknswrwzepn',status:'ACTIVE_HEALTHY'};
const token='synthetic-no-provider-access-token';
export const pin=async()=>sha(await readFile(new URL('./CAPTURE-SOURCE-PINS.json',import.meta.url)));
export const preflightPin=async()=>sha(await readFile(new URL('./SOURCE-PINS.json',import.meta.url)));
export async function testDirectory(t){const base=await mkdtemp('/private/tmp/collect-component-capture-test-');await chmod(base,0o700);t.after(()=>rm(base,{recursive:true,force:true}));return base;}
function fakeCounts(component,request){
 const auth=component==='auth',ref=auth?authRef:storageRef,hash=auth?'50e1fbcc6b1c97dab6d541fb2e342bdcb64b48efa5fc66a3757713d654b233d4':'38f477adf5aa3733af295a6c00893017f23ff6d253fe494ab554501660e11fbe';
 const identity={database:'postgres',server_version_num:'170011',read_only:'on',isolation:'repeatable read',row_security:'off',application_name:(auth?'collect.authmeta.':'collect.storagemeta.')+request.request_id.replaceAll('-',''),server_encoding:'UTF8',client_encoding:'UTF8',timezone:'UTC',backend_pid:'1234',snapshot:'10:10:',observed_at:'2026-11-14 10:00:00+00'};
 if(auth)return {format:'collect.managed-auth.counts.v1',request_id:request.request_id,project_ref:project.project_ref,reference_sha256:hash,identity,
  tables:ref.relations.filter(x=>x.kind==='r').map(x=>({schema:'auth',name:x.name,rows:'0'})).sort((a,b)=>a.name.localeCompare(b.name)),
  total_rows:'0',exact_auth_row_counts_measured:true,auth_cell_values_returned:false,sequence_values_returned:false,capture_dispatched:false};
 return {format:'collect.managed-storage.counts.v1',request_id:request.request_id,project_ref:project.project_ref,reference_sha256:hash,identity,
  tables:ref.relations.map(x=>({schema:'storage',name:x.name,rows:'0',rows_at_least:'0',exact:true})).sort((a,b)=>a.name.localeCompare(b.name)),total_rows:'0',within_row_caps:true,
  anonymous_bucket_count:'0',aggregates_measured:true,buckets:[],storage_identifiers_returned:false,metadata_bodies_returned:false,version_values_returned:false,object_bodies_read:false,capture_dispatched:false};
}
export async function syntheticPreflight(base,component){
 return runPreflight({component,pinsSha256:await preflightPin(),outputDirectory:join(base,'counts-'+component),environment:{COLLECT_COMPONENT_PREFLIGHT_ACCESS_TOKEN:token},
  transportFactory:()=>({async readProject(){return project;},async query(request){const p=fakeCounts(component,request);return {status:201,body:Buffer.from(JSON.stringify([{kind:p.format,payload:JSON.stringify(p)}]))};}})});
}
export async function syntheticPlan(base,component){
 const pre=await syntheticPreflight(base,component),pinsSha256=await pin();
 const out=await makePlanSynthetic({component,pinsSha256,resultPath:pre.result_path,resultSha256:pre.result_sha256,outputDirectory:join(base,'plan-'+component),environment:{}});
 return {...out,pinsSha256,pre};
}
export async function syntheticWire(plan,component){
 const auth=component==='auth',ref=auth?authRef:storageRef;
 const s=auth?authSnapshot():storageSnapshot(),p=JSON.parse(await readFile(plan.plan_path,'utf8'));
 s.fixture=false;s.reference=ref;s.reference_sha256=p.reference_sha256;s.postgres.database='postgres';s.postgres.application_name=(auth?'collect.authmeta.':'collect.storagemeta.')+p.request_id.replaceAll('-','');
 s.counts_preflight_sha256=p.canonical_counts_sha256;
 const name=auth?'users':'objects',target=ref.relations.find(t=>t.name===name),columns=ref.columns.filter(c=>c.relation_oid===target.oid),value=auth?authValue:storageValue;
 const row=columns.map(c=>value(ref,c,0));s.tables=s.tables.map(t=>t.name===name?(auth?sealAuthTable(ref,name,[row]):sealStorageMetadataTable(ref,name,[row])):t);
 const payload={format:auth?'collect.managed-auth.capture-response.v1':'collect.managed-storage.metadata.capture-response.v1',request_id:p.request_id,reference_sha256:p.reference_sha256,
  counts_preflight_sha256:p.canonical_counts_sha256,postgres:s.postgres,...(auth?{sequence:s.sequence}:{}),tables:s.tables.map((t,index)=>{
   const cells=t.rows.map(r=>r.cells);let bytes=0,max=0;for(const row of cells)for(const value of row)if(value!==null){const n=Buffer.byteLength(value);bytes+=n;max=Math.max(max,n);}
   return {schema:component,name:t.name,measure:{index,rows:String(cells.length),bytes:String(bytes),max_cell:String(max)},cells};})};
 return JSON.stringify([{kind:payload.format,payload:JSON.stringify(payload)}]);
}
