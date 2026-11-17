import {fenceFailure} from '../../../supabase/functions/_shared/application-fence.js';
import {bound,enter,reserve,rollbackAndRelease,transact,type Pool,type Transaction} from './transactions.ts';
const names={register:'collect_sms.work_register($1::uuid,$2::text,$3::text,$4::text)',
 assert:'collect_sms.work_assert($1::uuid,$2::bigint,$3::text)',
 close:'collect_sms.work_close($1::uuid,$2::bigint,$3::text,$4::text,$5::text,$6::integer,$7::integer)',
 status:'collect_sms.work_status($1::uuid)'} as const;
const need=(value:unknown)=>{if(!value)throw fenceFailure(null);};
async function result(tx:Transaction,name:keyof typeof names,values:unknown[]){
 const rows=await tx.query('SELECT '+names[name]+' AS result',values);const value=rows?.[0]?.result;
 need(rows?.length===1&&value&&typeof value==='object');return value;
}
export function managedSmsFence(pool:Pool,profileSha256:string){
 need(/^[a-f0-9]{64}$/.test(profileSha256));
 const call=(name:keyof typeof names,values:unknown[])=>bound(transact(pool,tx=>result(tx,name,values)));
 return Object.freeze({
  register:(id:string,source:string,kind:string)=>call('register',[id,source,kind,profileSha256]),
  close:(id:string,epoch:number,source:string,outcome:string,reason:string,dispatches:number,uncertain:number)=>call('close',[id,epoch,source,outcome,reason,dispatches,uncertain]),
  status:(id:string)=>call('status',[id]),
  async lease(id:string,epoch:number,source:string){
   const tx=await reserve(pool);let begun=false,closed=false,cleanup:Promise<void>|undefined;
   const release=()=>{if(!cleanup)cleanup=(async()=>{closed=true;if(begun)await rollbackAndRelease(tx);else tx.release();})();return bound(cleanup);};
   try{begun=true;await enter(tx);await tx.query('SELECT pg_catalog.pg_advisory_xact_lock_shared(7346371,1)');
    const row=await result(tx,'assert',[id,epoch,source]);
    return {row,async assert(){need(!closed);return bound(result(tx,'assert',[id,epoch,source]));},release};
   }catch(error){await release().catch(()=>{});throw error;}
  }
 });
}
