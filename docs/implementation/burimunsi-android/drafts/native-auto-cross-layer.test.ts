// Runs only against the isolated, loopback-bridged synthetic PostgreSQL fixture.
import assert from 'node:assert/strict';
import {connection,fenceConnection,PostgresDatabase} from '../../../../supabase/functions/_shared/postgres.js';
import {openApplicationWork,sqlFenceBackend} from '../../../../supabase/functions/_shared/application-fence.js';
import * as actualWorker from '../../../../supabase/functions/_shared/domain/burimunsi/postgres-native-auto-worker.js';
import {MOMO_SCHEMA_VERSION} from '../../../../supabase/functions/_shared/domain/momo_pipeline.js';
import {PostgresNativeAuthority} from '../../../../supabase/functions/_shared/domain/burimunsi/postgres-authority.js';
import {PostgresStorageWitnesses} from '../../../../supabase/functions/_shared/domain/burimunsi/postgres-storage-witnesses.js';
import {decrypt} from '../../../../supabase/functions/_shared/domain/encryption.js';
import {providerAdapters} from '../../../../supabase/functions/_shared/adapters.js';

Deno.test({name:'native worker decrypts a retained synthetic object and commits one automatic transaction',
 sanitizeOps:false,sanitizeResources:false,fn:async()=>{
  const url=Deno.env.get('BURI_AUTO_SYNTHETIC_DB')!,target=new URL(url);
  assert.equal(Deno.env.get('COLLECT_CI_SYNTHETIC'),'true');
  assert.equal(target.hostname,'127.0.0.1');
  assert.equal(target.pathname,'/collect_sms_content_test');
  const fixture=JSON.parse(await Deno.readTextFile(Deno.env.get('BURI_AUTO_SYNTHETIC_FIXTURE')!));
  let debugFile:string|undefined,worker:any=actualWorker;
  if(Deno.env.get('BURI_AUTO_DEBUG')==='1'){
   const original=new URL('../../../../supabase/functions/_shared/domain/burimunsi/postgres-native-auto-worker.js',import.meta.url);
   let code=await Deno.readTextFile(original);
   const target="throw new BuriError('native_auto_unavailable',503);";
   assert.equal(code.split(target).length,2);code=code.replace(target,'throw error;');
   code=code.replace(/(from\s*['"])(\.\.?\/[^'"]+)(['"])/g,(_all,a,s,b)=>a+new URL(s,original).href+b);
   debugFile=await Deno.makeTempFile({dir:new URL('.',new URL('file://'+Deno.env.get('BURI_AUTO_SYNTHETIC_FIXTURE')!)).pathname,suffix:'.mjs'});
   await Deno.writeTextFile(debugFile,code);worker=await import('file://'+debugFile);
  }
  const sql=connection(url),control=fenceConnection(url);
  const work=await openApplicationWork({backend:sqlFenceBackend(sql,control),sourceSha256:'a'.repeat(64),kind:'jobs'});
  const db=new PostgresDatabase(sql,{},work),namespace={origin:'https://synthetic-observation.example',bucket:'private'};
  let reads=0,calls=0;
  const media={namespace,async get(key:string){
   assert.equal(key,'sms/'+fixture.source);reads++;
   return {key,size:fixture.cipherSize,sha256:fixture.cipherSha,
    httpMetadata:{contentType:'application/octet-stream'},
    customMetadata:{sha256:fixture.objectSha,key_id:fixture.keyId,source_fingerprint:fixture.sourceFingerprint},
    async text(){return fixture.sealed;}};
  }};
  const output={schema_version:MOMO_SCHEMA_VERSION,event_kind:'incoming_receipt',payment_outcome:'successful',
   transaction_id_raw:'1234',original_transaction_id_raw:null,transaction_datetime_raw:null,principal_amount_raw:'250',
   currency_raw:'RWF',payer_name_raw:null,payer_identifier_raw:null,payment_reference_raw:null,
   fee_amount_raw:null,wallet_balance_after_raw:null,
   evidence:{incoming_success:'Received',principal:'Received 250 RWF',transaction_id:'Reference: 1234',
    transaction_datetime:null,payer:null,fee:null,wallet_balance_after:null},issues:[]};
  const env:any={DB:db,PRIVATE_MEDIA:media,BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED:'true',
   MOMO_AI_ENABLED:'true',MOMO_AI_MODEL:'synthetic-model',OPENAI_API_KEY:'synthetic-not-a-key',
   DATA_KEY_ID:fixture.keyId,DATA_ENCRYPTION_KEY:fixture.dataKey,
   AI:{async run(){calls++;return {response:JSON.stringify(output)};}}};
  if(Deno.env.get('BURI_AUTO_REAL_AI')==='1'){
   // Only the synthetic body above is sent; the real credential stays in its
   // existing protected file and never appears in command arguments or logs.
   const settings=JSON.parse(await Deno.readTextFile('/Volumes/SupaRuntime/collect-production/releases/testing-candidate-022/private/provider-settings.json'));
   env.MOMO_AI_MODEL=settings.MOMO_AI_MODEL;env.OPENAI_API_KEY=settings.OPENAI_API_KEY;
   env.COLLECT_FENCE_WORK=work;
   const adapter=providerAdapters(env).AI;assert(adapter);
   env.AI={async run(...args:any[]){calls++;
    try{const value=await adapter.run(...args);console.error('Synthetic provider response:',value.response);return value;}
    catch(error){console.error('Synthetic provider error:',{name:error?.name,code:error?.code,message:error?.message});throw error;}
   }};
  }
  assert.equal((await decrypt(env,fixture.sealed,`sms:${fixture.source}:${fixture.objectSha}`)).length,fixture.plainSize);
  const originalWrite=PostgresNativeAuthority.prototype.write;
  const originalPrefetch=PostgresStorageWitnesses.prototype.prefetch;
  const originalSealed=PostgresStorageWitnesses.prototype.sealed;
  PostgresNativeAuthority.prototype.write=function(fn:any){return originalWrite.call(this,async(tx:any)=>{
   try{return await fn(tx);}catch(error){console.error('Synthetic transaction failure:',error);throw error;}
  });};
  PostgresStorageWitnesses.prototype.prefetch=async function(plan:any){try{return await originalPrefetch.call(this,plan);}catch(error){console.error('Synthetic prefetch failure:',error);throw error;}};
  PostgresStorageWitnesses.prototype.sealed=async function(...args:any[]){try{return await originalSealed.apply(this,args);}catch(error){console.error('Synthetic sealed failure:',error);throw error;}};
  try{
   const first=await worker.drainNativeAutoTransactions(env,{limit:1});
   assert.equal(first.status,'complete');assert.equal(first.processed,1);
   assert.deepEqual(first.results,[{state:'completed',relation:'accepted'}]);
   const second=await worker.drainNativeAutoTransactions(env,{limit:1});
   assert.equal(second.status,'complete');assert.equal(second.processed,0);
   assert.equal(calls,1);assert.equal(reads,1);
   const rows=await sql.unsafe('SELECT id,event_kind,amount_minor,provider_transaction_id FROM app.momo_transactions');
   assert.equal(rows.length,1);assert.equal(rows[0].id,fixture.source);
   assert.equal(rows[0].event_kind,'incoming_receipt');assert.equal(Number(rows[0].amount_minor),250);
   assert.equal(rows[0].provider_transaction_id,'1234');
   assert.equal(Number((await sql.unsafe('SELECT count(*) AS n FROM app.ledger_entries'))[0].n),0);
  }catch(error){console.error('Synthetic progress:',{reads,calls});throw error;}
  finally{PostgresNativeAuthority.prototype.write=originalWrite;PostgresStorageWitnesses.prototype.prefetch=originalPrefetch;
   PostgresStorageWitnesses.prototype.sealed=originalSealed;await work.finish();await sql.end();await control.end();
   if(debugFile)await Deno.remove(debugFile);}
 }});
