import postgres from 'npm:postgres@3.4.7';
import {AccessDenied,lockReceiptPrincipal,validateReceiptWrite,type ReceiptAccess} from './access.ts';
import {applicationWorkTuple,fenceFailure} from '../../../supabase/functions/_shared/application-fence.js';
import {compileGatewaySql} from '../../collect-sms/src/postgres.ts';
import {ApiError} from '../../collect-sms/src/util.ts';
import {bound,enter,reserve,rollbackAndRelease,type Pool} from './transactions.ts';
const confirmedRollback=new WeakSet<object>();
const confirmedDenial=new WeakSet<object>();
/** Only errors created after this adapter has acknowledged rollback qualify. */
export function isConfirmedAccessDenied(error:unknown):boolean{return !!error&&typeof error==='object'&&confirmedDenial.has(error);}
const knownConstraint=(error:unknown)=>error instanceof postgres.PostgresError&&/^(?:22|23)[0-9A-Z]{3}$/.test((error as any).code??'');
class Statement {
 constructor(readonly database:ManagedGatewayDatabase,readonly query:string,readonly values:unknown[]=[]){ }
 bind(...values:unknown[]){return new Statement(this.database,this.query,values);}
 async all(){return (await this.database.batch([this]))[0];}
 async first(column?:string){const row=(await this.all()).results[0];return row?(column===undefined?row:row[column]):null;}
 run(){return this.all();}
}
export class ManagedGatewayDatabase {
 constructor(readonly pool:Pool,private readonly work:any=null,private readonly capacity={waiting:0},private readonly access:ReceiptAccess|null=null){}
 withApplicationWork(work:any,access:ReceiptAccess){applicationWorkTuple(work);if(!access)throw new AccessDenied();return new ManagedGatewayDatabase(this.pool,work,this.capacity,{...access});}
 prepare(query:string){if(typeof query!=='string'||query.length>100000)throw Error('gateway_sql_shape');return new Statement(this,query);}
 async batch(statements:Statement[]){
  if(!statements.length||statements.length>1000||this.capacity.waiting>=16)throw Error('gateway_database_busy');
  const work=this.work,access=this.access;if(!work||!access)throw fenceFailure(null);work.assertLocal();
  const queries=statements.map(s=>{if(!(s instanceof Statement)||s.database!==this)throw Error('gateway_statement_owner');return compileGatewaySql(s.query,s.values);});
  this.capacity.waiting++;
  try{const pending=work.waitUntil((async()=>{
   await work.assert();const tuple=applicationWorkTuple(work),tx=await reserve(this.pool);let commitSent=false,businessStarted=false;
   try{
    await enter(tx);await tx.query('SET LOCAL search_path=pg_catalog,collect_sms');
    await tx.query("SELECT pg_catalog.set_config('collect.fence_admission_id',$1,true),pg_catalog.set_config('collect.fence_epoch',$2,true),pg_catalog.set_config('collect.fence_source_sha256',$3,true)",[tuple[0],String(tuple[1]),tuple[2]]);
    const rows=await tx.query('SELECT collect_sms.work_assert_write($1::uuid,$2::bigint,$3::text) AS result',tuple),proof=rows?.[0]?.result;
    if(rows?.length!==1||proof?.contractVersion!==1||proof.epoch!==tuple[1]||!['open','quiescing'].includes(proof.mode))throw fenceFailure(null);
    await tx.query('SELECT pg_catalog.pg_advisory_xact_lock(721340019927::bigint)');
    const principal=await lockReceiptPrincipal(tx,access);
    const results=[];for(const query of queries){validateReceiptWrite(query.text,query.values,principal);businessStarted=true;const rows=await tx.query(query.text,query.values);results.push({success:true,results:[...rows],meta:{changes:rows.count??0}});}
    commitSent=true;await tx.query('COMMIT');tx.release();return results;
   }catch(error){
    // Only an acknowledged rollback of an access denial or a server-proven
    // deterministic data/constraint error is a confirmed no-commit outcome.
    let safe=false;if(!commitSent)try{await rollbackAndRelease(tx);safe=error instanceof AccessDenied||(businessStarted&&knownConstraint(error));}catch{/* quarantine */}
    if(safe&&error instanceof AccessDenied){
     // The shared gateway converts ApiError to an HTTP response. Do this only
     // after rollback is confirmed; an unconfirmed denial must remain a 503.
     const denial=new ApiError(404,'not_found','Resource not found');
     confirmedRollback.add(denial);confirmedDenial.add(denial);throw denial;
    }
    if(safe&&error&&typeof error==='object')confirmedRollback.add(error);else work.abandon('work_lost');
    throw error;
   }
  })());try{return await bound<any[]>(pending,12000);}catch(error){if(!error||typeof error!=='object'||!confirmedRollback.has(error))try{work.abandon('work_lost');}catch{}throw error;}}finally{this.capacity.waiting--;}
 }
}
