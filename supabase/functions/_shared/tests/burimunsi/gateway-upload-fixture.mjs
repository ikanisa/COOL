/** TEST ONLY: actual route, AES and exported authority/guard/source SQL on
 * reduced SQLite. PostgreSQL fence/RLS/operator helper/association trigger and
 * protected object storage are explicit doubles; actual PG contract is separate. */
import {routingFixture,I,OLD} from './gateway-routing-fixture.mjs';
import {momoGatewayRoute} from '../../domain/momo_gateway.js';
import {GATEWAY_CLASSIFICATION_SQL} from '../../domain/burimunsi/postgres-gateway-classification.js';
export {I,OLD};
export const SMS='You have received 1,000 RWF from EXAMPLE PAYER (*****001) at 2026-11-07 12:00:00. Balance: 2,000 RWF. FT Id: 123456789.';
export async function uploadFixture(){
 const f=await routingFixture(),s=f.sqlite;
 s.exec(`ALTER TABLE app.momo_receiving_accounts ADD COLUMN profile_status TEXT DEFAULT 'approved';
 ALTER TABLE app.momo_receiving_accounts ADD COLUMN profile_version TEXT DEFAULT 'fixture-approved-v1';
 ALTER TABLE app.momo_receiving_accounts ADD COLUMN profile_json TEXT;
 CREATE TABLE app.sms_receipts(id TEXT PRIMARY KEY,owner_user_id TEXT,originating_session_id TEXT,client_envelope_id TEXT,
 body_sha256 TEXT,receiver_hash TEXT,object_key TEXT,object_sha256 TEXT,size_bytes INTEGER,received_at_device TEXT,created_at TEXT,UNIQUE(owner_user_id,client_envelope_id));
 CREATE TABLE app.momo_processing_jobs(raw_sms_id TEXT UNIQUE,binding_id TEXT,binding_version INTEGER,receiving_account_id TEXT,mode TEXT,state TEXT,available_at INTEGER,created_at TEXT,updated_at TEXT);
 ALTER TABLE app.momo_gateway_captures ADD COLUMN identity_sha256 TEXT;
 ALTER TABLE app.momo_gateway_captures ADD COLUMN service_centre_at TEXT;
 ALTER TABLE app.momo_gateway_captures ADD COLUMN captured_at TEXT;
 ALTER TABLE app.momo_gateway_captures ADD COLUMN inbox_received_at TEXT;
 ALTER TABLE app.momo_gateway_captures ADD COLUMN subscription_id INTEGER;
 ALTER TABLE app.momo_gateway_captures ADD COLUMN completeness TEXT;
 ALTER TABLE app.momo_gateway_captures ADD COLUMN source_mode TEXT;
 CREATE UNIQUE INDEX app.upload_fixture_capture_unique ON momo_gateway_captures(raw_sms_id);
 CREATE TABLE private.burimunsi_sms_source_scopes(source_id TEXT PRIMARY KEY,collection_id TEXT,receiving_account_id TEXT,owner_user_id TEXT,
 source_body_sha256 TEXT,object_sha256 TEXT,binding_id TEXT,binding_version INTEGER,credential_id TEXT,installation_id TEXT,
 custodian_account_id TEXT,grant_id TEXT,grant_version INTEGER,provenance TEXT,proof_id TEXT);`);
 const profile={sender_allowlist:['M-Money'],currency_aliases:['RWF'],incoming_prefixes:['You have received'],transaction_id_prefixes:['FT Id:'],date_format:'YMD_HMS',utc_offset_minutes:120};
 f.execute('UPDATE app.momo_receiving_accounts SET profile_json=?,receiver_hash=?',JSON.stringify(profile),'c'.repeat(64));
 const paired=await(await f.invoke()).json(),secret=paired.gateway_token;
 const state={puts:0,gets:0,objects:new Map(),associate:true,onPut:null,onCaptureCommit:null,offline:false,loseCaptureCommit:false,failCapture:false,readOnlyReconciliations:0};
 const prior=f.db.statement;
 f.db.statement=async(tx,st)=>{
  if(st.sql===GATEWAY_CLASSIFICATION_SQL)return prior(tx,st);
  if(st.sql.startsWith('SELECT set_config'))return {success:true,results:[],meta:{changes:0}};
  if(state.failCapture&&st.sql.startsWith('INSERT INTO sms_receipts'))throw Error('PRIVATE synthetic rolled-back capture');
  let sql=st.sql.replaceAll('private.burimunsi_operator_is_current(','fixture_upload_operator(');
  const query=s.prepare(sql);
  if(/^SELECT\b/.test(sql)){
   const rows=query.all(...st.values).map(row=>{const r={...row};for(const key of ['associated','admitted'])if(key in r)r[key]=Boolean(r[key]);return r;});
   if(sql.includes('FROM app.sms_receipts r')){if(f.state.readOnly)state.readOnlyReconciliations++;else throw Error('Capture lookup must be read-only');}
   return {success:true,results:rows,meta:{changes:rows.length}};
  }
  const result=query.run(...st.values);
  if(state.associate&&sql.startsWith('INSERT INTO momo_gateway_captures')){
   // SQL27 trigger model: this is part of the SAME SQLite capture transaction.
   s.prepare(`INSERT INTO private.burimunsi_sms_source_scopes
    SELECT r.id,scope.collection_id,b.receiving_account_id,b.owner_user_id,r.body_sha256,r.object_sha256,
    b.id,b.version,c.id,c.installation_id,d.custodian_account_id,d.id,d.version,'gateway_capture',r.id
    FROM app.sms_receipts r JOIN app.momo_gateway_credentials c ON c.id=?
    JOIN app.momo_gateway_bindings b ON b.id=c.binding_id
    JOIN private.burimunsi_scopes scope ON scope.active_binding_id=b.id
    JOIN private.burimunsi_device_grants d ON d.collection_id=scope.collection_id AND d.installation_id=c.installation_id
    WHERE r.id=? AND d.active AND scope.enabled`).run(st.values[1],st.values[0]);
  }
  return {success:true,results:[],meta:{changes:Number(result.changes)}};
 };
 s.function('fixture_upload_operator',(_group,_principal,_phone,_role,_capabilities)=>Number(f.h.operatorApproved));
 const batch=f.db.batch;
 f.db.batch=async statements=>{
  const result=await batch(statements);
  if(statements.some(st=>st.sql.startsWith('INSERT INTO sms_receipts')))await state.onCaptureCommit?.();
  if(state.loseCaptureCommit&&statements.some(st=>st.sql.startsWith('INSERT INTO sms_receipts'))){
   state.loseCaptureCommit=false;throw Error('PRIVATE synthetic lost capture COMMIT');
  }
  return result;
 };
 const media={async put(key,value,options){
  state.puts++;if(state.offline)throw Error('PRIVATE synthetic storage offline');
  await state.onPut?.();if(!state.objects.has(key))state.objects.set(key,{value,options});
 },async get(key){state.gets++;const object=state.objects.get(key);return object?{text:async()=>object.value}:null;}};
 Object.assign(f.env,{BURIMUNSI_NATIVE_UPLOADS_ENABLED:'true',COLLECT_FENCE_WORK:f.db.applicationWork,PRIVATE_MEDIA:media});
 const body={client_envelope_id:I.request,gateway_binding_id:OLD,gateway_binding_version:3,raw_sender:'M-Money',raw_body:SMS,
  captured_at:new Date(I.now+1000).toISOString(),service_centre_at:null,inbox_received_at:new Date(I.now+1000).toISOString(),source_mode:'live',complete:true,subscription_id:1};
 const request=(changes={})=>new Request('https://qualification.invalid/v1/momo/gateway/ingest',{
  method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+secret,'X-BuriMunsi-Collection-Id':'attacker-group'},body:JSON.stringify({...body,...changes})});
 return Object.assign(f,{upload:state,body,secret,request,invokeUpload:changes=>momoGatewayRoute(request(changes),f.env),
  sources:()=>s.prepare('SELECT * FROM private.burimunsi_sms_source_scopes').all()});
}
