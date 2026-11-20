/** TEST ONLY. Actual SupabaseObjectBucket get/read/describe/checked methods,
 * protected-storage transport/protocol and pinned AES-GCM; synthetic HTTP,
 * journal and authority. SQLite strips PostgreSQL locks. Scrub-after-INSERT is
 * explicitly emulated in the same SQLite transaction, not PostgreSQL-qualified.
 * No provider, database server, production key or real account is contacted. */
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {preparationFixture} from './posting-preparation-service-fixture.mjs';
import {connectAllocationFlow} from './posting-allocation-fixture.mjs';
import {PostgresPostingCustody} from '../../domain/burimunsi/postgres-posting-custody.js';
import {PostgresPostingAllocation} from '../../domain/burimunsi/postgres-posting-allocation.js';
import {PostgresPostingPreparation} from '../../domain/burimunsi/postgres-posting-preparation.js';
import {PostgresStorageWitnesses} from '../../domain/burimunsi/postgres-storage-witnesses.js';
import {SupabaseNativeTransport} from '../../storage/supabase-transport.js';
import {ProtectedStorageProtocol,StorageProtocolError} from '../../storage/protocol.js';

// Extract the unchanged class to avoid loading unrelated SMTP/npm provider
// dependencies in Node. We instantiate its prototype with controlled ports;
// the production read/get methods below execute verbatim, not copied logic.
const adapters=readFileSync(new URL('../../adapters.js',import.meta.url),'utf8');
const start=adapters.indexOf('export class SupabaseObjectBucket {');
const end=adapters.indexOf('\n// Leave room for JSON escaping',start);
assert(start>=0&&end>start);
class ApiError extends Error{constructor(status,code,message){super(message);this.status=status;this.code=code;}}
const Bucket=new Function('StorageProtocolError','ApiError','unavailable',
  adapters.slice(start,end).replace('export class','class')+';return SupabaseObjectBucket;')(
  StorageProtocolError,ApiError,name=>new ApiError(503,name+'_unavailable','Synthetic unavailable'));
const parse=row=>row&&Object.fromEntries(Object.entries(row).map(([key,value])=>[key,
  ['scope','http_metadata','custom_metadata'].includes(key)?JSON.parse(value):
  ['upload_unresolved','delete_tombstone'].includes(key)?Boolean(value):value]));
const intent=r=>r&&{key:r.object_key,operationId:r.operation_id,fingerprint:r.fingerprint,sha256:r.sha256,size:r.size,
  scope:r.scope,httpMetadata:r.http_metadata,customMetadata:r.custom_metadata,state:r.state,
  activeAttempt:r.active_attempt,uploadUnresolved:r.upload_unresolved,deleteTombstone:r.delete_tombstone};

export async function storageWitnessFixture(mode='automatic',sourceBody=undefined){
  const f=await preparationFixture(mode,sourceBody),s=f.sqlite;
  s.exec(`ALTER TABLE app.momo_gateway_credentials ADD COLUMN installation_id TEXT DEFAULT '11111111-1111-4111-8111-111111111112';
    CREATE TABLE private.burimunsi_accounts(id TEXT,collection_id TEXT,principal_user_id TEXT);
    CREATE TABLE private.burimunsi_sms_source_scopes(source_id TEXT PRIMARY KEY,collection_id TEXT,receiving_account_id TEXT,
      owner_user_id TEXT,source_body_sha256 TEXT,object_sha256 TEXT,binding_id TEXT,binding_version INTEGER,credential_id TEXT,
      installation_id TEXT,custodian_account_id TEXT,grant_id TEXT,grant_version INTEGER,provenance TEXT,proof_id TEXT,proof_sha256 TEXT,associated_at TEXT);`);
  const rawSource=s.prepare('SELECT * FROM app.sms_receipts').get();
  s.prepare('INSERT INTO private.burimunsi_accounts VALUES(?,?,?)').run('custodian-1',f.command.groupId,rawSource.owner_user_id);
  s.prepare('INSERT INTO private.burimunsi_sms_source_scopes VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)').run(
    rawSource.id,f.command.groupId,'wallet-1',rawSource.owner_user_id,rawSource.body_sha256,rawSource.object_sha256,'binding-1',2,
    'credential-1','11111111-1111-4111-8111-111111111112','custodian-1','grant-1',1,'gateway_capture','capture-proof','c'.repeat(64),'2026-11-07 08:00:01+00');
  const unsafe=f.sql.unsafe;
  f.sql.unsafe=(text,values)=>unsafe(text.replaceAll('::text',''),values);
  Object.assign(f.state,{storageCalls:[],onStorage:null,scrubs:0,now:1000000,tuple:['11111111-1111-4111-8111-111111111111',1,'a'.repeat(64)],onAssert:null});
  f.db.applicationWork.assert=async()=>{await f.state.onAssert?.();};
  const remote=new Map(s.prepare('SELECT object_key,sealed_body FROM private.storage_payload_reservations').all()
    .map(r=>[r.object_key,Buffer.from(r.sealed_body)]));
  const transport=new SupabaseNativeTransport({url:f.custody.namespace.origin,bucket:f.custody.namespace.bucket,
    secretKey:'sb_secret_synthetic_storage_witness',fetchImpl:async(url,init)=>{
      assert.equal(f.state.inTransaction,false,'Storage HTTP must be outside the financial/SQL transaction');
      const u=new URL(url);assert.equal(u.origin,f.custody.namespace.origin);
      f.state.storageCalls.push({method:init.method,path:u.pathname});await f.state.onStorage?.(u,init);
      if(u.pathname==='/storage/v1/bucket/collect-evidence')return Response.json({id:'collect-evidence',name:'collect-evidence',public:false});
      const prefix='/storage/v1/object/authenticated/collect-evidence/';assert(u.pathname.startsWith(prefix));
      const key=decodeURIComponent(u.pathname.slice(prefix.length)),bytes=remote.get(key);
      return new Response(init.method==='HEAD'?null:bytes??'missing',{status:bytes?200:404,
        headers:{'Content-Type':'application/octet-stream',...(bytes?{'Content-Length':String(bytes.length)}:{})}});
    }});
  const journal={
    async getPutByKey(key){assert.equal(f.state.inTransaction,false);return intent(parse(s.prepare('SELECT * FROM private.storage_put_intents WHERE object_key=?').get(key)));},
    async getObject(key){assert.equal(f.state.inTransaction,false);return intent(parse(s.prepare('SELECT * FROM private.storage_objects WHERE object_key=?').get(key)));},
    async recordOutcome(){/* Synthetic journal observation only; no provider retry. */}
  };
  const media=Object.assign(Object.create(Bucket.prototype),{namespace:f.custody.namespace,journal,transport,
    protocol:new ProtectedStorageProtocol({transport,journal})});
  media.put=async(...args)=>{
    const ack=await f.media.put(...args);
    const sealed=s.prepare('SELECT sealed_body FROM private.storage_payload_reservations WHERE object_key=?').get(ack.key).sealed_body;
    assert.equal(typeof sealed,'string');remote.set(ack.key,Buffer.from(sealed));return ack;
  };
  const storageWitnesses=new PostgresStorageWitnesses({db:f.db,groupId:f.command.groupId,namespace:media.namespace,media,
    applicationWorkTuple:()=>[...f.state.tuple],clock:()=>f.state.now});
  const custody=new PostgresPostingCustody({db:f.db,groupId:f.command.groupId,namespace:media.namespace,
    decrypt:f.custody.decrypt,storageWitnesses});
  const allocation=new PostgresPostingAllocation({db:f.db,groupId:f.command.groupId,custody});
  f.writer.evidence=custody;f.writer.allocation=allocation;
  const preparation=new PostgresPostingPreparation({authority:f.authority,posting:f.writer,allocation,media,
    encrypt:f.args.encrypt,keyId:f.args.keyId});
  // Actual baseline clears raw reservation bytes after sms_receipts INSERT.
  s.exec("UPDATE private.storage_payload_reservations SET sealed_body=NULL WHERE object_key LIKE 'sms/%'");
  const after=f.state.afterQuery;
  f.state.afterQuery=async(text,values,rows)=>{
    await after?.(text,values,rows);
    if(text.startsWith('INSERT INTO app.payment_evidence')){
      s.prepare('UPDATE private.storage_payload_reservations SET sealed_body=NULL WHERE object_key=?').run(values[3]);
      f.state.scrubs++;
    }
  };
  const result={...f,storageWitnesses,custody,allocation,preparation,media,remote,prepare:()=>preparation.prepare(f.command)};
  result.connect=()=>{
    connectAllocationFlow(result);
    const write=result.store.authority.write;
    result.store.authority.write=async fn=>{
      assert.equal(result.state.inTransaction,false);result.state.inTransaction=true;
      try{return await write(fn);}finally{result.state.inTransaction=false;}
    };
    result.service.preparation=preparation;return result;
  };
  return result;
}
