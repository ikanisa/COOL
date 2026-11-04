import {applicationWork,noteUnknownEffect} from './application-fence.js';
const statuses=new Set(['disabled','capacity','rate_limited','idle','attempted_unconfirmed']);
const keys=['attempted','delivery_confirmed','failed','overflowed','scanned','status'];
function result(value){
 if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).sort().join(',')!==keys.join(',')
 ||!statuses.has(value.status)||value.delivery_confirmed!==false
 ||!Number.isSafeInteger(value.scanned)||value.scanned<0||value.scanned>4
 ||!Number.isSafeInteger(value.attempted)||value.attempted<0||value.attempted>32
 ||!Number.isSafeInteger(value.failed)||value.failed<0||value.failed>value.attempted
 ||!Number.isSafeInteger(value.overflowed)||value.overflowed<0||value.overflowed>value.scanned)throw new Error('member_realtime_result_unconfirmed');
 return value;
}
// The SQL singleton is independently OFF/source-bound. An environment flag never
// bypasses it; a missing flag makes no DB/provider call. This is an awaited jobs
// maintenance hook, after authoritative auth cleanup and outside money commits.
export async function publishMemberRealtime(env){
 if(env.MEMBER_REALTIME_PUBLISHER_ENABLED!=='true')return{status:'disabled',scanned:0,attempted:0,failed:0,overflowed:0,delivery_confirmed:false,authoritative_polling:true};
 const work=applicationWork(env);
 try{
  const observed=result(await work.dispatch('realtime',()=>env.DB.prepare('SELECT private.collect_member_realtime_publish() AS result').first('result')));
  // Database send is not a subscriber receipt. Preserve that uncertain external
  // observation without changing any financial/provider journal or replaying it.
  if(observed.attempted>0)noteUnknownEffect(env,'realtime');
  return{...observed,authoritative_polling:true};
 }catch(error){
  if(['application_fenced','application_fence_unavailable'].includes(error?.code))throw error;
  noteUnknownEffect(env,'realtime');
  return{status:'unavailable',scanned:null,attempted:null,failed:null,overflowed:null,delivery_confirmed:false,authoritative_polling:true};
 }
}
