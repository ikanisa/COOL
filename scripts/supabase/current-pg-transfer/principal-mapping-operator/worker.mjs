// Fresh worker: only a clean pipe input, private memory, bounded connections,
// and aggregate output. Managed dispatch is closed by protocol.mjs.
import pg from '../../node_modules/pg/lib/index.js';
import {observePrincipalMapping} from '../principal-mapping-preflight/preflight.mjs';
import {cleanEnvironment,validateEnvelope,targetConfig,sanitizeObservation} from './protocol.mjs';
import {readPrivateInput} from './input.mjs';
const {Client}=pg;
const safe=new Set(['input_refused','plan_refused','managed_preimage_unavailable','source_identity_refused','connection_refused','preflight_refused','result_refused']);
const fail=x=>{throw Object.assign(Error(x),{safeCode:x});};
let source,target,ending=false;
function destroy(){if(ending)return;ending=true;for(const c of [source,target])try{c?.connection?.stream?.destroy();}catch{}}
process.once('SIGTERM',()=>{destroy();process.exit(143);});process.once('SIGINT',()=>{destroy();process.exit(130);});
try{
 if(process.argv.length!==3||!cleanEnvironment())fail('input_refused');
 const envelope=await readPrivateInput(),{plan,mode}=validateEnvelope(envelope,process.argv[2]),f=plan.preflight;
 const timeout=Math.min(5000,Math.max(250,plan.deadlineMs-250));
 const sourceConfig={host:f.source.host,port:f.source.port,database:f.source.database,user:f.source.session_user,password:envelope.sourcePassword,ssl:false,connectionTimeoutMillis:timeout,application_name:'collect_principal_preflight'};
 source=new Client(sourceConfig);source.on('error',()=>{});
 try{await source.connect();}catch{fail('connection_refused');}
 const stream=source.connection.stream,pid=source.processID;
 let identity;try{await source.query('BEGIN ISOLATION LEVEL READ COMMITTED READ ONLY');identity=(await source.query({text:`SELECT system_identifier::text AS system_identifier,
  to_char(pg_postmaster_start_time() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS started,
  current_setting('server_version_num') AS version,pg_backend_pid()::text AS pid,
  inet_server_addr() IS NULL AS unix_socket FROM pg_catalog.pg_control_system()`,values:[]})).rows;await source.query('ROLLBACK');}catch{try{await source.query('ROLLBACK');}catch{}fail('source_identity_refused');}
 if(identity.length!==1||identity[0].system_identifier!==plan.sourceIdentity.systemIdentifier||identity[0].started!==plan.sourceIdentity.postmasterStartedAt||
  identity[0].version!==plan.sourceIdentity.serverVersion||identity[0].pid!==String(pid)||identity[0].unix_socket!==true||source.connection.stream!==stream)fail('source_identity_refused');
 const targetOptions=mode==='managed'?targetConfig(f.target,envelope.targetPassword,timeout):{host:f.target.host,port:f.target.port,database:f.target.database,user:f.target.session_user,password:envelope.targetPassword,ssl:false,connectionTimeoutMillis:timeout,application_name:'collect_principal_preflight'};
 target=new Client(targetOptions);target.on('error',()=>{});try{await target.connect();}catch{fail('connection_refused');}
 let result;try{result=await observePrincipalMapping({sourceClient:source,targetClient:target,plan:f,expectedPlanSha256:plan.preflightSha256});}catch{fail('preflight_refused');}
 const output=sanitizeObservation(result,plan);process.stdout.write(JSON.stringify(output)+'\n');
}catch(e){const reason=safe.has(e?.safeCode)?e.safeCode:'input_refused';process.stdout.write(JSON.stringify({status:'refused',reason,write_authorized:false})+'\n');process.exitCode=1;}
finally{destroy();for(const c of [source,target])try{await c?.end();}catch{}}
