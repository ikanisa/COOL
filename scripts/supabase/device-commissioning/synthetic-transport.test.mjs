// All identities, keys and database records here are synthetic. The fixture
// never connects to a device, a real local database, or Supabase.
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createPrivateKey,createPublicKey,randomBytes,randomUUID,sign as nativeSign,verify as nativeVerify} from 'node:crypto';
import pg from '../node_modules/pg/lib/index.js';
import {startOwnedPg17} from '../current-pg-transfer/test-support/owned-pg17.mjs';
import {canonical,encode64,keyFingerprint,rawPublicKey,signDomain,verifyEnvelope} from './protocol.mjs';
import {closedProductionTransport,createSyntheticTransport} from './synthetic-transport.mjs';

const hash=()=>randomBytes(32).toString('hex');
const keys=()=>crypto.subtle.generateKey({name:'Ed25519'},true,['sign','verify']);
const fixtureBinding=b=>({...b,format:'collect.fixture.commissioning-binding.v1'});
const commandUrl='https://synthetic-only.invalid/commissioning/v1';
test('signed commissioning transport with durable synthetic PostgreSQL receipts', {timeout:120000},async t=>{
 const cluster=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_commissioning_synthetic_only'});
 const clients=[];let admin,server,operator,device,other,policy,now=Date.now(),authorised=true,issued=0,consumed=0,dropIssueAck=false,dropConsumeAck=false;
 const connect=async(database='collect_commissioning_fixture_wire')=>{const c=new pg.Client({host:cluster.socket,port:cluster.port,database,user:'fixture_bootstrap',connectionTimeoutMillis:3000});c.on('error',()=>{});clients.push(c);await c.connect();return c;};
 try{
  admin=await connect('postgres');await admin.query('CREATE DATABASE collect_commissioning_fixture_wire');
  const owner=await connect();await owner.query('CREATE ROLE collect_commissioning_fixture_runtime LOGIN NOSUPERUSER NOINHERIT');
  await owner.query(await readFile(new URL('./fixture-schema.sql',import.meta.url),'utf8'));
  // This test-owned table supplies durable signing bytes for the synthetic
  // adapter only. Production role, fence and retention design remain absent.
  await owner.query('CREATE TABLE commissioning_fixture.wire_receipts (transition_id uuid PRIMARY KEY,receipt text NOT NULL,ack text); REVOKE ALL ON commissioning_fixture.wire_receipts FROM PUBLIC,collect_commissioning_fixture_runtime');
  [server,operator,device,other]=await Promise.all([keys(),keys(),keys(),keys()]);
  const operatorSha256=await keyFingerprint(await rawPublicKey(operator.publicKey));
  let deviceSha256=await keyFingerprint(await rawPublicKey(device.publicKey));
  const newDevice=async()=>{device=await keys();deviceSha256=await keyFingerprint(await rawPublicKey(device.publicKey));};
  policy={targetProject:'synthetic-project-only',primaryAccountSha256:hash(),targetApiSha256:hash(),targetAuthSha256:hash(),targetGatewaySha256:hash(),operatorSha256};
  const binding=()=>({format:'collect.commissioning-binding.v1',transition_id:randomUUID(),target_project:policy.targetProject,
   application:'rw.ikanisa.burimunsi.gateway',role:'receiver',installation_sha256:hash(),source_api_sha256:hash(),source_auth_sha256:hash(),source_gateway_sha256:hash(),
   target_api_sha256:policy.targetApiSha256,target_auth_sha256:policy.targetAuthSha256,target_gateway_sha256:policy.targetGatewaySha256,
   source_account_sha256:hash(),target_primary_account_sha256:policy.primaryAccountSha256,account_group_mapping_sha256:hash(),source_fence_sha256:hash(),
   target_fence_sha256:hash(),reconciliation_sha256:hash(),sealed_queue_sha256:hash(),queue_generation:'1',queue_revision:'7',queue_watermark:'4',
   target_device_key_sha256:deviceSha256,approved_operator_sha256:policy.operatorSha256,expires_epoch:String(Math.floor(now/1000)+120)});
  const store={
   async issue(b,mint){issued++;const c=await connect();try{
    await c.query('BEGIN');const row=(await c.query('SELECT commissioning_fixture.issue($1::jsonb) AS result',[JSON.stringify(fixtureBinding(b))])).rows[0].result;
    let stored=(await c.query('SELECT receipt FROM commissioning_fixture.wire_receipts WHERE transition_id=$1',[b.transition_id])).rows[0]?.receipt;
    if(!stored){stored=canonical(await mint(row.receipt_id));await c.query('INSERT INTO commissioning_fixture.wire_receipts(transition_id,receipt) VALUES($1,$2)',[b.transition_id,stored]);}
    await c.query('COMMIT');if(dropIssueAck){dropIssueAck=false;throw Error('synthetic lost ack');}
    return {state:'committed',receipt:JSON.parse(stored)};
   }catch(e){await c.query('ROLLBACK').catch(()=>{});throw e;}finally{await c.end();}},
   async consume(b,id,consumeId,mint){consumed++;const c=await connect();try{
    await c.query('BEGIN');await c.query('SELECT commissioning_fixture.consume($1::jsonb)',[JSON.stringify({transition_id:b.transition_id,receipt_id:id,installation_sha256:b.installation_sha256,target_device_key_sha256:b.target_device_key_sha256,consume_id:consumeId})]);
    let prior=(await c.query('SELECT ack FROM commissioning_fixture.wire_receipts WHERE transition_id=$1 FOR UPDATE',[b.transition_id])).rows[0]?.ack;
    if(!prior){prior=canonical(await mint());await c.query('UPDATE commissioning_fixture.wire_receipts SET ack=$2 WHERE transition_id=$1',[b.transition_id,prior]);}
    await c.query('COMMIT');if(dropConsumeAck){dropConsumeAck=false;throw Error('synthetic lost ack');}
    return {state:'committed',ack:JSON.parse(prior)};
   }catch(e){await c.query('ROLLBACK').catch(()=>{});throw e;}finally{await c.end();}},
   async status(b){const c=await connect();try{
    await c.query('BEGIN READ ONLY');const status=(await c.query('SELECT commissioning_fixture.status($1::jsonb) AS result',[JSON.stringify(fixtureBinding(b))])).rows[0].result;
    const prior=(await c.query('SELECT receipt,ack FROM commissioning_fixture.wire_receipts WHERE transition_id=$1',[b.transition_id])).rows[0];await c.query('COMMIT');
    if(status.state!=='found'||!prior)return {state:'absent_at_snapshot'};
    return {state:'found',receipt:JSON.parse(prior.receipt),...(prior.ack?{ack:JSON.parse(prior.ack)}:{})};
   }catch(e){await c.query('ROLLBACK').catch(()=>{});throw e;}finally{await c.end();}}
  };
  const handler=await createSyntheticTransport({policy,operatorPublicKey:operator.publicKey,targetPrivateKey:server.privateKey,targetPublicKey:server.publicKey,
   targetKeyId:'fixture-key',store,authorize:async()=>authorised,clock:()=>now});
  async function command(action,b,extras={},signer=operator,deviceSigner=device){
   const payload={action,binding:b,device_public_key:encode64(await rawPublicKey(deviceSigner.publicKey)),format:'collect.commissioning-command.v1',...extras};
   return {...payload,operator_signature:await signDomain(signer.privateKey,'collect.commissioning.operator-'+action+'.v1',payload),
    device_signature:await signDomain(deviceSigner.privateKey,'collect.commissioning.device-'+action+'.v1',payload)};
  }
  const send=async command=>{const r=await handler(new Request(commandUrl,{method:'POST',headers:{'content-type':'application/json'},body:canonical(command)}));return {status:r.status,body:await r.json()};};

  await t.test('production route is closed and real project configuration is refused',async()=>{
   assert.equal((await closedProductionTransport()(new Request(commandUrl))).status,503);
   await assert.rejects(createSyntheticTransport({policy:{...policy,targetProject:'rrlduytparvsjfmegalh'},operatorPublicKey:operator.publicKey,targetPrivateKey:server.privateKey,targetPublicKey:server.publicKey,targetKeyId:'fixture-key',store,authorize:async()=>true}),/synthetic_transport_refused/);
  });
  await t.test('changing a caller-owned policy after construction cannot retarget the transport',async()=>{
   const mutable={...policy},h=await createSyntheticTransport({policy:mutable,operatorPublicKey:operator.publicKey,targetPrivateKey:server.privateKey,targetPublicKey:server.publicKey,targetKeyId:'fixture-key',store,authorize:async()=>true});
   mutable.targetProject='rrlduytparvsjfmegalh';const b={...binding(),target_project:mutable.targetProject},c=await command('status',b);
   assert.equal((await h(new Request(commandUrl,{method:'POST',headers:{'content-type':'application/json'},body:canonical(c)}))).status,400);
  });
  await t.test('signed dual-authority issuance, consumption, retry and status retain identical durable tokens',async()=>{
   const b=binding(),issue=await command('issue',b),first=await send(issue);assert.equal(first.status,200);
   const verified=await verifyEnvelope(first.body.receipt,server.publicKey,'fixture-key','receipt');assert.deepEqual(verified.binding,b);
   assert.deepEqual(await send(issue),first);const consumeId=randomUUID(),c=await command('consume',b,{consume_id:consumeId,receipt:first.body.receipt});
   const ack=await send(c);assert.equal(ack.status,200);assert.deepEqual(await send(c),ack);
   assert.deepEqual((await send(await command('status',b))).body,{state:'found',receipt:first.body.receipt,ack:ack.body.ack});
   assert.equal((await send(await command('consume',b,{consume_id:randomUUID(),receipt:first.body.receipt}))).status,503);
   assert.equal((await owner.query('SELECT count(*)::int AS n FROM commissioning_fixture.receipts WHERE transition_id=$1',[b.transition_id])).rows[0].n,1);
  });
  await t.test('a newly signed changed custody binding conflicts with an existing transition',async()=>{
   await newDevice();const b=binding(),first=await send(await command('issue',b));assert.equal(first.status,200);
   assert.equal((await send(await command('issue',{...b,sealed_queue_sha256:hash()}))).status,503);
   assert.deepEqual((await send(await command('status',b))).body.receipt,first.body.receipt);
  });
  await t.test('native Ed25519 signatures interoperate with Web Crypto and the signed receipt',async()=>{
   await newDevice();const b=binding(),payload={action:'issue',binding:b,device_public_key:encode64(await rawPublicKey(device.publicKey)),format:'collect.commissioning-command.v1'};
   const nativeKey=async pair=>createPrivateKey({key:Buffer.from(await crypto.subtle.exportKey('pkcs8',pair.privateKey)),format:'der',type:'pkcs8'});
   const sig=async(pair,domain)=>encode64(nativeSign(null,Buffer.from(domain+'\n'+canonical(payload)),await nativeKey(pair)));
   const result=await send({...payload,operator_signature:await sig(operator,'collect.commissioning.operator-issue.v1'),device_signature:await sig(device,'collect.commissioning.device-issue.v1')});
   assert.equal(result.status,200);const {signature,...content}=result.body.receipt;
   const pub=createPublicKey({key:Buffer.from(await crypto.subtle.exportKey('spki',server.publicKey)),format:'der',type:'spki'});
   assert.equal(nativeVerify(null,Buffer.from('collect.commissioning.target-receipt.v1\n'+canonical(content)),pub,Buffer.from(signature,'base64url')),true);
  });
  await t.test('bad or cross-action signatures and changed primary identity never reach the store',async()=>{
   const b=binding(),good=await command('issue',b),start=issued;
   for(const bad of [await command('issue',b,{},other),await command('issue',b,{},operator,other),{...good,action:'status'},
    {...good,binding:{...b,target_primary_account_sha256:hash()}},{...good,operator_signature:good.device_signature}])assert.equal((await send(bad)).status,400);
   assert.equal(issued,start);
  });
  await t.test('only canonical bounded JSON at the exact route is accepted',async()=>{
   const b=binding(),c=await command('issue',b),body=canonical(c),requests=[
    new Request(commandUrl,{method:'POST',headers:{'content-type':'text/plain'},body}),
    new Request(commandUrl,{method:'POST',headers:{'content-type':'application/json'},body:' '+body}),
    new Request(commandUrl,{method:'POST',headers:{'content-type':'application/json'},body:'{"action":"issue","action":"issue"}'}),
    new Request(commandUrl,{method:'POST',headers:{'content-type':'application/json'},body:'x'.repeat(16385)}),
    new Request(commandUrl,{method:'POST',headers:{'content-type':'application/json','content-length':'1'},body}),
    new Request(commandUrl+'?alias=1',{method:'POST',headers:{'content-type':'application/json'},body}),
    new Request('https://different.invalid/commissioning/v1',{method:'POST',headers:{'content-type':'application/json'},body})];
   const before=issued;for(const request of requests)assert.ok([400,404].includes((await handler(request)).status));assert.equal(issued,before);
  });
  await t.test('a stalled request body times out without reaching authority or storage',async()=>{
   const h=await createSyntheticTransport({policy,operatorPublicKey:operator.publicKey,targetPrivateKey:server.privateKey,targetPublicKey:server.publicKey,targetKeyId:'fixture-key',store,authorize:async()=>{throw Error('unexpected');},clock:()=>now,bodyTimeoutMs:25});
   const stream=new ReadableStream({start(){},cancel(){}}),request=new Request(commandUrl,{method:'POST',headers:{'content-type':'application/json'},body:stream,duplex:'half'});
   const before=issued;assert.equal((await h(request)).status,400);assert.equal(issued,before);
  });
  await t.test('unknown commit acknowledgements recover only through authenticated readback',async()=>{
   await newDevice();const b=binding(),issueBefore=issued,consumeBefore=consumed;dropIssueAck=true;assert.equal((await send(await command('issue',b))).status,503);
   const status=await send(await command('status',b));assert.equal(status.status,200);assert.equal(issued,issueBefore+1);const receipt=status.body.receipt;
   const id=randomUUID();dropConsumeAck=true;assert.equal((await send(await command('consume',b,{consume_id:id,receipt}))).status,503);
   const result=await send(await command('status',b));assert.equal(result.status,200);assert.equal(result.body.ack.payload.consume_id,id);
   assert.equal(consumed,consumeBefore+1);
   assert.equal((await send(await command('status',binding()))).status,503);
  });
  await t.test('a timed-out committed issue stays unknown until a separate authenticated status read',async()=>{
   await newDevice();const b=binding(),slow={...store,issue:async(...args)=>{const result=await store.issue(...args);await new Promise(resolve=>setTimeout(resolve,120));return result;}};
   const h=await createSyntheticTransport({policy,operatorPublicKey:operator.publicKey,targetPrivateKey:server.privateKey,targetPublicKey:server.publicKey,targetKeyId:'fixture-key',store:slow,authorize:async()=>true,clock:()=>now,adapterTimeoutMs:30});
   const req=await command('issue',b);assert.equal((await h(new Request(commandUrl,{method:'POST',headers:{'content-type':'application/json'},body:canonical(req)}))).status,503);
   await new Promise(resolve=>setTimeout(resolve,150));assert.equal((await send(await command('status',b))).status,200);
  });
  await t.test('issue that finishes after expiry is unconfirmed but remains readable by status',async()=>{
   await newDevice();const b=binding(),before=now;
   try{
    const slow={...store,issue:async(...args)=>{const result=await store.issue(...args);now=Number(b.expires_epoch)*1000;return result;}};
    const h=await createSyntheticTransport({policy,operatorPublicKey:operator.publicKey,targetPrivateKey:server.privateKey,targetPublicKey:server.publicKey,targetKeyId:'fixture-key',store:slow,authorize:async()=>true,clock:()=>now});
    const req=await command('issue',b),r=await h(new Request(commandUrl,{method:'POST',headers:{'content-type':'application/json'},body:canonical(req)}));
    assert.equal(r.status,503);assert.equal((await r.json()).code,'unconfirmed');
    const status=await send(await command('status',b));assert.equal(status.status,200);assert.equal(status.body.state,'found');
    assert.deepEqual(status.body.receipt.payload.binding,b);assert.equal(Object.hasOwn(status.body,'ack'),false);
   }finally{now=before;}
  });
  await t.test('consumption that finishes after expiry is unconfirmed but its acknowledgement remains readable',async()=>{
   await newDevice();const b=binding(),before=now;
   try{
    const initial=await send(await command('issue',b));assert.equal(initial.status,200);const consumeId=randomUUID();
    const slow={...store,consume:async(...args)=>{const result=await store.consume(...args);now=Number(b.expires_epoch)*1000;return result;}};
    const h=await createSyntheticTransport({policy,operatorPublicKey:operator.publicKey,targetPrivateKey:server.privateKey,targetPublicKey:server.publicKey,targetKeyId:'fixture-key',store:slow,authorize:async()=>true,clock:()=>now});
    const req=await command('consume',b,{consume_id:consumeId,receipt:initial.body.receipt});
    const r=await h(new Request(commandUrl,{method:'POST',headers:{'content-type':'application/json'},body:canonical(req)}));
    assert.equal(r.status,503);assert.equal((await r.json()).code,'unconfirmed');
    const status=await send(await command('status',b));assert.equal(status.status,200);assert.equal(status.body.state,'found');
    assert.equal(status.body.ack.payload.consume_id,consumeId);assert.deepEqual(status.body.receipt,initial.body.receipt);
   }finally{now=before;}
  });
  await t.test('concurrent copies serialize to one signed receipt and one signed acknowledgement',async()=>{
   await newDevice();const b=binding(),c=await command('issue',b),[a,d]=await Promise.all([send(c),send(c)]);assert.equal(a.status,200);assert.deepEqual(a,d);
   const use=await command('consume',b,{consume_id:randomUUID(),receipt:a.body.receipt}),[x,y]=await Promise.all([send(use),send(use)]);assert.equal(x.status,200);assert.deepEqual(x,y);
  });
  await t.test('tampered receipts, expiration and denied authority cannot create effects',async()=>{
   await newDevice();const b=binding(),first=await send(await command('issue',b));assert.equal(first.status,200);const before=consumed;
   const receipt=structuredClone(first.body.receipt);receipt.payload.binding.queue_watermark='5';
   assert.equal((await send(await command('consume',b,{consume_id:randomUUID(),receipt}))).status,503);assert.equal(consumed,before);
   authorised=false;assert.equal((await send(await command('issue',binding()))).status,503);authorised=true;
   now+=121000;assert.equal((await send(await command('consume',b,{consume_id:randomUUID(),receipt:first.body.receipt}))).status,400);
   const recovered=await send(await command('status',b));assert.equal(recovered.status,200);now-=121000;
  });
 }finally{
  await Promise.allSettled(clients.map(c=>c.end()));const closed=await cluster.close();assert.equal(closed.removed,true,'owned fixture cleanup must be confirmed');
 }
});
