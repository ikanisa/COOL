/** Executes actual custody and posting SQL with actual pinned AES-GCM code.
 * This is an IN-MEMORY SQLITE fixture: PostgreSQL row/advisory locks are removed
 * explicitly. Runtime authority and allocation remain synthetic test bridges.
 * Never install this fixture as a deployment schema or runtime adapter.
 */
import {postingFixture,ids} from './posting-executor-fixture.mjs';
import {custodyFixture,encryption,namespace} from './posting-custody-fixture.mjs';
import {PostgresPostingCustody} from '../../domain/burimunsi/postgres-posting-custody.js';
import {sha256} from '../../domain/burimunsi/values.js';
export async function custodySqliteFixture(mode='automatic'){
 const f=postingFixture(mode),c=await custodyFixture(),s=f.sqlite,r=c.state.row;
 s.exec(`ALTER TABLE app.momo_transactions ADD COLUMN parse_attempt_id TEXT;
 ALTER TABLE app.payment_evidence ADD COLUMN owner_user_id TEXT;
 ALTER TABLE app.momo_receiving_accounts ADD COLUMN receiver_hash TEXT;
 ALTER TABLE app.momo_receiving_accounts ADD COLUMN profile_version TEXT;
 ALTER TABLE app.momo_receiving_accounts ADD COLUMN profile_json TEXT;
 CREATE TABLE app.momo_transaction_sources(transaction_id TEXT,raw_sms_id TEXT,parse_attempt_id TEXT,relation TEXT);
 CREATE TABLE app.sms_receipts(id TEXT PRIMARY KEY,owner_user_id TEXT,object_key TEXT,object_sha256 TEXT,size_bytes INTEGER,body_sha256 TEXT,receiver_hash TEXT);
 CREATE TABLE app.momo_parse_attempts(id TEXT PRIMARY KEY,raw_sms_id TEXT,source_body_sha256 TEXT,outcome TEXT,profile_version TEXT,profile_json TEXT);
 CREATE TABLE app.momo_gateway_captures(raw_sms_id TEXT PRIMARY KEY,credential_id TEXT,identity_sha256 TEXT,completeness TEXT,source_mode TEXT,subscription_id INTEGER);
 CREATE TABLE app.momo_processing_jobs(raw_sms_id TEXT PRIMARY KEY,binding_id TEXT,binding_version INTEGER,receiving_account_id TEXT,mode TEXT,state TEXT,last_error TEXT);
 CREATE TABLE app.momo_gateway_credentials(id TEXT PRIMARY KEY,binding_id TEXT,revoked_at TEXT);
 CREATE TABLE app.momo_gateway_bindings(id TEXT PRIMARY KEY,owner_user_id TEXT,receiving_account_id TEXT,version INTEGER,status TEXT,subscription_evidence TEXT);
 CREATE TABLE app.privacy_retention_barriers(subject_id TEXT PRIMARY KEY);
 CREATE TABLE private.storage_namespace(singleton BOOLEAN PRIMARY KEY,origin TEXT,bucket TEXT);
 CREATE TABLE private.storage_put_intents(object_key TEXT PRIMARY KEY,operation_id TEXT,fingerprint TEXT,sha256 TEXT,size INTEGER,scope TEXT,http_metadata TEXT,custom_metadata TEXT,state TEXT,active_attempt TEXT,upload_unresolved BOOLEAN,delete_tombstone BOOLEAN);
 CREATE TABLE private.storage_objects(object_key TEXT PRIMARY KEY,operation_id TEXT,fingerprint TEXT,sha256 TEXT,size INTEGER,scope TEXT,http_metadata TEXT,custom_metadata TEXT);
 CREATE TABLE private.storage_payload_reservations(object_key TEXT PRIMARY KEY,source_fingerprint TEXT,scope TEXT,aad TEXT,key_id TEXT,plaintext_sha256 TEXT,sealed_body TEXT);
 CREATE TABLE private.storage_delete_intents(object_key TEXT PRIMARY KEY,operation_id TEXT);`);
 s.prepare('UPDATE app.momo_transactions SET parse_attempt_id=?').run('parse-1');
 s.prepare('UPDATE app.momo_receiving_accounts SET receiver_hash=?,profile_version=?,profile_json=?').run(r.wallet_hash,r.profile_version,r.wallet_profile_json);
 s.prepare('UPDATE app.payment_evidence SET owner_user_id=?,object_key=?,object_sha256=?,size_bytes=?').run(ids.otherActor,'evidence/'+ids.evidence,r.body_sha256,r.evidence_size);
 s.prepare('INSERT INTO app.momo_transaction_sources VALUES(?,?,?,?)').run('transaction-1','raw-1','parse-1','accepted');
 s.prepare('INSERT INTO app.sms_receipts VALUES(?,?,?,?,?,?,?)').run('raw-1',r.raw_owner,r.raw_key,r.raw_sha256,r.raw_size,r.body_sha256,r.receiver_hash);
 s.prepare('INSERT INTO app.momo_parse_attempts VALUES(?,?,?,?,?,?)').run('parse-1','raw-1',r.body_sha256,'accepted',r.profile_version,r.parse_profile_json);
 s.prepare('INSERT INTO app.momo_gateway_captures VALUES(?,?,?,?,?,?)').run('raw-1','credential-1',r.identity_sha256,'complete','live',7);
 s.prepare('INSERT INTO app.momo_processing_jobs VALUES(?,?,?,?,?,?,?)').run('raw-1','binding-1',2,'wallet-1','live','completed',null);
 s.prepare('INSERT INTO app.momo_gateway_credentials VALUES(?,?,?)').run('credential-1','binding-1',null);
 s.prepare('INSERT INTO app.momo_gateway_bindings VALUES(?,?,?,?,?,?)').run('binding-1',r.raw_owner,'wallet-1',2,'active',r.subscription_evidence);
 s.prepare('INSERT INTO private.storage_namespace VALUES(?,?,?)').run(1,namespace.origin,namespace.bucket);
 // Target identity/AAD uses the existing posting fixture's actual evidence UUID.
 const target=c.state.journals.get('evidence/evidence-1'),body=await encryption.decrypt(c.env,target.reservation.sealed_body,target.reservation.aad);
 const aad=`evidence:${ids.evidence}:${r.body_sha256}`,sealed=await encryption.encrypt(c.env,body,aad),cipherSha=await sha256(sealed);
 for(const record of [target.put,target.metadata,target.reservation]){
   record.object_key='evidence/'+ids.evidence;record.scope.ownerId=ids.otherActor;record.scope.entityId=ids.evidence;
 }
 target.reservation.aad=aad;target.reservation.sealed_body=sealed;
 for(const record of [target.put,target.metadata]){record.sha256=cipherSha;record.size=Buffer.byteLength(sealed);}
 for(const journal of c.state.journals.values())for(const [name,record]of Object.entries(journal)){
   const table={put:'storage_put_intents',metadata:'storage_objects',reservation:'storage_payload_reservations'}[name];
   const columns=Object.keys(record),values=Object.values(record).map(v=>typeof v==='boolean'?Number(v):v&&typeof v==='object'?JSON.stringify(v):v);
   s.prepare(`INSERT INTO private.${table}(${columns.join(',')}) VALUES(${columns.map(()=>'?').join(',')})`).run(...values);
 }
 const bools=['has_entries','has_snapshot','has_other_reference','source_conflict','upload_unresolved','delete_tombstone'];
 const jsons=['scope','http_metadata','custom_metadata'];
 const original=f.sql.unsafe;
 f.sql.unsafe=async(text,values=[])=>{
   if(text.startsWith('SELECT pg_advisory')){f.state.queries.push({text,values,notExecuted:'PostgreSQL advisory lock is outside this SQLite scope'});return [{}];}
   f.state.queries.push({text,values});
   const params=[];const compiled=text.replace(/\s+FOR UPDATE(?: OF [\w,]+)?\s*$/,'').replace(/\s+FOR SHARE\s*$/,'')
     .replace(/\$(\d+)/g,(_s,n)=>{params.push(values[Number(n)-1]);return '?';});
   return s.prepare(compiled).all(...params).map(row=>{
     const out={...row};for(const key of bools)if(key in out&&out[key]!==null)out[key]=Boolean(out[key]);
     for(const key of jsons)if(key in out&&typeof out[key]==='string')out[key]=JSON.parse(out[key]);return out;
   });
 };
 let decryptCount=0;const custody=new PostgresPostingCustody({db:f.db,groupId:ids.group,namespace,
   decrypt:async(document,context)=>{decryptCount++;return encryption.decrypt(c.env,document,context);}});
 f.writer.evidence=custody;
 return {...f,custody,decryptCount:()=>decryptCount};
}
