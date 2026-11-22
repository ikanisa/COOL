/** TEST ONLY. Actual route, native pairing closure, legacy canonical statements
 * and AES over reduced SQLite. PostgreSQL/RLS/fence/classifier function are
 * explicit doubles; no live DB, provider, physical phone or real secret. */
import {gatewayFixture,I,OLD} from './collect-gateway-fixture.mjs';
import {GATEWAY_CLASSIFICATION_SQL} from '../../domain/burimunsi/postgres-gateway-classification.js';
import {momoGatewayRoute} from '../../domain/momo_gateway.js';
export {I,OLD};
export async function routingFixture(){
 const f=await gatewayFixture(),s=f.sqlite;
 s.exec(`ALTER TABLE app.momo_receiving_accounts ADD COLUMN receiver_hash TEXT;
 CREATE TABLE app.admin_users(id TEXT PRIMARY KEY,status TEXT);
 CREATE TABLE app.admin_principal_links(user_id TEXT,admin_user_id TEXT);`);
 f.execute('INSERT INTO app.admin_users VALUES(?,?)','synthetic-admin','active');
 f.execute('INSERT INTO app.admin_principal_links VALUES(?,?)',I.principal,'synthetic-admin');
 f.execute('INSERT INTO app.momo_receiving_accounts(id,provider,public_code,recipient_name,currency,timezone,status) VALUES(?,?,?,?,?,?,?)',
  'another-wallet','mtn_momo','000000','SYNTHETIC OTHER WALLET','RWF','Africa/Kigali','active');
 s.function('unixepoch',()=>Math.floor(I.now/1000));
 const route={reads:[],batches:[],classifications:0,classifierError:false,beforeBatch:null,loseClaimAck:false};
 const classify=hash=>{
  route.classifications++;if(route.classifierError)throw Error('PRIVATE classifier or SQL helper failure');
  const p=s.prepare(`SELECT p.binding_id,b.receiving_account_id FROM app.momo_gateway_pairings p
   JOIN app.momo_gateway_bindings b ON b.id=p.binding_id WHERE p.code_sha256=?`).get(hash);
  if(!p)return {kind:'blocked'};
  const scopes=s.prepare('SELECT * FROM private.burimunsi_scopes WHERE active_binding_id=? OR receiving_account_id=?').all(p.binding_id,p.receiving_account_id);
  const exact=scopes.filter(scope=>scope.active_binding_id===p.binding_id);
  return exact.length===1?{kind:'burimunsi',collectionId:exact[0].collection_id}:scopes.length?{kind:'blocked'}:{kind:'non_burimunsi'};
 };
 s.function('synthetic_gateway_classification',hash=>JSON.stringify(classify(hash)));
 f.db.prepare=sql=>({bind:(...values)=>({sql,values,first:async()=>{
  route.reads.push({sql,values});return s.prepare(sql).get(...values)??null;
 }})});
 const statement=f.db.statement;
 f.db.statement=async(sql,st)=>{
  if(st.sql===GATEWAY_CLASSIFICATION_SQL)return {success:true,results:[{classification:classify(st.values[0])}],meta:{changes:1}};
  const translated={...st,sql:st.sql.replaceAll('private.burimunsi_gateway_pair_classify(?)','synthetic_gateway_classification(?)').replaceAll('::jsonb','')};
  return statement(sql,translated);
 };
 f.db.batch=async statements=>{
  route.batches.push(statements);await route.beforeBatch?.(statements);
  const result=await f.db.transaction(async sql=>{
   await f.db.applicationWork.assert();await f.db.context(sql);await sql.unsafe('SELECT pg_advisory_xact_lock(734636924058501::bigint)');
   const out=[];for(const st of statements)out.push(await f.db.statement(sql,st));await f.db.applicationWork.assert();return out;
  });
  if(route.loseClaimAck&&statements.some(st=>st.sql.startsWith('INSERT INTO momo_gateway_credentials'))){
   route.loseClaimAck=false;throw Error('PRIVATE lost legacy COMMIT acknowledgement');
  }
  return result;
 };
 Object.assign(f.env,{BURIMUNSI_NATIVE_ENABLED:'true',BURIMUNSI_COLLECTION_ID:I.group});
 const attach=()=>f.execute('UPDATE private.burimunsi_scopes SET active_binding_id=?,receiving_account_id=?,binding_version=3',OLD,'wallet-1');
 const detach=()=>f.execute('UPDATE private.burimunsi_scopes SET active_binding_id=NULL,receiving_account_id=?','another-wallet');
 return Object.assign(f,{route,attach,detach,request:(overrides={})=>new Request('https://qualification.invalid/v1/momo/gateway/pair',{
  method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({pairing_code:f.code,installation_id:I.installation,...overrides})}),
  invoke:overrides=>momoGatewayRoute(new Request('https://qualification.invalid/v1/momo/gateway/pair',{
   method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({pairing_code:f.code,installation_id:I.installation,...overrides})}),f.env)});
}
