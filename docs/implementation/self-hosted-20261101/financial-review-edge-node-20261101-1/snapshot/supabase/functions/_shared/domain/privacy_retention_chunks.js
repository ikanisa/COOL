import {ApiError,digest,stableJson} from './core.js';

// These are execution/inventory bounds, never legal retention decisions. Only
// the four existing subject-owned SQL adapters receive the larger row budget.
export const erasableTables=Object.freeze(['notification_devices','notification_preferences','notification_events','support_requests']);
export const SQL_CHUNK_ROWS=40;
export const SQL_OWN_ROW_LIMIT=2000;
const fail=()=>{throw new ApiError(409,'privacy_retention_chunk_coverage_unknown','Retention chunk coverage could not be verified.');};
const exact=(v,keys)=>v&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).length===keys.length&&keys.every(k=>Object.hasOwn(v,k));
const hash=value=>digest(stableJson(value));
const sha=value=>typeof value==='string'&&/^[a-f0-9]{64}$/.test(value);
export const ownRowKey=table=>{if(!erasableTables.includes(table))fail();return table==='notification_preferences'?'user_id':'id';};
export function rowPages(rows){const pages=[];for(let i=0;i<rows.length;i+=SQL_CHUNK_ROWS)pages.push(rows.slice(i,i+SQL_CHUNK_ROWS));return pages.length?pages:[[]];}

export async function ownRowInventory(env,table,where){
 const key=ownRowKey(table),rows=[],seen=new Set();let cursor=null;
 while(true){
  const query='SELECT * FROM "'+table+'" WHERE '+where.sql+(cursor===null?'':' AND "'+key+'" COLLATE BINARY>?')+' ORDER BY "'+key+'" COLLATE BINARY LIMIT ?';
  const page=(await env.DB.prepare(query).bind(...where.args,...(cursor===null?[]:[cursor]),SQL_CHUNK_ROWS).all()).results;
  for(const row of page){const id=row[key];if(typeof id!=='string'||!id||seen.has(id))fail();seen.add(id);rows.push(row);if(rows.length>SQL_OWN_ROW_LIMIT)throw new ApiError(409,'privacy_retention_inventory_limit','Retention source coverage could not be verified.');}
  if(page.length<SQL_CHUNK_ROWS)break;cursor=page.at(-1)[key];
 }
 return rows;
}
export async function rowChunkManifest(targetIds){
 if(!Array.isArray(targetIds)||targetIds.length>SQL_OWN_ROW_LIMIT||new Set(targetIds).size!==targetIds.length||targetIds.some(v=>typeof v!=='string'||!v))fail();
 return {contract_version:1,chunk_rows:SQL_CHUNK_ROWS,target_ids_sha256:await hash(targetIds)};
}
export async function rowChunkState(env,task,plan){
 if(!erasableTables.includes(task.class_name))return null;
 const expected=JSON.parse(task.expected_json);if(!Object.hasOwn(expected,'row_chunks'))return null;
 const manifest=expected.row_chunks;if(!exact(manifest,['contract_version','chunk_rows','target_ids_sha256'])||manifest.contract_version!==1||manifest.chunk_rows!==SQL_CHUNK_ROWS||!Array.isArray(expected.target_ids)||stableJson(manifest)!==stableJson(await rowChunkManifest(expected.target_ids)))fail();
 const records=(await env.DB.prepare("SELECT * FROM privacy_retention_outcomes WHERE task_id=? AND json_type(outcome_json,'$.row_chunk') IS NOT NULL ORDER BY fence,operation_id LIMIT ?").bind(task.id,Math.ceil(SQL_OWN_ROW_LIMIT/SQL_CHUNK_ROWS)+2).all()).results;
 const absent=new Set();let head=null,post=null,lastFence=0;
 for(const record of records){
  const out=JSON.parse(record.outcome_json),c=out.row_chunk;if(plan&&(out.source_id!==plan.source_id||out.policy_sha256!==plan.policy_sha256))fail();
  if(!exact(c,['contract_version','target_ids_sha256','parent_outcome_sha256','ids','absent_count','remaining_count','post_images'])||c.contract_version!==1||c.target_ids_sha256!==manifest.target_ids_sha256||c.parent_outcome_sha256!==head||record.fence<=lastFence||!Array.isArray(c.ids)||c.ids.length>SQL_CHUNK_ROWS||(!c.ids.length&&expected.target_ids.length!==0)||new Set(c.ids).size!==c.ids.length)fail();
  for(const id of c.ids){if(!expected.target_ids.includes(id)||absent.has(id))fail();absent.add(id);}
  if(c.absent_count!==absent.size||c.remaining_count!==expected.target_ids.length-absent.size||out.verified!==(c.remaining_count===0)||out.disposition!==(out.verified?'own_rows_absence_verified':'own_rows_chunk_absence_verified')||!exact(c.post_images,['tables'])||!exact(c.post_images.tables,[task.class_name]))fail();
  const image=c.post_images.tables[task.class_name];if(!exact(image,['count','sha256'])||!Number.isSafeInteger(image.count)||image.count<0||image.count!==expected.count-absent.size||!sha(image.sha256))fail();
  head=await digest(record.outcome_json);post=c.post_images;lastFence=record.fence;
 }
 if(records.length>Math.max(1,Math.ceil(expected.target_ids.length/SQL_CHUNK_ROWS)))fail();
 return {expected,absent,head,post,lastFence};
}
export async function rowChunkOutcome(state,ids,post){
 if(!Array.isArray(ids)||ids.length>SQL_CHUNK_ROWS||new Set(ids).size!==ids.length||(!ids.length&&state.expected.target_ids.length!==0))fail();
 const absent=new Set(state.absent);for(const id of ids){if(absent.has(id)||!state.expected.target_ids.includes(id))fail();absent.add(id);}
 const remaining=state.expected.target_ids.length-absent.size;
 return {verified:remaining===0,disposition:remaining===0?'own_rows_absence_verified':'own_rows_chunk_absence_verified',rows_erased_or_confirmed_absent:absent.size,rows_remaining:remaining,row_chunk:{contract_version:1,target_ids_sha256:state.expected.row_chunks.target_ids_sha256,parent_outcome_sha256:state.head,ids,absent_count:absent.size,remaining_count:remaining,post_images:post},erasure_completed:false,all_data_erased:false};
}
