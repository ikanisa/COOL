/** TEST ONLY: real adapter/native auth/canonical statements over reduced SQLite.
 * PostgreSQL locks, managed-owner/email proof functions, roles and the fence are
 * explicit doubles. No provider, real account, credential or live DB is used. */
import {principalFixture,I} from './native-principal-fixture.mjs';
import {installCanonicalHarness} from './posting-authority-fixture.mjs';
import {PostgresCollectGateway,GATEWAY_READ_PERMISSION_SQL,CANONICAL_PAIR_SQL,PAIR_TARGET_SQL,createCanonicalGatewayPair} from '../../domain/burimunsi/postgres-collect-gateway.js';
import {GatewayRegistry} from '../../domain/burimunsi/gateway-registry.js';
import {sha256} from '../../domain/burimunsi/values.js';
export {I};
export const OLD='20000000-0000-4000-8000-000000000001',TARGET='20000000-0000-4000-8000-000000000002',PAIR='20000000-0000-4000-8000-000000000003';
export async function gatewayFixture(){
 const f=principalFixture(),h=installCanonicalHarness(f);h.sharedRole='admin';h.permissions=new Set(['receivers.read','receivers.manage']);
 h.emailFresh=true;h.ownerLive=true;h.installationApproved=true;
 const s=f.sqlite,stamp=new Date(I.now).toISOString();
 s.exec(`ALTER TABLE private.burimunsi_scopes ADD COLUMN receiving_account_id TEXT;
  ALTER TABLE private.burimunsi_scopes ADD COLUMN active_binding_id TEXT;
  ALTER TABLE private.burimunsi_scopes ADD COLUMN binding_version INTEGER;
  ALTER TABLE private.burimunsi_scopes ADD COLUMN version INTEGER;
  ALTER TABLE private.burimunsi_device_grants ADD COLUMN custodian_account_id TEXT;
  CREATE TABLE app.momo_receiving_accounts(id TEXT PRIMARY KEY,provider TEXT,public_code TEXT,recipient_name TEXT,currency TEXT,timezone TEXT,status TEXT);
  CREATE TABLE app.momo_gateway_bindings(id TEXT PRIMARY KEY,owner_user_id TEXT,receiving_account_id TEXT,version INTEGER DEFAULT 1,status TEXT DEFAULT 'active',subscription_evidence TEXT,created_at TEXT,revoked_at TEXT);
  CREATE TABLE app.momo_gateway_pairings(id TEXT PRIMARY KEY,binding_id TEXT,code_sha256 TEXT UNIQUE,originating_session_id TEXT,expires_at INTEGER,claimed_installation_id TEXT,created_at TEXT);
  CREATE TABLE app.momo_gateway_credentials(id TEXT PRIMARY KEY,binding_id TEXT UNIQUE,pairing_id TEXT UNIQUE,installation_id TEXT,token_sha256 TEXT UNIQUE,token_ciphertext TEXT,last_contact_at TEXT,last_sms_at TEXT,pending_count INTEGER DEFAULT 0,oldest_pending_at TEXT,revoked_at TEXT,created_at TEXT);
  CREATE TABLE app.momo_gateway_captures(raw_sms_id TEXT,credential_id TEXT,created_at TEXT);
  CREATE TABLE app.momo_processing_guards(id TEXT PRIMARY KEY,passed INTEGER CHECK(passed=1));
  CREATE TABLE app.audit_log(id INTEGER PRIMARY KEY,actor_user_id TEXT,actor_session_id TEXT,action TEXT,entity_type TEXT,entity_id TEXT,request_id TEXT,details_json TEXT,created_at TEXT);
  CREATE TABLE private.burimunsi_command_receipts(collection_id TEXT,actor_id TEXT,request_id TEXT,session_id TEXT,operation TEXT,fingerprint TEXT,response TEXT,created_at INTEGER,UNIQUE(collection_id,actor_id,request_id));`);
 f.execute("UPDATE private.burimunsi_accounts SET role='admin',capabilities=?",JSON.stringify(['records.read','staff.manage','gateway.manage']));
 f.execute("UPDATE private.burimunsi_device_grants SET profile='internal_receiver',custodian_account_id=?",I.account);
 f.execute('INSERT INTO private.burimunsi_device_grants VALUES(?,?,?,?,?,?,?,?)','target-grant',I.group,TARGET,'e'.repeat(64),'internal_receiver',1,1,I.account);
 f.execute('INSERT INTO private.burimunsi_device_accounts VALUES(?,?,?)','target-grant',I.account,I.group);
 f.execute('INSERT INTO app.momo_receiving_accounts VALUES(?,?,?,?,?,?,?)','wallet-1','mtn_momo','008000','SYNTHETIC RECEIVER','RWF','Africa/Kigali','active');
 f.execute('INSERT INTO app.momo_gateway_bindings(id,owner_user_id,receiving_account_id,version,subscription_evidence,created_at) VALUES(?,?,?,?,?,?)',OLD,I.principal,'wallet-1',3,JSON.stringify({subscription_id:1}),stamp);
 f.execute('UPDATE private.burimunsi_scopes SET receiving_account_id=?,active_binding_id=?,binding_version=3,version=5','wallet-1',OLD);
 const code='f'.repeat(64);
 f.execute('INSERT INTO app.momo_gateway_pairings VALUES(?,?,?,?,?,?,?)',PAIR,OLD,await sha256(code),I.canonical,Math.floor(I.now/1000)+600,null,stamp);
 const originalSession=f.store.session.bind(f.store);
 f.store.session=async(...args)=>{const actor=await originalSession(...args);return actor?{...actor,principalSessionId:h.sessionId}:null;};
 const unsafe=f.sql.unsafe;
 f.sql.unsafe=async(text,values=[])=>{
  // Explicit pre33 unbound challenge fixture only. SQL33 target-bound codes
  // and their real native/legacy policy are covered by actual SQL qualification.
  if(text===PAIR_TARGET_SQL){f.state.queries.push({text,values});return [{allowed:true}];}
  if(text===GATEWAY_READ_PERMISSION_SQL){f.state.queries.push({text,values});return h.managed&&h.emailFresh&&h.allowed&&h.permissions.has('receivers.read')&&h.sharedRole!=='staff'?
   [{principal_user_id:values[0],principal_session_id:values[1],shared_role:h.sharedRole}]:[];}
  if(text===CANONICAL_PAIR_SQL){
   f.state.queries.push({text,values});
   if(!h.ownerLive||!h.managed||!h.emailFresh||!h.allowed||!h.installationApproved||!h.operatorApproved||!h.permissions.has('receivers.manage')||h.sharedRole==='staff')return [];
   return s.prepare(`SELECT p.*,b.owner_user_id,b.receiving_account_id,b.version AS binding_version,b.subscription_evidence,b.created_at AS binding_created_at,
    a.provider,a.public_code,a.recipient_name,a.currency,a.timezone FROM app.momo_gateway_pairings p
    JOIN app.momo_gateway_bindings b ON b.id=p.binding_id JOIN app.momo_receiving_accounts a ON a.id=b.receiving_account_id
    JOIN private.burimunsi_scopes scope ON scope.active_binding_id=b.id AND scope.receiving_account_id=b.receiving_account_id
    WHERE p.code_sha256=? AND scope.collection_id=? AND scope.enabled=1 AND scope.binding_version=b.version
     AND b.status='active' AND a.status='active' AND p.expires_at>?
     AND EXISTS(SELECT 1 FROM private.burimunsi_device_grants d JOIN private.burimunsi_accounts n ON n.id=d.custodian_account_id
       JOIN private.burimunsi_device_accounts da ON da.grant_id=d.id AND da.account_id=n.id AND da.collection_id=d.collection_id
       WHERE d.collection_id=scope.collection_id AND d.installation_id=? AND d.active=1 AND d.profile='internal_receiver'
        AND n.active=1 AND n.removed=0 AND n.role='admin' AND n.principal_user_id=b.owner_user_id)`).all(values[0],values[1],Math.floor(I.now/1000),values[2]).map(r=>({...r}));
  }
  if(text.startsWith('SELECT to_char(clock_timestamp()'))return [{at:stamp}];
  if(text==='SELECT pg_is_in_recovery() AS replica')return [{replica:false}];
  if(text.includes('private.burimunsi_operator_is_current')&&!h.operatorApproved)return [];
  const translated=text.replace(/ FOR UPDATE/g,'').replace(/ AND private\.burimunsi_operator_is_current\([^)]*\)/g,'');
  const rows=await unsafe(translated,values);
  return rows.map(row=>{const r={...row};if('enabled'in r)r.enabled=Boolean(r.enabled);if(typeof r.response==='string')r.response=JSON.parse(r.response);return r;});
 };
 const statement=f.db.statement;f.statements=[];f.failStatement=null;
 f.db.statement=async(sql,st)=>{
  f.statements.push(st);
  if(st.sql.startsWith('INSERT INTO app.mutation_guards')&&(!h.emailFresh||!h.permissions.has('receivers.manage')||h.sharedRole==='staff'))throw Error('synthetic shared permission/freshness denial');
  if(f.failStatement?.(st))throw Error('synthetic statement failure');return statement(sql,st);
 };
 const transaction=f.db.transaction;f.loseCommit=false;
 f.db.transaction=async fn=>{const value=await transaction(fn);if(f.loseCommit){f.loseCommit=false;throw Error('synthetic lost COMMIT acknowledgement');}return value;};
 const env={DB:f.db,DATA_KEY_ID:'synthetic-test-only',DATA_ENCRYPTION_KEY:Buffer.alloc(32,7).toString('base64')};
 const adapter=new PostgresCollectGateway({authority:f.store,env,clock:()=>I.now}),registry=new GatewayRegistry({store:adapter,groupId:I.group,clock:()=>I.now});
 const actor={id:I.account,sessionId:I.session};
 const command={replacementCode:code,requestId:I.request};
 return Object.assign(f,{h,env,adapter,registry,actor,command,code,pair:createCanonicalGatewayPair({env,groupId:I.group}),
  replace:()=>registry.replace(actor,copy(command)),
  seedCredential:()=>f.execute(`INSERT INTO app.momo_gateway_credentials(id,binding_id,pairing_id,installation_id,token_sha256,token_ciphertext,last_contact_at,last_sms_at,pending_count,oldest_pending_at,created_at)
   VALUES(?,?,?,?,?,?,?,?,?,?,?)`,'old-credential',OLD,PAIR,I.installation,'a'.repeat(64),'synthetic-not-decrypted',stamp,stamp,2,stamp,stamp),
  seedReplacementReceipt:response=>f.execute(`INSERT INTO private.burimunsi_command_receipts
   (collection_id,actor_id,request_id,session_id,operation,fingerprint,response,created_at) VALUES(?,?,?,?,?,?,?,?)`,
   I.group,I.account,I.request,I.session,'burimunsi.gateway.replace','b'.repeat(64),JSON.stringify(response),I.now),
  replacementSnapshot:()=>Object.fromEntries(['app.momo_gateway_bindings','app.momo_gateway_credentials',
   'app.momo_gateway_pairings','private.burimunsi_scopes','private.burimunsi_sessions',
   'private.burimunsi_command_receipts','app.audit_log'].map(table=>[table,s.prepare('SELECT * FROM '+table).all().map(row=>({...row}))])),
  count:table=>s.prepare('SELECT count(*) AS n FROM '+table).get().n});
}
const copy=v=>JSON.parse(JSON.stringify(v));
