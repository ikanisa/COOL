import postgres from 'npm:postgres@3.4.7';
import {createManagedSmsHandler} from './handler.ts';
import type {Pool} from './transactions.ts';
// Source-level closure; neither a request nor an environment variable can
// assert that the managed role, identity or provider boundaries are proven.
const MANAGED_SMS_ISOLATION_QUALIFIED=false;
const unavailable=()=>Response.json({error:{code:'gateway_unavailable',message:'The SMS gateway is unavailable. Retain the original operation for reconciliation.'}},{status:503,headers:{'cache-control':'no-store','x-content-type-options':'nosniff'}});
function defaultPool(binding:any):Pool{
 if(!binding||typeof binding.connectionString!=='string'||!binding.connectionString)throw Error('binding_unavailable');
 // postgres.js .unsafe() also needs its own explicit prepared option: see transactions.ts.
 return postgres(binding.connectionString,{max:4,prepare:true,fetch_types:true,connect_timeout:10,idle_timeout:20,
  types:{bigint:{to:20,from:[20],serialize:String,parse:(v:string)=>{const n=Number(v);if(!Number.isSafeInteger(n))throw Error('integer_range');return n;}}},onnotice:()=>{}}) as unknown as Pool;
}
const managed=createManagedSmsHandler({poolFactory:defaultPool});
export default {fetch(request:Request,env:Record<string,any>,ctx:{waitUntil:(p:Promise<unknown>)=>void}){
 if(!MANAGED_SMS_ISOLATION_QUALIFIED)return unavailable();return managed(request,env,ctx);
}};
