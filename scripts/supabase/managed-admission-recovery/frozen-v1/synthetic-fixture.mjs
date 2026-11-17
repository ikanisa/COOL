// This fixture owns a new socket-only PG17 process and has no managed/cloud
// connection option, provider client, database URL, or production write path.
import {createHash,randomUUID} from 'node:crypto';
import {lstat,readFile,realpath} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import pg from '../node_modules/pg/lib/index.js';
import {startOwnedPg17} from '../current-pg-transfer/test-support/owned-pg17.mjs';

const BIN='/Volumes/PRO-G40/Development/Supabase/Qwen-Validation/cache/stack/slim-services/postgres/17.11.0.004-r1/darwin-arm64/bin';
const BIN_PINS=Object.freeze({
 initdb:'1a53edc7a433f9cc789b968d97ef8bd99fd12377dca09022b578558844720d82',
 postgres:'9058a8740787c17c4736be5945369bd9ddeff189743a3ce1032383d23a1e356c',
 pg_ctl:'8a2bada4e252f1ff2ed4b0bea33246608b85b6711e29926e8b5c90a016a384a1',
 pg_isready:'b70711c575b302ebdc117ccf0e57751a2e250cfa8e763f18e88931479b575e25',
});
const SQL_SHA='f39d2c2495a752459cb8e9eaa66e115835a1060976143778911ae759bb0152fb';
const CLUSTER='collect_admission_recovery_synthetic_only';
const SOURCE='a'.repeat(64);
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const fail=code=>{const e=new Error(code);e.code=code;throw e;};
const need=(condition,code)=>{if(!condition)fail(code);};

export function assertSyntheticEnvironment(env){
 need(env&&typeof env==='object','SYNTHETIC_ENVIRONMENT_REQUIRED');
 for(const [key,value] of Object.entries(env))if(value&&(/^(?:PG[A-Z_0-9]*|SUPABASE_.*|DATABASE_URL|POSTGRES_URL)$/i.test(key)))fail('MANAGED_OR_EXTERNAL_CONNECTION_REFUSED');
 need(!env.COLLECT_SYNTHETIC_PG_BIN||env.COLLECT_SYNTHETIC_PG_BIN===BIN,'SYNTHETIC_BINARY_REQUIRED');
}
async function verifyBinaryPins(){
 need(await realpath(BIN)===BIN,'SYNTHETIC_BINARY_REQUIRED');
 for(const [name,pin] of Object.entries(BIN_PINS)){
  const path=join(BIN,name),s=await lstat(path);need(s.isFile()&&!s.isSymbolicLink()&&await realpath(path)===path&&s.size<=128*1024*1024,'SYNTHETIC_BINARY_REQUIRED');
  need(sha(await readFile(path))===pin,'SYNTHETIC_BINARY_CHANGED');
 }
}
export async function createSyntheticAdmissionFixture(...args){
 need(args.length===0,'SYNTHETIC_ONLY_REFUSAL');assertSyntheticEnvironment(process.env);
 const sql=await readFile(new URL('./synthetic-model.sql',import.meta.url),'utf8');need(sha(Buffer.from(sql))===SQL_SHA,'SYNTHETIC_SOURCE_CHANGED');
 await verifyBinaryPins();const cluster=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:CLUSTER});
 const dbName='collect_admission_'+randomUUID().replaceAll('-','')+'_test',clients=[];let startedAt;
 const connect=async(user='fixture_bootstrap',database=dbName)=>{
  need(['fixture_bootstrap','synthetic_admission_actor_one','synthetic_admission_actor_two'].includes(user),'SYNTHETIC_IDENTITY_REQUIRED');
  need(database==='postgres'||database===dbName,'SYNTHETIC_DATABASE_REQUIRED');
  const client=new pg.Client({host:cluster.socket,port:cluster.port,database,user,ssl:false,connectionTimeoutMillis:3000});
  client.on('error',()=>{});await client.connect();clients.push(client);
  const dataSetting=user==='fixture_bootstrap'?"current_setting('data_directory')":"NULL::text";
  const socketSetting=user==='fixture_bootstrap'?"current_setting('unix_socket_directories')":"NULL::text";
  const listenSetting=user==='fixture_bootstrap'?"current_setting('listen_addresses')":"NULL::text";
  const clusterSetting=user==='fixture_bootstrap'?"current_setting('cluster_name')":"NULL::text";
  const r=(await client.query(`SELECT current_database() AS database,session_user AS username,inet_server_addr() AS server_address,
   inet_client_addr() AS client_address,${dataSetting} AS data,${socketSetting} AS socket,${listenSetting} AS listen,${clusterSetting} AS cluster,
   pg_postmaster_start_time()::text AS started,current_setting('server_version_num') AS version`)).rows[0];
  if(startedAt===undefined)startedAt=r.started;
  need(r.database===database&&r.username===user&&r.server_address===null&&r.client_address===null&&r.started===startedAt&&
   (user!=='fixture_bootstrap'||r.data===cluster.data&&r.socket===cluster.socket&&r.listen===''&&r.cluster===CLUSTER)&&
   /^17[0-9]{4}$/.test(r.version),'SYNTHETIC_DATABASE_IDENTITY_REFUSED');
  await client.query('SET statement_timeout=5000');return client;
 };
 let closing;
 const close=()=>closing??=(async()=>{
  const ended=await Promise.allSettled(clients.map(c=>c.end())),outcome=await cluster.close();
  need(ended.every(x=>x.status==='fulfilled')&&outcome.removed===true,'SYNTHETIC_CLEANUP_UNCONFIRMED');return outcome;
 })();
 try{
  const admin=await connect('fixture_bootstrap','postgres');
  need(/^collect_admission_[0-9a-f]{32}_test$/.test(dbName),'SYNTHETIC_DATABASE_REQUIRED');
  await admin.query('CREATE DATABASE "'+dbName+'" TEMPLATE template0');
  const db=await connect();await db.query(sql);
  await db.query('INSERT INTO admission_fixture.control(singleton,mode,epoch,source_sha256) VALUES(true,$1,$2,$3)',['open',13,SOURCE]);
  need(sha(Buffer.from(await readFile(new URL('./synthetic-model.sql',import.meta.url),'utf8')))===SQL_SHA,'SYNTHETIC_SOURCE_CHANGED');
  return Object.freeze({admin,db,connect:()=>connect(),actorOne:()=>connect('synthetic_admission_actor_one'),
   actorTwo:()=>connect('synthetic_admission_actor_two'),sql,source:SOURCE,epoch:13,providerCalls:0,close});
 }catch(error){await close();throw error;}
}
// Explicit public entry for callers that might otherwise try to supply a real
// target. This candidate intentionally has no path to open such a connection.
export function executeManagedAdmissionRecovery(){fail('MANAGED_OR_REAL_EXECUTION_REFUSED');}
