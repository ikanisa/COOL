import {fencedTest} from './helpers/fenced-unit.js';
import {assertEquals, assertThrows, assertRejects} from 'jsr:@std/assert@1.0.14';
import {compileSql,PostgresDatabase} from './helpers/fenced-postgres.js';
import {logicalRequest,createHandler,createScheduledHandler,runtimeFailureEvent,requestTransportProfile} from './helpers/fenced-handler.js';
import {validateAdminOrigin} from './helpers/module-admin-security.js';
import {operationInventory} from '../domain/operations.js';
import {normalizeRuntimeEnv,isGoogleProviderNavigation,COLLECT_SUPABASE_ORIGIN,COLLECT_PROJECT_REF} from '../runtime-env.js';
import {callbackResult} from '../domain/google_auth.js';
import {createHandler as actualRuntimeHandler} from '../serve.js';
import {createPlatformHealthReporter} from '../domain/observability.js';
import {verifyToken} from './helpers/module-auth-http.js';
fencedTest('actual default Deno environment readers admit preflight and deny unauthenticated jobs',async()=>{
 const preflight=await createHandler('collect-api')(new Request(COLLECT_SUPABASE_ORIGIN+'/functions/v1/collect-api/health',{method:'OPTIONS'}));
 assertEquals(preflight.status,204);
 const unauthenticatedJob=await createScheduledHandler()(new Request(COLLECT_SUPABASE_ORIGIN+'/functions/v1/collect-jobs',{method:'POST'}));
 assertEquals(unauthenticatedJob.status,401);
});
fencedTest('runtime failure diagnostics retain only bounded stages, known reasons and presence flags',async()=>{
 const credential='fixture-secret-must-never-be-logged',env={SUPABASE_URL:'https://example.test',SUPABASE_DB_URL:'postgres://operator:'+credential+'@db.example.test/postgres',SUPABASE_SECRET_KEYS:credential};
 const unknown=runtimeFailureEvent(new Error('Connection rejected '+env.SUPABASE_DB_URL),credential,env);
 assertEquals(unknown.stage,'unknown');assertEquals(unknown.reason,'unclassified');
 assertEquals(unknown.configured,{supabase_origin:true,injected_database:true,custom_database:false,publishable_dictionary:false,secret_dictionary:true});
 assertEquals(JSON.stringify(unknown).includes(credential),false);
 const known=runtimeFailureEvent(new Error('Database connection overrides are not permitted'),'normalization',env);
 assertEquals(known.stage,'normalization');assertEquals(known.reason,'database_overrides_rejected');
 assertEquals(JSON.stringify(known).includes(credential),false);
 assertEquals(known.database_profile,{parameter_count:0,parameters:[],ssl_modes:[],host:'other',port:'other'});
 const profile=runtimeFailureEvent(new Error('Database connection overrides are not permitted'),'normalization',{...env,SUPABASE_DB_URL:env.SUPABASE_DB_URL+'?sslmode='+credential+'&'+credential+'='+credential+'&options='+credential});
 assertEquals(profile.database_profile,{parameter_count:3,parameters:['options','other','sslmode'],ssl_modes:['other'],host:'other',port:'other'});assertEquals(JSON.stringify(profile).includes(credential),false);
 const originalLogger=console.error,captured:unknown[][]=[];
 try{
  console.error=(...args:unknown[])=>{captured.push(args);};
  const reporter=createPlatformHealthReporter();
  const handler=actualRuntimeHandler('collect-api',()=>{throw new Error('Connection rejected '+credential);},{reportHealth:reporter});
  const response=await handler(new Request(COLLECT_SUPABASE_ORIGIN+'/functions/v1/collect-api/health?probe='+credential,{headers:{Authorization:'Bearer '+credential}}));
  const body=await response.json();assertEquals(response.status,503);assertEquals(body.code,'backend_unavailable');
  assertEquals(body.message,'The backend is unavailable.');assertEquals(/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(body.request_id),true);
  assertEquals(JSON.stringify(body).includes(credential),false);assertEquals(captured.length,1);
  assertEquals(captured[0].length,1);assertEquals(typeof captured[0][0],'string');
  const event=JSON.parse(String(captured[0][0]));
  assertEquals(event.request_id,body.request_id);assertEquals(Number.isInteger(event.elapsed_ms)&&event.elapsed_ms>=0&&event.elapsed_ms<=3600000,true);
  assertEquals(event,{service:'collect_platform_api',schema_version:1,event:'runtime_unavailable',component:'platform',status:503,request_id:body.request_id,source_id:'unknown',elapsed_ms:event.elapsed_ms,stage:'environment',reason:'unclassified',configured:{supabase_origin:false,injected_database:false,custom_database:false,publishable_dictionary:false,secret_dictionary:false}});
  assertEquals(JSON.stringify(captured).includes(credential),false);
 }finally{console.error=originalLogger;}
});
fencedTest('transport rejection profiles expose only closed request transport classes',()=>{
 const secret='synthetic-credential-never-log',request=new Request('http://'+COLLECT_PROJECT_REF+'.supabase.co/functions/v1/admin-api/api/admin/auth/session?'+secret+'='+secret,{headers:{Authorization:'Bearer '+secret,Origin:'https://'+secret+'.example','Sec-Fetch-Site':secret}});
 const profile=requestTransportProfile(request);assertEquals(profile,{protocol:'http:',host:'project',port:'',sec_fetch_site:'other',origin_present:true});assertEquals(JSON.stringify(profile).includes(secret),false);
});
fencedTest('operation dispatch keeps all 93 registered current product operations',()=>{
 assertEquals(operationInventory.length,93);assertEquals(new Set(operationInventory.map(v=>v.path)).size,93);
});
fencedTest('SQL parameterization never rewrites question marks inside quoted literals',()=>{
 assertEquals(compileSql("SELECT '?' AS literal,? AS value, 'it''s ?' AS escaped",['binding']),{text:"SELECT '?' AS literal,$1 AS value, 'it''s ?' AS escaped",values:['binding']});
 assertThrows(()=>compileSql('SELECT ?',[]));
});
fencedTest('NULL-safe SQL comparisons preserve source semantics',()=>{
 assertEquals(compileSql('SELECT mfa_at IS ? AND factor IS NOT ?',[null,'factor']).text,'SELECT mfa_at IS NOT DISTINCT FROM $1 AND factor IS DISTINCT FROM $2');
});
fencedTest('prefix translation preserves logical method,path,query and strips spoofed authority',()=>{
 const r=logicalRequest(new Request('https://backend.example/functions/v1/collect-api/v1/rpc/create_contribution_intent?x=1',{method:'POST',headers:{'X-Collect-Actor':'spoofed','X-Collect-Original-Path':'/bad','Content-Type':'application/json'},body:'{"p_request_id":"unchanged"}'}),'collect-api');
 assertEquals(new URL(r.url).pathname,'/v1/rpc/create_contribution_intent');assertEquals(r.method,'POST');assertEquals(new URL(r.url).search,'?x=1');assertEquals(r.headers.get('X-Collect-Actor'),null);
});
fencedTest('hosted project internal HTTP scheme restores the fixed HTTPS contract without trusting forwarded headers',async()=>{
 const origin='https://admin.example',env={SUPABASE_URL:COLLECT_SUPABASE_ORIGIN,SUPABASE_PUBLISHABLE_KEY:'synthetic-public',SUPABASE_SECRET_KEY:'synthetic-secret',APP_ENVIRONMENT:'test',COLLECT_DATABASE_URL:'postgres://fixture:synthetic@127.0.0.1:55439/collect_edge_test',ADMIN_ORIGIN:origin},handler=createHandler('admin-api',()=>({...env}));
 const path='/functions/v1/admin-api/api/admin/auth/session';
 const internal=new Request('http://'+COLLECT_PROJECT_REF+'.supabase.co'+path,{headers:{Origin:origin,'X-Forwarded-Proto':'http'}});
 assertEquals(logicalRequest(internal,'admin-api').url,COLLECT_SUPABASE_ORIGIN+'/api/admin/auth/session');
 const admitted=await handler(internal);assertEquals(admitted.status,200);assertEquals(await admitted.json(),{user:null,expiresAt:null,csrfToken:null,ownerEmail:'info@ikanisa.com'});
 for(const host of ['other.supabase.co',COLLECT_PROJECT_REF+'.supabase.co:8080']){
  const request=new Request('http://'+host+path,{headers:{Origin:origin,'X-Forwarded-Proto':'https'}});
  assertEquals(new URL(logicalRequest(request,'admin-api').url).protocol,'http:');assertEquals((await handler(request)).status,403);
 }
 const crossSite=new Request('http://'+COLLECT_PROJECT_REF+'.supabase.co'+path,{headers:{Origin:origin,'Sec-Fetch-Site':'cross-site'}});assertEquals((await handler(crossSite)).status,403);
});
fencedTest('Admin exact origin, non-simple header and content type block forged mutations',()=>{
 const env={ADMIN_ORIGIN:'https://admin.example'};
 assertThrows(()=>validateAdminOrigin(new Request('https://backend.example/api/admin/auth/login',{method:'POST',headers:{Origin:'https://evil.example','Content-Type':'application/json','X-Collect-Requested-With':'collect-admin'},body:'{}'}),env));
 assertThrows(()=>validateAdminOrigin(new Request('https://backend.example/api/admin/auth/login',{method:'POST',headers:{Origin:'https://admin.example','Content-Type':'text/plain'},body:'{}'}),env));
 assertEquals(validateAdminOrigin(new Request('https://backend.example/api/admin/auth/login',{method:'POST',headers:{Origin:'https://admin.example','Content-Type':'application/json','X-Collect-Requested-With':'collect-admin'},body:'{}'}),env),'https://admin.example');
});
fencedTest('API keys cannot be interpreted as verified user tokens',async()=>{
 await assertRejects(()=>verifyToken({},'sb_publishable_non_user'));await assertRejects(()=>verifyToken({},'sb_secret_non_user'));
});
fencedTest('credentialed CORS is exact and preflight exposes required client headers only',async()=>{
 const handler=createHandler('admin-api',()=>({ADMIN_ORIGIN:'https://admin.example'}));
 const response=await handler(new Request('https://backend.example/functions/v1/admin-api/api/admin/auth/session',{method:'OPTIONS',headers:{Origin:'https://admin.example'}}));
 assertEquals(response.status,204);assertEquals(response.headers.get('Access-Control-Allow-Headers')?.includes('X-Collect-Admin'),true);assertEquals(response.headers.get('Access-Control-Allow-Origin'),'https://admin.example');assertEquals(response.headers.get('Access-Control-Allow-Credentials'),'true');assertEquals(response.headers.get('Access-Control-Expose-Headers'),'X-Collect-Evidence-Sensitivity');
 const denied=await handler(new Request('https://backend.example/functions/v1/admin-api/api/admin/auth/session',{method:'OPTIONS',headers:{Origin:'https://evil.example'}}));assertEquals(denied.status,403);
});

fencedTest('qualified challenge/privacy HTML retains CSP and explicit renderer markers',async()=>{
 const handler=createHandler('collect-api',()=>({SUPABASE_URL:'https://project.example',SUPABASE_SERVICE_ROLE_KEY:'sb_secret_synthetic',SUPABASE_PUBLISHABLE_KEY:'synthetic-public-key',APP_ENVIRONMENT:'test',COLLECT_DATABASE_URL:'postgres://fixture:fixture@127.0.0.1:55439/collect_edge_test',TURNSTILE_SITE_KEY:'synthetic-site-key-12345',ALLOWED_ORIGINS:'https://member.example',ADMIN_ORIGIN:'https://admin.example'}));
 for(const [path,marker]of [['/v1/security/challenge?attempt_id=00000000-0000-4000-8000-000000000001&parent_origin=https%3A%2F%2Fadmin.example','collect.turnstile.v1'],['/privacy/account-deletion','collect.privacy.portal.v1'],['/privacy/account-deletion/','collect.privacy.portal.v1']]){const response=await handler(new Request('https://project.example/functions/v1/collect-api'+path));assertEquals(response.status,200);assertEquals(response.headers.get('X-Collect-Document'),marker);assertEquals(Boolean(response.headers.get('Content-Security-Policy')),true);}
 const denied=await handler(new Request('https://project.example/functions/v1/collect-api/v1/security/challenge'));assertEquals(denied.headers.get('X-Collect-Document'),null);
});

fencedTest('Google callback exports only transient handoff with qualified renderer/redirect contract',async()=>{
 const code='a'.repeat(43),state='b'.repeat(43),browser=callbackResult({return_origin:'https://member.example'},{code,state});assertEquals(browser.status,200);assertEquals(browser.headers.get('X-Collect-Document'),'collect.google.callback.v1');assertEquals(Boolean(browser.headers.get('Content-Security-Policy')),true);const html=await browser.text();assertEquals(html.includes('access_token'),false);assertEquals(html.includes('refresh_token'),false);
 const native=callbackResult({return_origin:null},{code,state});assertEquals(native.status,302);assertEquals(native.headers.get('X-Collect-Document'),'collect.google.native.v1');const url=new URL(native.headers.get('Location')!);assertEquals(url.protocol,'collect:');assertEquals(url.hostname,'auth');assertEquals(url.pathname,'/google');assertEquals([...url.searchParams.keys()],['code','state']);
});

fencedTest('documented Supabase runtime dictionaries normalize keys and retain nominated database identity',()=>{
 const input={SUPABASE_URL:COLLECT_SUPABASE_ORIGIN,SUPABASE_DB_URL:'postgres://postgres:synthetic@db.'+COLLECT_PROJECT_REF+'.supabase.co:5432/postgres',SUPABASE_PUBLISHABLE_KEYS:JSON.stringify({default:'sb_publishable_synthetic'}),SUPABASE_SECRET_KEYS:JSON.stringify({default:'sb_secret_synthetic'}),SUPABASE_ANON_KEY:'eyJlegacy.old.signature',SUPABASE_SERVICE_ROLE_KEY:'eyJlegacy.old.signature'};
 const env=normalizeRuntimeEnv(input);assertEquals(env.COLLECT_DATABASE_URL,input.SUPABASE_DB_URL);assertEquals(env.SUPABASE_PUBLISHABLE_KEY,'sb_publishable_synthetic');assertEquals(env.SUPABASE_SERVICE_ROLE_KEY,'sb_secret_synthetic');assertEquals(env.SUPABASE_SECRET_KEY,'sb_secret_synthetic');
 for(const patch of [{SUPABASE_URL:'https://another.supabase.co'},{SUPABASE_DB_URL:'postgres://postgres:synthetic@db.another.supabase.co:5432/postgres'},{SUPABASE_SECRET_KEYS:'{bad'},{SUPABASE_PUBLISHABLE_KEYS:'{}'},{SUPABASE_SECRET_KEY:''},{SUPABASE_DB_URL:input.SUPABASE_DB_URL+'?sslmode=disable'}])assertThrows(()=>normalizeRuntimeEnv({...input,...patch}));
 assertThrows(()=>normalizeRuntimeEnv({SUPABASE_URL:COLLECT_SUPABASE_ORIGIN}));
 for(const option of ['host=other.example','user=other','database=other','sslmode=no-verify','sslmode=verify-full&sslmode=verify-full','options=-csearch_path=other'])assertThrows(()=>normalizeRuntimeEnv({...input,SUPABASE_DB_URL:input.SUPABASE_DB_URL+'?'+option}));
 assertEquals(normalizeRuntimeEnv({...input,SUPABASE_DB_URL:input.SUPABASE_DB_URL+'?sslmode=verify-full'}).COLLECT_DATABASE_URL,input.SUPABASE_DB_URL);
 assertEquals(normalizeRuntimeEnv({...input,SUPABASE_DB_URL:input.SUPABASE_DB_URL+'?sslmode=require'}).COLLECT_DATABASE_URL,input.SUPABASE_DB_URL);
 assertThrows(()=>normalizeRuntimeEnv({...input,COLLECT_DATABASE_URL:input.SUPABASE_DB_URL+'?sslmode=require'}));
 assertEquals(normalizeRuntimeEnv({...input,SUPABASE_DB_URL:input.SUPABASE_DB_URL+'?sslmode=prefer'}).COLLECT_DATABASE_URL,input.SUPABASE_DB_URL);
 assertThrows(()=>normalizeRuntimeEnv({...input,COLLECT_DATABASE_URL:input.SUPABASE_DB_URL+'?sslmode=prefer'}));
 for(const option of ['sslmode=disable','sslmode=allow','sslmode=require&host=other.example','sslmode=require&sslmode=require','sslmode=require&sslrootcert=/tmp/ca'])assertThrows(()=>normalizeRuntimeEnv({...input,SUPABASE_DB_URL:input.SUPABASE_DB_URL+'?'+option}));
 const {SUPABASE_SECRET_KEYS:_secret,SUPABASE_PUBLISHABLE_KEYS:_public,...legacy}=input;assertEquals(normalizeRuntimeEnv(legacy).SUPABASE_SECRET_KEY,'eyJlegacy.old.signature');
 const fixture=normalizeRuntimeEnv({APP_ENVIRONMENT:'test',SUPABASE_URL:'https://fixture.example',COLLECT_DATABASE_URL:'postgres://fixture:synthetic@127.0.0.1:55439/collect_edge_test',SUPABASE_PUBLISHABLE_KEY:'synthetic-public',SUPABASE_SECRET_KEY:'synthetic-secret'});assertEquals(fixture.SUPABASE_URL,'https://fixture.example');
});

fencedTest('provider callback Origin exception is exact navigation-only and does not expand API CORS',()=>{
 const request=(path:string,mode='navigate',dest='document',method='GET')=>new Request('https://backend.example'+path,{method,headers:{Origin:COLLECT_SUPABASE_ORIGIN,'Sec-Fetch-Mode':mode,'Sec-Fetch-Dest':dest}});
 assertEquals(isGoogleProviderNavigation(request('/v1/auth/google/callback')),true);assertEquals(isGoogleProviderNavigation(request('/v1/auth/google/exchange')),false);assertEquals(isGoogleProviderNavigation(request('/v1/auth/google/callback','cors','empty')),false);assertEquals(isGoogleProviderNavigation(request('/v1/auth/google/callback','navigate','document','POST')),false);
});

fencedTest('scheduled auth cleanup has separate failure status while receipt processing is paused',async()=>{
 const env={SUPABASE_URL:'https://fixture.example',COLLECT_DATABASE_URL:'postgres://fixture:synthetic@127.0.0.1:55439/collect_edge_test',SUPABASE_PUBLISHABLE_KEY:'synthetic-public',SUPABASE_SECRET_KEY:'synthetic-secret',APP_ENVIRONMENT:'test',COLLECT_JOB_TOKEN:'synthetic-job-token',MOMO_PROCESSING_PAUSED:'true'};let called=0;
 const handler=createScheduledHandler(()=>env,async()=>{called++;throw new Error('synthetic lost SQL reply');});const response=await handler(new Request('https://backend.example/functions/v1/collect-jobs',{method:'POST',headers:{Authorization:'Bearer '+env.COLLECT_JOB_TOKEN}})),body=await response.json();assertEquals(response.status,503);assertEquals(called,1);assertEquals(body.maintenance.status,'unconfirmed');assertEquals(body.processing.paused,true);
 const denied=await handler(new Request('https://backend.example/functions/v1/collect-jobs',{method:'POST'}));assertEquals(denied.status,401);assertEquals(called,1);
});

fencedTest('authenticated jobs echo the exact bounded opaque dispatch id and reject other payloads before work',async()=>{
 const env={SUPABASE_URL:'https://fixture.example',COLLECT_DATABASE_URL:'postgres://fixture:synthetic@127.0.0.1:55439/collect_edge_test',SUPABASE_PUBLISHABLE_KEY:'synthetic-public',SUPABASE_SECRET_KEY:'synthetic-secret',APP_ENVIRONMENT:'test',COLLECT_JOB_TOKEN:'synthetic-job-token',MOMO_PROCESSING_PAUSED:'true'};
 let called=0;const handler=createScheduledHandler(()=>env,async()=>{called++;return {status:'complete',examined_limit:100,purged:0,provider_calls:0};});
 const id=crypto.randomUUID(),send=(body:unknown)=>handler(new Request('https://backend.example/functions/v1/collect-jobs',{method:'POST',headers:{Authorization:'Bearer '+env.COLLECT_JOB_TOKEN,'Content-Type':'application/json'},body:JSON.stringify(body)}));
 const response=await send({dispatch_id:id}),body=await response.json();assertEquals(response.status,200);assertEquals(body.dispatch_id,id);assertEquals(called,1);
 for(const payload of [{dispatch_id:'not-a-uuid'},{dispatch_id:id,unexpected:true},{dispatch_id:'x'.repeat(256)},[]]){const denied=await send(payload);assertEquals([400,413].includes(denied.status),true);assertEquals(called,1);}
 const direct=await send({});assertEquals(direct.status,200);assertEquals(Object.hasOwn(await direct.json(),'dispatch_id'),false);assertEquals(called,2);
});

fencedTest('maintenance scheduler refuses changed pause settings before receipt admission',async()=>{
 const base={SUPABASE_URL:'https://fixture.example',COLLECT_DATABASE_URL:'postgres://fixture:synthetic@127.0.0.1:55439/collect_edge_test',SUPABASE_PUBLISHABLE_KEY:'synthetic-public',SUPABASE_SECRET_KEY:'synthetic-secret',APP_ENVIRONMENT:'test',COLLECT_JOB_TOKEN:'synthetic-job-token'};
 let receiptCalls=0;for(const paused of ['false','TRUE','typo','']){
  const handler=createScheduledHandler(()=>({...base,MOMO_PROCESSING_PAUSED:paused}),async()=>({status:'complete',examined_limit:100,purged:0,provider_calls:0}),async()=>{receiptCalls++;throw Error('Receipt queue must remain untouched');});
  const dispatch=crypto.randomUUID(),response=await handler(new Request('https://backend.example/functions/v1/collect-jobs',{method:'POST',headers:{Authorization:'Bearer '+base.COLLECT_JOB_TOKEN,'Content-Type':'application/json'},body:JSON.stringify({dispatch_id:dispatch})})),body=await response.json();
  assertEquals(response.status,503);assertEquals(body.dispatch_id,dispatch);assertEquals(body.processing.code,'maintenance_gate_changed');assertEquals(receiptCalls,0);
 }
});
