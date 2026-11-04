import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash,createHmac} from 'node:crypto';

// Intercept the pinned driver before loading the real wrapper. The replacement
// below contains only in-process SQL/fence doubles and never opens a socket.
await import('./helpers/node-postgres-import.mjs');
const {canonicalProfile}=await import('../deployment-profile.js');
const {COLLECT_PROJECT_REF,COLLECT_SUPABASE_ORIGIN,normalizeDatabaseTarget,normalizeRuntimeEnv}=await import('../runtime-env.js');
const {createCollectSendSmsHandler}=await import('../send-sms-hook.js');

const NOW=1793448000000,secret=Buffer.alloc(32,7),source='a'.repeat(64);
const profile={format:'collect.deployment.v1',id:'sms-hook-target-test',mode:'self_hosted',environment:'qualification',
 supabase_origin:'https://supabase.collect.example',member_api_origin:'https://api.collect.example',
 admin_origin:'https://admin.collect.example',public_origin:'https://collect.example',google_callback_origin:'https://admin.collect.example'};
const raw=canonicalProfile(profile),profileHash=createHash('sha256').update(raw).digest('hex');
const ca='-----BEGIN CERTIFICATE-----\nAA==\n-----END CERTIFICATE-----';
const publicKey='sb_publishable_synthetic',serviceKey='sb_secret_synthetic';
let instance=0;
function settings(){
 const database=`postgres://collect_edge:synthetic_${++instance}@db:5432/postgres`;
 return {COLLECT_DEPLOYMENT_PROFILE:raw,COLLECT_DEPLOYMENT_PROFILE_SHA256:profileHash,BUILD_SOURCE_ID:source,
  APP_ENVIRONMENT:profile.environment,SUPABASE_URL:profile.supabase_origin,COLLECT_DATABASE_URL:database,COLLECT_DB_CA_PEM:ca,
  AUTH_PROJECT_ID:profile.id,AUTH_SMS_ENABLED:'true',AUTH_WHATSAPP_ENABLED:'false',AUTH_PHONE_DELIVERY_MODE:'opensms_hook',
  AUTH_SEND_SMS_SECRET:'v1,whsec_'+secret.toString('base64'),OPENSMS_BASE_URL:profile.supabase_origin+'/functions/v1/collect-sms',
  OPENSMS_APPLICATION_ID:'collect_auth',OPENSMS_APPLICATION_TOKEN:'app_'+'s'.repeat(40),OPENSMS_DISPATCH_TTL_SECONDS:'120'};
}
function request({signed=true}={}){
 const body=JSON.stringify({user:{id:'11111111-1111-4111-8111-111111111111'},sms:{phone:'250788000002',otp:'123456'}}),
  id='synthetic_event',stamp=String(NOW/1000);
 return new Request(profile.supabase_origin+'/functions/v1/send-sms-hook',{method:'POST',headers:{'Content-Type':'application/json',
  ...(signed?{'webhook-id':id,'webhook-timestamp':stamp,'webhook-signature':'v1,'+createHmac('sha256',secret).update(id+'.'+stamp+'.'+body).digest('base64')}:{})},body});
}
function fakeEffects(t,{deploymentAllowed=true}={}){
 const trace=[],constructors=[],outbound=[];let admission;
 let releasedResolve;const released=new Promise(resolve=>{releasedResolve=resolve;});
 function transaction(){
  const tx=async(strings,...values)=>{
   const query=strings.join('?').trim();
   if(query==='SET LOCAL ROLE collect_runtime'){trace.push('deployment_role');return [];}
   if(query.includes('private.collect_assert_deployment')){
    assert.deepEqual(values,[profileHash]);trace.push('deployment_check');return [{allowed:deploymentAllowed}];
   }
   throw Error('Unexpected synthetic tagged SQL');
  };
  tx.unsafe=async(query,values=[])=>{
   if(query.includes('private.collect_fence_register')){
    const [id,hash,kind]=values;trace.push('register');
    admission={contractVersion:1,admissionId:id,sourceSha256:hash,kind,epoch:1,state:'active',mode:'open'};
    return [{result:{...admission}}];
   }
   if(query.includes('private.collect_fence_assert_work')){
    assert.deepEqual(values,[admission.admissionId,1,source]);trace.push('assert');return [{result:{...admission}}];
   }
   if(query.includes('private.collect_fence_close')){
    const [id,epoch,hash,state,reason,externalDispatches,uncertainDispatches]=values;
    assert.deepEqual([id,epoch,hash],[admission.admissionId,1,source]);trace.push('close');
    admission={...admission,state,reason,externalDispatches,uncertainDispatches};return [{result:{...admission}}];
   }
   if(query==='ROLLBACK'){trace.push('rollback');return [];}
   if(query.startsWith('BEGIN ')||query.startsWith('SET LOCAL ')||query.includes('pg_catalog.set_config')||query.includes('pg_advisory_xact_lock_shared'))return [];
   throw Error('Unexpected synthetic unsafe SQL');
  };
  tx.release=()=>{trace.push('release');releasedResolve();};
  return tx;
 }
 t.mock.method(globalThis,'__collectFencePostgresFixture',(target,options)=>{
  constructors.push({target,options});
  return {async begin(...args){return args.at(-1)(transaction());},async reserve(){return transaction();},async end(){}};
 });
 t.mock.method(globalThis,'fetch',async(input,options)=>{
  const url=new URL(String(input));assert.equal(url.origin,profile.supabase_origin);
  assert(url.pathname.startsWith('/functions/v1/collect-sms/v1/messages'));
  assert.equal(options.redirect,'error');outbound.push(options.method);
  if(options.method==='GET')return new Response(null,{status:404});
  assert.equal(options.method,'POST');const body=JSON.parse(options.body);
  assert.equal(body.kind,'otp');assert.equal(body.to,'+250788000002');
  return Response.json({message_id:body.message_id,state:'accepted'},{status:202});
 });
 return {trace,constructors,outbound,released};
}
function handler(env){return createCollectSendSmsHandler(()=>({...env}),{handlerOptions:{now:()=>NOW}});}

test('database-only normalization preserves managed and self-hosted runtime behavior without service keys',()=>{
 const local=settings(),plain=local.COLLECT_DATABASE_URL;
 assert.equal(normalizeDatabaseTarget({...local,COLLECT_DATABASE_URL:plain+'?sslmode=verify-full'}),plain);
 for(const mode of ['require','prefer','disable'])assert.throws(()=>normalizeDatabaseTarget({...local,COLLECT_DATABASE_URL:plain+'?sslmode='+mode}));
 const localInput={...local,COLLECT_DATABASE_URL:plain+'?sslmode=verify-full',SUPABASE_PUBLISHABLE_KEY:publicKey,SUPABASE_SECRET_KEY:serviceKey};
 assert.deepEqual(normalizeRuntimeEnv(localInput),{...localInput,COLLECT_DATABASE_URL:plain,
  ADMIN_ORIGIN:profile.admin_origin,ADMIN_ORIGINS:profile.admin_origin,
  ALLOWED_ORIGINS:[profile.admin_origin,profile.member_api_origin,profile.public_origin].join(','),
  SUPABASE_AUTH_ISSUER:profile.supabase_origin+'/auth/v1',SUPABASE_INTERNAL_URL:profile.supabase_origin,SUPABASE_SERVICE_ROLE_KEY:serviceKey});
 const managedUrl=`postgres://postgres:synthetic@db.${COLLECT_PROJECT_REF}.supabase.co:5432/postgres`;
 for(const mode of ['verify-full','require','prefer']){
  const injected={SUPABASE_URL:COLLECT_SUPABASE_ORIGIN,SUPABASE_DB_URL:managedUrl+'?sslmode='+mode};
  assert.equal(normalizeDatabaseTarget(injected),managedUrl);
  const input={...injected,SUPABASE_PUBLISHABLE_KEY:publicKey,SUPABASE_SECRET_KEY:serviceKey};
  assert.deepEqual(normalizeRuntimeEnv(input),{...input,COLLECT_DATABASE_URL:managedUrl,
   SUPABASE_AUTH_ISSUER:COLLECT_SUPABASE_ORIGIN+'/auth/v1',SUPABASE_INTERNAL_URL:COLLECT_SUPABASE_ORIGIN,SUPABASE_SERVICE_ROLE_KEY:serviceKey});
  assert.equal(normalizeDatabaseTarget({...injected,COLLECT_DATABASE_URL:managedUrl+'?sslmode=verify-full'}),managedUrl);
  for(const explicitMode of ['require','prefer'])assert.throws(()=>normalizeDatabaseTarget({...injected,COLLECT_DATABASE_URL:managedUrl+'?sslmode='+explicitMode}));
 }
 const fixture={APP_ENVIRONMENT:'test',SUPABASE_URL:'https://fixture.example',COLLECT_DATABASE_URL:'postgres://fixture:synthetic@127.0.0.1:55439/collect_edge_test'};
 assert.equal(normalizeDatabaseTarget(fixture),fixture.COLLECT_DATABASE_URL);
 assert.throws(()=>normalizeDatabaseTarget({...local,COLLECT_DATABASE_URL:fixture.COLLECT_DATABASE_URL}));
});

test('the real hook refuses invalid database targets before connector or provider construction',async t=>{
 const effects=fakeEffects(t),env=settings(),base=env.COLLECT_DATABASE_URL;
 const cases=[
  {COLLECT_DATABASE_URL:undefined},{COLLECT_DATABASE_URL:undefined,SUPABASE_DB_URL:base},{COLLECT_DATABASE_URL:''},
  {COLLECT_DATABASE_URL:base.replace('@db:','@external.example:')},
  {COLLECT_DATABASE_URL:base.replace('@db:','@127.0.0.1:')},
  {COLLECT_DATABASE_URL:base.replace('collect_edge:','postgres:')},
  {COLLECT_DATABASE_URL:base.replace(/:synthetic_\d+@/,'@')},{COLLECT_DATABASE_URL:base.replace('postgres:','http:')},
  {COLLECT_DATABASE_URL:base.replace(':5432/',':6543/')},{COLLECT_DATABASE_URL:base.replace('/postgres','/other')},
  {COLLECT_DATABASE_URL:base+'?sslmode=disable'},{COLLECT_DATABASE_URL:base+'?sslmode=require'},
  {COLLECT_DATABASE_URL:base+'?sslmode=prefer'},{COLLECT_DATABASE_URL:base+'?host=other.example'},
  {COLLECT_DATABASE_URL:base+'?sslmode=verify-full&sslmode=verify-full'},{COLLECT_DATABASE_URL:base+'?sslrootcert=/tmp/ca'},
  {COLLECT_DB_CA_PEM:undefined},{COLLECT_DB_CA_PEM:''},{COLLECT_DB_CA_PEM:'-----BEGIN CERTIFICATE-----\nnot-valid!\n-----END CERTIFICATE-----'},
  {COLLECT_DEPLOYMENT_PROFILE_SHA256:'0'.repeat(64)},
  {APP_ENVIRONMENT:'test',COLLECT_DATABASE_URL:'postgres://fixture:synthetic@127.0.0.1:55439/collect_edge_test'},
 ];
 for(const changes of cases){
  const response=await handler({...env,...changes})(request());
  assert.equal(response.status,503,JSON.stringify(Object.keys(changes)));
  const body=await response.text();assert(!body.includes('synthetic_'));assert(!body.includes('app_'));
  assert.deepEqual(effects.constructors,[]);assert.deepEqual(effects.trace,[]);assert.deepEqual(effects.outbound,[]);
 }
 const unsigned=await handler({...env,COLLECT_DATABASE_URL:base.replace('@db:','@external.example:')})(request({signed:false}));
 assert.equal(unsigned.status,401);assert.deepEqual(effects.constructors,[]);assert.deepEqual(effects.outbound,[]);
});

test('a valid hook target is normalized, verified and fenced before synthetic transport',async t=>{
 const effects=fakeEffects(t),env=settings(),target=env.COLLECT_DATABASE_URL;
 const response=await handler({...env,COLLECT_DATABASE_URL:target+'?sslmode=verify-full'})(request());
 assert.equal(response.status,200);assert.deepEqual(await response.json(),{});
 await effects.released;
 assert.equal(effects.constructors.length,2);
 for(const entry of effects.constructors){
  assert.equal(entry.target,target);assert.deepEqual(entry.options.ssl,{rejectUnauthorized:true,ca,servername:'db'});
 }
 assert.deepEqual(effects.outbound,['GET','POST']);
 for(const event of ['deployment_check','register','assert'])assert(effects.trace.includes(event),event);
 assert(effects.trace.indexOf('deployment_check')<effects.trace.indexOf('register'));
 assert(effects.trace.indexOf('register')<effects.trace.indexOf('assert'));
 assert(effects.trace.includes('close'));assert(effects.trace.includes('release'));
});

test('a mismatched database deployment cannot admit work or reach the synthetic provider',async t=>{
 const effects=fakeEffects(t,{deploymentAllowed:false}),env=settings();
 const response=await handler(env)(request());assert.equal(response.status,503);
 assert.equal(effects.constructors.length,1);assert.deepEqual(effects.trace,['deployment_role','deployment_check']);
 assert.deepEqual(effects.outbound,[]);
});
