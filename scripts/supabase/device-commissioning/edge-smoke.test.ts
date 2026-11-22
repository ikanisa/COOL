// Synthetic Deno API compatibility only; no network, credentials or live DB.
import {canonical,encode64,keyFingerprint,rawPublicKey,signDomain} from './protocol.mjs';
import {closedProductionTransport,createSyntheticTransport} from './synthetic-transport.mjs';

Deno.test('synthetic Edge request signs and verifies commissioning receipt and acknowledgement',async()=>{
 const pair=async()=>await crypto.subtle.generateKey({name:'Ed25519'},true,['sign','verify']) as CryptoKeyPair;
 const [target,operator,device]=await Promise.all([pair(),pair(),pair()]);
 const operatorSha256=await keyFingerprint(await rawPublicKey(operator.publicKey));
 const deviceSha256=await keyFingerprint(await rawPublicKey(device.publicKey));
 const policy={targetProject:'synthetic-project-only',primaryAccountSha256:'a'.repeat(64),targetApiSha256:'b'.repeat(64),
  targetAuthSha256:'c'.repeat(64),targetGatewaySha256:'d'.repeat(64),operatorSha256};
 const b={format:'collect.commissioning-binding.v1',transition_id:crypto.randomUUID(),target_project:policy.targetProject,
  application:'rw.ikanisa.burimunsi.gateway',role:'receiver',installation_sha256:'e'.repeat(64),source_api_sha256:'f'.repeat(64),
  source_auth_sha256:'1'.repeat(64),source_gateway_sha256:'2'.repeat(64),target_api_sha256:policy.targetApiSha256,
  target_auth_sha256:policy.targetAuthSha256,target_gateway_sha256:policy.targetGatewaySha256,source_account_sha256:'3'.repeat(64),
  target_primary_account_sha256:policy.primaryAccountSha256,account_group_mapping_sha256:'4'.repeat(64),source_fence_sha256:'5'.repeat(64),
  target_fence_sha256:'6'.repeat(64),reconciliation_sha256:'7'.repeat(64),sealed_queue_sha256:'8'.repeat(64),queue_generation:'1',
  queue_revision:'7',queue_watermark:'4',target_device_key_sha256:deviceSha256,approved_operator_sha256:operatorSha256,
  expires_epoch:String(Math.floor(Date.now()/1000)+120)};
 let receipt:any,ack:any;
 const store={
  issue:async (_binding:unknown,mint:(id:string)=>Promise<unknown>)=>({state:'committed',receipt:receipt??=await mint(crypto.randomUUID())}),
  consume:async (_binding:unknown,_id:string,_consumeId:string,mint:()=>Promise<unknown>)=>({state:'committed',ack:ack??=await mint()}),
  status:async ()=>receipt?{state:'found',receipt,...(ack?{ack}:{})}:{state:'absent_at_snapshot'}
 };
 const makeHandler=createSyntheticTransport as unknown as (options:Record<string,unknown>)=>Promise<(request:Request)=>Promise<Response>>;
 const handler=await makeHandler({policy,operatorPublicKey:operator.publicKey,targetPrivateKey:target.privateKey,targetPublicKey:target.publicKey,
  targetKeyId:'edge-fixture',store,authorize:async()=>true});
 const command=async(action:string,extra:Record<string,unknown>={})=>{
  const payload={action,binding:b,device_public_key:encode64(await rawPublicKey(device.publicKey)),format:'collect.commissioning-command.v1',...extra};
  return {...payload,operator_signature:await signDomain(operator.privateKey,'collect.commissioning.operator-'+action+'.v1',payload),
   device_signature:await signDomain(device.privateKey,'collect.commissioning.device-'+action+'.v1',payload)};
 };
 const send=async(value:unknown)=>handler(new Request('https://synthetic-only.invalid/commissioning/v1',{
  method:'POST',headers:{'content-type':'application/json'},body:canonical(value)}));
 const issued=await send(await command('issue'));if(issued.status!==200)throw Error('synthetic_issue_failed');
 const token=(await issued.json()).receipt;
 const consumed=await send(await command('consume',{receipt:token,consume_id:crypto.randomUUID()}));if(consumed.status!==200)throw Error('synthetic_consume_failed');
 const readback=await send(await command('status'));if(readback.status!==200||(await readback.json()).state!=='found')throw Error('synthetic_status_failed');
 if((await closedProductionTransport()()).status!==503)throw Error('production_not_closed');
});
