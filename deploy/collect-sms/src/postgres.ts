import postgres from 'npm:postgres@3.4.7';
import {applicationWorkTuple,fenceFailure,reserveDatabaseConnection} from '../../../supabase/functions/_shared/application-fence.js';
import {smsRuntimeRole} from './fence.ts';

// Internal server SQL only. No route accepts a query or database credential.
// These compatibility types preserve the inspected OpenSMS module contract;
// all durable state is PostgreSQL in the private collect_sms schema.
export interface D1Result<T=Record<string,unknown>> {success: true;results: T[];meta:{changes:number};}
export interface D1PreparedStatement {
 bind(...values: unknown[]): D1PreparedStatement;
 all<T=Record<string,unknown>>(): Promise<D1Result<T>>;
 first<T=Record<string,unknown>>(column?: string): Promise<T|null>;
 run(): Promise<D1Result>;
}
export interface D1Database {prepare(query:string):D1PreparedStatement;batch<T=Record<string,unknown>>(statements:D1PreparedStatement[]):Promise<D1Result<T>[]>;}

export function compileGatewaySql(input:string, values:unknown[]){
 let text='',count=0;
 for(let i=0;i<input.length;i++){
  const c=input[i];
  if(c==='\''||c==='"'){
   const quote=c;text+=c;let closed=false;
   while(++i<input.length){text+=input[i];if(input[i]===quote){if(input[i+1]===quote){text+=input[++i];}else{closed=true;break;}}}
   if(!closed)throw Error('gateway_sql_literal');
  }else if(c==='?')text+='$'+(++count);else text+=c;
 }
 if(count!==values.length||text.includes(';'))throw Error('gateway_sql_shape');
 // SQLite IS is null-safe equality. PostgreSQL also needs an explicit type
 // for standalone nullable parameters in CASE, before it sees other copies.
 text=text.replace(/(\$\d+) IS fcm_token/g,'$1 IS NOT DISTINCT FROM fcm_token')
  .replace(/application_id IS (\$\d+)/g,'application_id IS NOT DISTINCT FROM $1')
  .replace(/(\$\d+) IS NULL/g,'$1::text IS NULL');
 return {text,values:values.map(value=>value===undefined?null:value)};
}

class Statement implements D1PreparedStatement {
 constructor(readonly database:GatewayDatabase,readonly query:string,readonly values:unknown[]=[]){ }
 bind(...values:unknown[]){return new Statement(this.database,this.query,values);}
 async all<T=Record<string,unknown>>():Promise<D1Result<T>>{return (await this.database.batch<T>([this]))[0];}
 async first<T=Record<string,unknown>>(column?:string):Promise<T|null>{const row=(await this.all<Record<string,unknown>>()).results[0];return (row?(column===undefined?row:row[column]):null) as T|null;}
 run():Promise<D1Result>{return this.all();}
}

export class GatewayDatabase implements D1Database {
 constructor(readonly sql: ReturnType<typeof postgres>,private readonly work:any=null,private readonly capacity={waiting:0}){ }
 withApplicationWork(work:any){applicationWorkTuple(work);return new GatewayDatabase(this.sql,work,this.capacity);}
 prepare(query:string){if(typeof query!=='string'||query.length>100000)throw Error('gateway_sql_shape');return new Statement(this,query);}
 async batch<T=Record<string,unknown>>(statements:D1PreparedStatement[]):Promise<D1Result<T>[]>{
  if(!statements.length||statements.length>1000||this.capacity.waiting>=16)throw Error('gateway_database_busy');
  const work=this.work;if(!work)throw fenceFailure(null);
  // Refuse a departed context before creating a promise that cannot be owned
  // by the already-closed work journal.
  work.assertLocal();
  const prepared=statements.map(statement=>{
   if(!(statement instanceof Statement)||statement.database!==this)throw Error('gateway_statement_owner');
   return compileGatewaySql(statement.query,statement.values);
  });
  this.capacity.waiting++;
  try{return await work.waitUntil((async()=>{
   await work.assert();const tuple=applicationWorkTuple(work),tx=await reserveDatabaseConnection(this.sql);let idleConfirmed=false;
   try{
    await tx.unsafe('BEGIN ISOLATION LEVEL READ COMMITTED');await smsRuntimeRole(tx);
    await tx.unsafe('SET LOCAL search_path=collect_sms,pg_catalog');
    await tx.unsafe("SET LOCAL statement_timeout='8s'");await tx.unsafe("SET LOCAL lock_timeout='5s'");
    await tx.unsafe("SELECT set_config('collect.fence_admission_id',$1,true),set_config('collect.fence_epoch',$2,true),set_config('collect.fence_source_sha256',$3,true)",[tuple[0],String(tuple[1]),tuple[2]]);
    const proof=(await tx.unsafe('SELECT collect_sms.work_assert_write($1::uuid,$2::bigint,$3::text) AS result',tuple))[0]?.result;
    if(proof?.contractVersion!==1||proof.epoch!==tuple[1]||!['open','quiescing'].includes(proof.mode))throw fenceFailure(null);
    // All reads and read/modify batches participate in the same source/epoch
    // lease. The independent serial writer lock grants no fence authority.
    await tx.unsafe('SELECT pg_advisory_xact_lock(721340019927::bigint)');
    const result:D1Result<T>[]=[];
    for(const statement of prepared){
     const rows=await tx.unsafe(statement.text,statement.values as never[]);
     result.push({success:true,results:[...rows] as T[],meta:{changes:rows.count??0}});
    }
    await tx.unsafe('COMMIT');idleConfirmed=true;return result;
   }catch(error){try{await tx.unsafe('ROLLBACK');idleConfirmed=true;}catch{work.abandon('work_lost');}throw error;}
   finally{if(idleConfirmed)tx.release();}
  })()) as D1Result<T>[];}finally{this.capacity.waiting--;}
 }
}

export function gatewayConnection(url:string,env:Record<string,string|undefined>={}){
 const target=new URL(url),local=['localhost','127.0.0.1','[::1]'].includes(target.hostname);
 if(!['postgres:','postgresql:'].includes(target.protocol)||!target.username||!target.pathname.slice(1))throw Error('gateway_database_configuration');
 const ca=env.COLLECT_DB_CA_PEM;
 if(ca!==undefined&&(!ca.startsWith('-----BEGIN CERTIFICATE-----\n')||ca.length>32768))throw Error('gateway_database_ca');
 if(local&&env.COLLECT_SMS_FIXTURE!=='true')throw Error('gateway_fixture_required');
 return postgres(url,{max:4,prepare:false,connect_timeout:10,idle_timeout:20,
  ssl:local?false:{rejectUnauthorized:true,servername:target.hostname,...(ca?{ca}:{})},
  types:{bigint:{to:20,from:[20],serialize:String,parse:(value:string)=>{const n=Number(value);if(!Number.isSafeInteger(n))throw Error('gateway_integer_range');return n;}}},onnotice:()=>{}});
}
