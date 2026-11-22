import {FENCE_IO_TIMEOUT_MS,fenceFailure,reserveDatabaseConnection} from '../../../supabase/functions/_shared/application-fence.js';
import type postgres from 'npm:postgres@3.4.7';

type Sql=ReturnType<typeof postgres>;
const need=(ok:unknown)=>{if(!ok)throw fenceFailure(null);};
const names={register:'collect_sms.work_register($1::uuid,$2::text,$3::text,$4::text)',
 assert:'collect_sms.work_assert($1::uuid,$2::bigint,$3::text)',
 close:'collect_sms.work_close($1::uuid,$2::bigint,$3::text,$4::text,$5::text,$6::integer,$7::integer)',
 status:'collect_sms.work_status($1::uuid)'};
async function bounded<T>(promise:Promise<T>):Promise<T>{let timer:ReturnType<typeof setTimeout>|undefined;try{
 return await Promise.race([promise,new Promise<T>((_,reject)=>{timer=setTimeout(()=>reject(fenceFailure(null)),FENCE_IO_TIMEOUT_MS);})]);
}finally{clearTimeout(timer);}}
export async function smsRuntimeRole(tx:any){
 await tx.unsafe('SET LOCAL ROLE collect_sms_runtime');
 await tx.unsafe("SELECT pg_catalog.set_config('collect.sms_verified','true',true)");
}
async function result(tx:any,name:keyof typeof names,values:unknown[]){
 const rows=await tx.unsafe('SELECT '+names[name]+' AS result',values);
 need(rows.length===1&&rows[0].result&&typeof rows[0].result==='object');return rows[0].result;
}
// The gateway login can only select collect_sms_runtime. These closed wrappers
// cannot act on another lane's admission or grant general application access.
export function smsFenceBackend(businessSql:Sql,controlSql:Sql,profileSha256:string){
 need(/^[a-f0-9]{64}$/.test(profileSha256));
 const call=(name:keyof typeof names,values:unknown[])=>bounded(businessSql.begin('ISOLATION LEVEL READ COMMITTED',async tx=>{
  await smsRuntimeRole(tx);return result(tx,name,values);
 }));
 return Object.freeze({
  register:(id:string,source:string,kind:string)=>call('register',[id,source,kind,profileSha256]),
  close:(id:string,epoch:number,source:string,outcome:string,reason:string,dispatches:number,uncertain:number)=>call('close',[id,epoch,source,outcome,reason,dispatches,uncertain]),
  status:(id:string)=>call('status',[id]),
  async lease(id:string,epoch:number,source:string){
   const tx=await reserveDatabaseConnection(controlSql);let begun=false,released=false,cleanup:Promise<void>|null=null;
   const release=()=>{
    if(!cleanup)cleanup=(async()=>{if(begun)await tx.unsafe('ROLLBACK');if(!released){released=true;tx.release();}})();
    // Observe the original rollback exactly once; an unconfirmed connection is
    // quarantined and never recycled into another request.
    return bounded(cleanup);
   };
   try{
    begun=true;await tx.unsafe('BEGIN ISOLATION LEVEL READ COMMITTED');await smsRuntimeRole(tx);
    await tx.unsafe("SET LOCAL statement_timeout='5s'");await tx.unsafe("SET LOCAL lock_timeout='5s'");
    await tx.unsafe('SELECT pg_catalog.pg_advisory_xact_lock_shared(7346371,1)');
    const row=await result(tx,'assert',[id,epoch,source]);
    return {row,async assert(){need(!cleanup&&!released);return bounded(result(tx,'assert',[id,epoch,source]));},release};
   }catch(error){await release().catch(()=>{});throw error;}
  }
 });
}
