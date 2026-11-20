/** Test-only module linkage and synthetic data. NOT Collect auth or DB guards. */
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {appendContributionCollision,appendContributionEntry,appendContributionSnapshots} from '../../domain/contribution-posting.mjs';
const root=new URL('../../../../../',import.meta.url);
export const upstream=readFileSync(new URL('upstream/collect/supabase/functions/_shared/domain/payments.js',root),'utf8');
export const refactored=readFileSync(new URL('integration/collect-posting/payments.js',root),'utf8');
export const expectedBlob='63f4ba68c2de7b4aa1cf3dc5523cf354aff5c643';
export function blob(text){const b=Buffer.from(text);return createHash('sha1').update(`blob ${b.length}\0`).update(b).digest('hex');}
const uid=n=>`${String(n).padStart(8,'0')}-1111-4111-8111-111111111111`;
export const ids={actor:uid(1),session:uid(2),request:uid(3),reconciliation:uid(4),payment:uid(5),member:uid(6),group:uid(7),evidence:uid(8),otherActor:uid(9),intent:uid(10)};
export function setup(overrides={}) {
 const state={snapshot:true,permission:true,queries:[],writes:[],events:[],mutations:[],readIndex:0,retained:[],
  actor:{userId:ids.actor,sessionId:ids.session},body:{p_request_id:ids.request,p_reconciliation_id:ids.reconciliation,p_reason:'Identity evidence reviewed'},
  reconciliation:{id:ids.reconciliation,payment_id:ids.payment,proposed_by:ids.otherActor,proposed_member_id:ids.member,status:'proposed',expected_payment_revision:7},
  payment:{id:ids.payment,collection_id:ids.group,evidence_id:ids.evidence,member_id:null,amount_minor:12500,revision:7,currency:'RWF',rail:'rwanda_momo',status:'recorded'},
  evidence:{external_reference:'wallet-1:FT100',receiver_network:'mtn_momo',receiver_momo_number:'+250780000001',currency:'RWF'},...overrides};
 let serial=0,ticks=0;
 class ApiError extends Error{constructor(status,code,message){super(message);this.status=status;this.code=code;}}
 const deps={ApiError,first:async(_env,q,...v)=>{
  state.queries.push({q,v});
  if(q.startsWith('SELECT * FROM reconciliations'))return state.reconciliation;
  if(q.startsWith('SELECT * FROM payments'))return state.payment;
  if(q.startsWith('SELECT external_reference,'))return state.evidence;
  if(q.includes("name='contribution_posting_snapshots'"))return state.snapshot?{name:'contribution_posting_snapshots'}:null;
  throw Error('Unexpected test query '+q);
 },rows:async()=>{throw Error('Unexpected rows')},id:()=>{const value='generated-'+(++serial);state.events.push(['id',value]);return value;},
 uuid:value=>{if(typeof value!=='string'||!/^\w{8}(?:-\w{4}){3}-\w{12}$/.test(value))throw new ApiError(400,'invalid_uuid','Invalid UUID');return value;},
 text:value=>String(value),integer:value=>value,now:()=>{const value=new Date(Date.UTC(2026,10,7)+ticks++).toISOString();state.events.push(['now',value]);return value;},
 digest:async value=>createHash('sha256').update(value).digest('hex'),stableJson:JSON.stringify,
 requirePermission:()=>{if(!state.permission)throw new ApiError(403,'42501','This action is unavailable.');},
 groupFor:()=>{throw Error('Unexpected group')},encrypt:()=>{throw Error('Unexpected encryption')},memberHistoryPage:()=>{throw Error('Unexpected history')},
 mutation:async(_env,actor,operation,request,body,value,writes,options)=>{state.writes=writes;state.mutations.push({actor,operation,request,body,value,options});return value;},
 retainedResponse:async()=>state.retained[state.readIndex++]??{found:false},
 appendContributionCollision,appendContributionEntry,appendContributionSnapshots};
 const env={DB:{prepare:sql=>({bind:(...values)=>({sql,values})})}};
 // Link these two exact reviewed source modules without fetching their unrelated
 // application dependencies. Only import declarations/exports are transformed.
 function link(source){
  const body=source.replace(/^import .*?;\n/gm,'').replace(/^export \{intentJson as contributionIntentJson\};\n/m,'').replace(/^export /gm,'');
  return new Function(...Object.keys(deps),body+'\nreturn financialRpc;')(...Object.values(deps));
 }
 return {state,async run(source=refactored,operation='approve_payment_reconciliation_v2',internal={}){
  try{return {value:await link(source)(operation,state.body,env,state.actor,internal),state};}
  catch(error){return {error:{status:error.status,code:error.code,message:error.message},state};}
 }};
}
