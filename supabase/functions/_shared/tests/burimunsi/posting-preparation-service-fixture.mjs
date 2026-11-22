/** TEST ONLY: SQLite with PostgreSQL locks adapted away; real preparation SQL,
 * allocator, custody and AES-GCM. Media persistence below is a synthetic durable
 * journal adapter, not SupabaseObjectBucket or a live provider. No real secrets.
 */
import assert from 'node:assert/strict';
import {allocationFixture,ids,connectAllocationFlow} from './posting-allocation-fixture.mjs';
import {custodyFixture,encryption} from './posting-custody-fixture.mjs';
import {PostgresNativeAuthority} from '../../domain/burimunsi/postgres-authority.js';
import {PostgresPostingPreparation} from '../../domain/burimunsi/postgres-posting-preparation.js';
import {canonicalJson,sha256} from '../../domain/burimunsi/values.js';
export {ids,connectAllocationFlow};
export async function preparationFixture(mode='automatic',sourceBody=undefined){
  const f=await allocationFixture(mode,sourceBody),s=f.sqlite,{env}=await custodyFixture();
  for(const t of ['storage_put_intents','storage_objects','storage_payload_reservations'])s.prepare(`DELETE FROM private.${t} WHERE object_key LIKE 'evidence/%'`).run();
  Object.assign(f.state,{inTransaction:false,puts:0,encrypts:0,onPut:null,afterPut:null,onEncrypt:null,commitLost:false});
  const unsafe=f.sql.unsafe;
  f.sql.unsafe=async(text,values=[])=>text.startsWith("SELECT set_config(")?[]:unsafe(text,values);
  f.db.context=async()=>{};f.db.readContext=async()=>{};
  f.db.transaction=async fn=>{
    assert.equal(f.state.inTransaction,false,'no nested SQL transaction');s.exec('BEGIN');f.state.inTransaction=true;
    let committed=false;
    try{const result=await fn(f.sql);s.exec('COMMIT');committed=true;f.state.inTransaction=false;
      if(f.state.commitLost){f.state.commitLost=false;throw Error('synthetic lost commit reply');}return result;
    }catch(e){if(!committed)s.exec('ROLLBACK');throw e;}finally{f.state.inTransaction=false;}
  };
  const authority=new PostgresNativeAuthority({db:f.db,groupId:ids.group});
  const media={namespace:f.custody.namespace,put:async(key,value,options)=>{
    assert.equal(f.state.inTransaction,false,'storage I/O must be outside transaction');f.state.puts++;
    await f.state.onPut?.(key,value,options);
    const prior=s.prepare('SELECT * FROM private.storage_payload_reservations WHERE object_key=?').get(key);
    const custom={...options.customMetadata};if(prior)custom.key_id=prior.key_id;
    const d={scope:options.scope,aad:options.aad,keyId:prior?.key_id??env.DATA_KEY_ID,
      plaintextSha256:custom.sha256,requestDigest:options.sourceDigest,httpMetadata:options.httpMetadata,customMetadata:custom};
    const fingerprint=await sha256(canonicalJson(d));
    if(prior)assert.equal(prior.source_fingerprint,fingerprint,'immutable source fingerprint');
    const sealed=prior?.sealed_body??value,sha=await sha256(sealed),size=Buffer.byteLength(sealed),op=await sha256('test-operation:'+key);
    const data={object_key:key,operation_id:op,fingerprint:await sha256('test-intent:'+key),sha256:sha,size,
      scope:options.scope,http_metadata:options.httpMetadata,custom_metadata:{...custom,source_fingerprint:fingerprint}};
    const records={storage_put_intents:{...data,state:'committed',active_attempt:null,upload_unresolved:false,delete_tombstone:false},
      storage_objects:data,storage_payload_reservations:{object_key:key,source_fingerprint:fingerprint,scope:options.scope,
        aad:options.aad,key_id:d.keyId,plaintext_sha256:d.plaintextSha256,sealed_body:sealed}};
    for(const [table,row]of Object.entries(records)){
      const keys=Object.keys(row),values=Object.values(row).map(v=>typeof v==='boolean'?Number(v):v&&typeof v==='object'?JSON.stringify(v):v);
      s.prepare(`INSERT OR REPLACE INTO private.${table}(${keys.join(',')}) VALUES(${keys.map(()=>'?').join(',')})`).run(...values);
    }
    const ack={stored:true,metadataCommitted:true,operationId:op,key,sha256:sha,size};
    await f.state.afterPut?.(ack,key);return ack;
  }};
  const encrypt=async(bytes,aad)=>{assert.equal(f.state.inTransaction,false);f.state.encrypts++;await f.state.onEncrypt?.(bytes,aad);return encryption.encrypt(env,bytes,aad);};
  const args={authority,posting:f.writer,allocation:f.allocation,media,encrypt,keyId:env.DATA_KEY_ID};
  const preparation=new PostgresPostingPreparation(args);
  return {...f,authority,media,env,args,preparation,prepare:()=>preparation.prepare(f.command)};
}
