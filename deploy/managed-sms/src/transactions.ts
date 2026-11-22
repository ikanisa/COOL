// Hyperdrive transactions are the unit of backend affinity. Never rely on a
// session SET, prepared statement, or lock surviving COMMIT/ROLLBACK.
import {reserveDatabaseConnection, fenceFailure} from '../../../supabase/functions/_shared/application-fence.js';

const TIMEOUT_MS=5000;
export const ROLE='collect_sms_runtime';
export const LOGIN='collect_sms_edge';
const VERIFY_LOGIN=`SELECT session_user::text AS login_name,current_user::text AS active_name,
 (SELECT rolcanlogin AND NOT (rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls OR rolinherit)
  FROM pg_catalog.pg_roles WHERE rolname=session_user) AS login_safe,
 (SELECT NOT (rolcanlogin OR rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls OR rolinherit)
  FROM pg_catalog.pg_roles WHERE rolname='collect_sms_runtime') AS role_safe,
 (SELECT count(*)::int FROM pg_catalog.pg_roles r WHERE r.rolname NOT IN (session_user,'collect_sms_runtime')
  AND pg_catalog.pg_has_role(session_user,r.rolname,'MEMBER')) AS other_memberships,
 pg_catalog.has_schema_privilege(session_user,'private','USAGE') AS private_usage,
 pg_catalog.has_schema_privilege(session_user,'app','USAGE') AS app_usage,
 pg_catalog.has_schema_privilege(session_user,'public','CREATE') AS public_create,
 pg_catalog.has_database_privilege(session_user,current_database(),'CREATE') AS database_create`;
const VERIFY_ROLE=`SELECT current_user::text AS active_name, current_setting('collect.sms_verified',true) AS verified,
 pg_catalog.has_schema_privilege(current_user,'collect_sms','USAGE') AS sms_usage,
 pg_catalog.has_schema_privilege(current_user,'collect_sms','CREATE') AS sms_create,
 pg_catalog.has_schema_privilege(current_user,'app','USAGE') AS app_usage,
 pg_catalog.has_schema_privilege(current_user,'private','USAGE') AS private_usage`;
const need=(value:unknown)=>{if(!value)throw fenceFailure(null);};
export type RawTx={unsafe:(sql:string,values?:unknown[],options?:Record<string,unknown>)=>Promise<any>;release:()=>void};
export type Pool={reserve:()=>Promise<RawTx>;end:(options?:Record<string,unknown>)=>Promise<unknown>};
export type Transaction={query:(sql:string,values?:unknown[])=>Promise<any>;release:()=>void};

// postgres.js unsafe() defaults to prepare:false even when its client defaults
// to true; explicitly override it for every statement, including parameters.
export async function reserve(pool:Pool):Promise<Transaction>{
 const tx=await reserveDatabaseConnection(pool) as RawTx;let released=false;
 return {query:(text,values=[])=>tx.unsafe(text,values,{prepare:true,simple:false}),release(){if(!released){released=true;tx.release();}}};
}
export async function bound<T>(p:Promise<T>,ms=TIMEOUT_MS):Promise<T>{let timer:ReturnType<typeof setTimeout>|undefined;try{
 return await Promise.race([p,new Promise<T>((_,reject)=>{timer=setTimeout(()=>reject(fenceFailure(null)),ms);})]);
 }finally{clearTimeout(timer);}}
export async function enter(tx:Transaction){
 await tx.query('BEGIN ISOLATION LEVEL READ COMMITTED');
 await tx.query("SET LOCAL statement_timeout='8s'");await tx.query("SET LOCAL lock_timeout='5s'");
 const rows=await tx.query(VERIFY_LOGIN);const r=rows?.[0];
 need(rows?.length===1&&r?.login_name===LOGIN&&r?.active_name===LOGIN&&r?.login_safe===true&&r?.role_safe===true&&r?.other_memberships===0&&
  r?.private_usage===false&&r?.app_usage===false&&r?.public_create===false&&r?.database_create===false);
 await tx.query('SET LOCAL ROLE collect_sms_runtime');
 await tx.query("SELECT pg_catalog.set_config('collect.sms_verified','true',true)");
 const roles=await tx.query(VERIFY_ROLE);const a=roles?.[0];
 need(roles?.length===1&&a?.active_name===ROLE&&a?.verified==='true'&&a?.sms_usage===true&&a?.sms_create===false&&a?.app_usage===false&&a?.private_usage===false);
}
export async function rollbackAndRelease(tx:Transaction){await tx.query('ROLLBACK');tx.release();}
// A failed/unknown COMMIT is never followed by a second COMMIT or a retry. A
// transaction whose outcome is unknown is quarantined rather than recycled.
export async function transact<T>(pool:Pool,body:(tx:Transaction)=>Promise<T>):Promise<T>{
 const tx=await reserve(pool);let commitSent=false;
 try{await enter(tx);const result=await body(tx);commitSent=true;await tx.query('COMMIT');tx.release();return result;}
 catch(error){if(!commitSent)try{await rollbackAndRelease(tx);}catch{/* quarantine */}throw error;}
}
