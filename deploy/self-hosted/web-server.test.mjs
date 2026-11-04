import test from 'node:test';import assert from 'node:assert/strict';
import {mkdtemp,mkdir,writeFile,symlink,rm} from 'node:fs/promises';import {tmpdir} from 'node:os';import {join} from 'node:path';import {createHash} from 'node:crypto';
import {createWebApplication,serveWeb,staticAssets,validRawTarget} from './web-server.mjs';
import http from 'node:http';import {Readable,Writable} from 'node:stream';
import {workerEnvironment} from './edge-main/environment.mjs';
import {canonicalProfile} from '../../supabase/functions/_shared/deployment-profile.js';
const profile={format:'collect.deployment.v1',id:'qualification',mode:'self_hosted',environment:'qualification',supabase_origin:'https://supabase.collect.example',admin_origin:'https://admin.collect.example',member_api_origin:'https://api.collect.example',public_origin:'https://collect.example',google_callback_origin:'https://admin.collect.example'};
const raw=canonicalProfile(profile),env={COLLECT_DEPLOYMENT_PROFILE:raw,COLLECT_DEPLOYMENT_PROFILE_SHA256:createHash('sha256').update(raw).digest('hex'),APP_ENVIRONMENT:'qualification',SUPABASE_URL:profile.supabase_origin,SUPABASE_INTERNAL_URL:'http://api-gw:8000',AUTH_PHONE_DELIVERY_MODE:'opensms_hook',AUTH_WHATSAPP_ENABLED:'false'};

test('raw HTTP aliases are refused before URL normalization',()=>{
 for(const path of ['/auth/v1/user','/auth/v1/callback?code=a%2Fb','/.well-known/assetlinks.json'])assert.equal(validRawTarget(path),true);
 for(const path of ['//elsewhere/auth/v1/user','https://elsewhere/auth/v1/user','/x/../auth/v1/user','/auth/%2ev1/user','/auth%2fv1/user','/auth\\v1/user','/auth/v1/%5cuser','/auth/v1/%00user','/bad path'])assert.equal(validRawTarget(path),false,path);
});
test('static serving isolates files, preserves association files and blocks arbitrary hidden files',async()=>{
 const folder=await mkdtemp(join(tmpdir(),'collect-web-'));
 try{
  await writeFile(join(folder,'index.html'),'<main>Collect</main>');await mkdir(join(folder,'.well-known'));await writeFile(join(folder,'.well-known/assetlinks.json'),'[]');await writeFile(join(folder,'.secret'),'private');await symlink('/etc/passwd',join(folder,'escape'));
  const assets=staticAssets(folder);
  for(const path of ['/.secret','/escape','/missing.js','/source.js.map'])assert.equal((await assets.fetch(new Request('https://collect.example'+path))).status,404);
  const association=await assets.fetch(new Request('https://collect.example/.well-known/assetlinks.json'));assert.equal(association.status,200);assert.equal(association.headers.get('Content-Type'),'application/json');
  const fallback=await assets.fetch(new Request('https://collect.example/account',{headers:{Accept:'text/html'}}));assert.equal(await fallback.text(),'<main>Collect</main>');assert.match(fallback.headers.get('Cache-Control'),/no-store/);
  assert.equal((await assets.fetch(new Request('https://collect.example/',{method:'HEAD'}))).body,null);
 }finally{await rm(folder,{recursive:true,force:true});}
});
test('public directory indexes are isolated from Admin and retain static-file protections',async()=>{
 const folder=await mkdtemp(join(tmpdir(),'collect-web-directory-'));
 try{
  const admin=join(folder,'admin'),publicSite=join(folder,'public'),outside=join(folder,'outside');
  await mkdir(admin);await mkdir(publicSite);await mkdir(outside);
  await writeFile(join(admin,'index.html'),'ADMIN-ROOT');await mkdir(join(admin,'privacy'));await writeFile(join(admin,'privacy/index.html'),'ADMIN-PRIVATE-DIRECTORY');
  await writeFile(join(publicSite,'index.html'),'PUBLIC-ROOT');await mkdir(join(publicSite,'privacy'));await writeFile(join(publicSite,'privacy/index.html'),'PUBLIC-PRIVACY');
  await mkdir(join(publicSite,'privacy/terms'));await writeFile(join(publicSite,'privacy/terms/index.html'),'PUBLIC-TERMS');
  await mkdir(join(publicSite,'empty'));await mkdir(join(publicSite,'.hidden'));await writeFile(join(publicSite,'.hidden/index.html'),'HIDDEN-MARKER');
  await mkdir(join(publicSite,'.well-known'));await writeFile(join(publicSite,'.well-known/assetlinks.json'),'ASSET-LINKS');await writeFile(join(publicSite,'.well-known/apple-app-site-association'),'APPLE-ASSOCIATION');
  await writeFile(join(publicSite,'visible.txt'),'VISIBLE-FILE');await symlink(join(publicSite,'visible.txt'),join(publicSite,'visible-file-alias'));
  await symlink(join(publicSite,'.hidden/index.html'),join(publicSite,'hidden-file-alias'));
  await symlink(join(publicSite,'.well-known/assetlinks.json'),join(publicSite,'well-known-file-alias'));
  for(const route of ['c','group-link']){
   await mkdir(join(publicSite,route));await writeFile(join(publicSite,route,'index.html'),route+'-INVITATION');
   await mkdir(join(publicSite,route,'slug'));await writeFile(join(publicSite,route,'slug/index.html'),route+'-SLUG');
   await symlink(join(publicSite,route),join(publicSite,route+'-alias'));
   await mkdir(join(publicSite,route+'-index-alias'));await symlink(join(publicSite,route,'index.html'),join(publicSite,route+'-index-alias/index.html'));
  }
  await symlink(join(publicSite,'privacy'),join(publicSite,'c/other-directory'));
  await mkdir(join(publicSite,'c-extra'));await writeFile(join(publicSite,'c-extra/index.html'),'OTHER-PAGE');
  await writeFile(join(outside,'index.html'),'OUTSIDE-MARKER');await symlink(outside,join(publicSite,'outside-directory'));
  await mkdir(join(publicSite,'outside-index'));await symlink(join(outside,'index.html'),join(publicSite,'outside-index/index.html'));
  await symlink(join(publicSite,'.hidden'),join(publicSite,'hidden-directory'));
  await mkdir(join(publicSite,'hidden-index'));await symlink(join(publicSite,'.hidden/index.html'),join(publicSite,'hidden-index/index.html'));
  await symlink(join(publicSite,'privacy'),join(publicSite,'inside-directory'));
  const application=await createWebApplication({...env,COLLECT_ADMIN_ASSET_DIR:admin,COLLECT_PUBLIC_ASSET_DIR:publicSite});
  const request=(origin,path,options={})=>application(new Request(origin+path,options));
  for(const path of ['/privacy','/privacy/']){
   const result=await request(profile.public_origin,path);assert.equal(result.status,200,path);assert.equal(await result.text(),'PUBLIC-PRIVACY');
   assert.match(result.headers.get('Content-Type'),/^text\/html/);assert.match(result.headers.get('Cache-Control'),/no-store/);
   const head=await request(profile.public_origin,path,{method:'HEAD'});assert.equal(head.status,200);assert.equal(head.body,null);
   assert.match(head.headers.get('Content-Type'),/^text\/html/);
  }
  assert.equal(await (await request(profile.public_origin,'/privacy/terms/')).text(),'PUBLIC-TERMS');
  assert.equal(await (await request(profile.public_origin,'/inside-directory')).text(),'PUBLIC-PRIVACY');
  assert.equal(await (await request(profile.public_origin,'/c-extra')).text(),'OTHER-PAGE');
  for(const path of ['/c','/c/','/c///','/%63','/%63/','/c/slug','/c/%73lug','/c%2Fslug','/c/other-directory','/c-alias','/c-alias/slug','/c-index-alias','/group-link','/group-link/','/group%2Dlink','/group-link/slug','/group-link-alias/slug','/group-link-index-alias']){
   const groupRoutes=new Set(['/c/slug','/c/%73lug','/c%2Fslug','/c/other-directory']);
   const plain=await request(profile.public_origin,path);
   assert.equal(plain.status,groupRoutes.has(path)?200:404,path);
   if(groupRoutes.has(path))assert.equal(await plain.text(),'c-INVITATION',path);
   assert.equal(await (await request(profile.public_origin,path,{headers:{Accept:'text/html'}})).text(),groupRoutes.has(path)?'c-INVITATION':'PUBLIC-ROOT',path);
  }
  for(const [path,body] of [['/c/index.html','c-INVITATION'],['/c/slug/index.html','c-SLUG'],['/c-index-alias/index.html','c-INVITATION'],['/group-link/index.html','group-link-INVITATION'],['/group-link/slug/index.html','group-link-SLUG'],['/group-link-index-alias/index.html','group-link-INVITATION']]){
   assert.equal(await (await request(profile.public_origin,path)).text(),body,path);
  }
  assert.equal(await (await request(profile.public_origin,'/visible.txt')).text(),'VISIBLE-FILE');
  assert.equal(await (await request(profile.public_origin,'/visible-file-alias')).text(),'VISIBLE-FILE');
  for(const [path,body] of [['/.well-known/assetlinks.json','ASSET-LINKS'],['/.well-known/apple-app-site-association','APPLE-ASSOCIATION']]){
   const result=await request(profile.public_origin,path);assert.equal(result.status,200);assert.equal(await result.text(),body);assert.equal(result.headers.get('Content-Type'),'application/json');
  }
  for(const path of ['/outside-directory','/outside-index/','/hidden-directory','/hidden-index','/hidden-file-alias','/well-known-file-alias','/.hidden','/privacy%2F..%2F.hidden%2Findex.html','/missing.js','/empty/','/source.js.map']){
   assert.equal((await request(profile.public_origin,path)).status,404,path);
  }
  assert.equal((await request(profile.public_origin,'/hidden-file-alias',{method:'HEAD'})).status,404);
  for(const path of ['/outside-directory','/outside-index/','/hidden-file-alias','/empty/']){
   const result=await request(profile.public_origin,path,{headers:{Accept:'text/html'}});
   assert.equal(await result.text(),'PUBLIC-ROOT',path);
  }
  for(const path of ['/.well-known/assetlinks.json','/.well-known/apple-app-site-association']){
   const file=join(publicSite,path);await rm(file);await symlink(join(publicSite,'.hidden/index.html'),file);
   assert.equal((await request(profile.public_origin,path)).status,404,path);
  }
  await rm(join(publicSite,'.well-known/assetlinks.json'));await symlink(join(publicSite,'visible.txt'),join(publicSite,'.well-known/assetlinks.json'));
  assert.equal(await (await request(profile.public_origin,'/.well-known/assetlinks.json')).text(),'VISIBLE-FILE');
  assert.equal((await request(profile.public_origin,'/privacy',{method:'POST'})).status,405);
  assert.equal((await request(profile.admin_origin,'/privacy')).status,404);
  assert.equal(await (await request(profile.admin_origin,'/privacy',{headers:{Accept:'text/html'}})).text(),'ADMIN-ROOT');
  assert.equal(await (await request(profile.admin_origin,'/privacy/index.html')).text(),'ADMIN-PRIVATE-DIRECTORY');
  assert.equal((await request(profile.member_api_origin,'/privacy')).status,404);
  assert.equal(await (await request(profile.member_api_origin,'/privacy',{headers:{Accept:'text/html'}})).text(),'PUBLIC-ROOT');
  assert.equal(validRawTarget('/privacy/%2e%2e/index.html'),false);
  assert.equal(validRawTarget('/c%2Fslug'),false);assert.equal(validRawTarget('/c/%73lug'),true);
 }finally{await rm(folder,{recursive:true,force:true});}
});
test('public Supabase phone route is filtered and other hosts remain exact',async()=>{
 const app=await createWebApplication(env);
 assert.equal((await app(new Request('https://unknown.example/'))).status,421);
 assert.equal((await app(new Request(profile.supabase_origin+'/rest/v1/users'))).status,404);
 assert.equal((await app(new Request(profile.public_origin+'/api/admin/users'))).status,404);
 const response=await app(new Request(profile.supabase_origin+'/auth/v1/otp',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({phone:'+250780000000'})}));
 assert.equal(response.status,403);assert.equal((await response.json()).code,'phone_requires_collect');
});
test('function environment projection separates privileged backend credentials and delivery lanes',()=>{
 const input={...env,COLLECT_DATABASE_URL:'main-db',COLLECT_SMS_DATABASE_URL:'sms-db',COLLECT_DB_CA_PEM:'ca',ROOT_ADMIN_TOKEN:'sms-root',COLLECT_JOB_TOKEN:'jobs',COLLECT_EMAIL_JOB_TOKEN:'email',AUTH_SEND_SMS_SECRET:'hook',OPENSMS_APPLICATION_TOKEN:'otp',OPENSMS_RECEIPT_APPLICATION_TOKEN:'receipt',SUPABASE_SECRET_KEY:'server',DATA_ENCRYPTION_KEY:'data',SESSION_ENCRYPTION_KEY:'session',JWT_SECRET:'root-jwt',POSTGRES_PASSWORD:'root-db',SMTP_PASS:'smtp',GOOGLE_SECRET:'google',GOTRUE_SMS_TWILIO_AUTH_TOKEN:'twilio'};
 const project=name=>Object.fromEntries(workerEnvironment(name,input));
 const api=project('collect-api'),admin=project('admin-api'),jobs=project('collect-jobs'),email=project('collect-email-jobs'),sms=project('collect-sms'),hook=project('send-sms-hook');
 for(const projected of [api,admin,jobs,email,sms,hook])for(const key of ['JWT_SECRET','POSTGRES_PASSWORD','SMTP_PASS','GOOGLE_SECRET','GOTRUE_SMS_TWILIO_AUTH_TOKEN'])assert.equal(projected[key],undefined,key);
 assert.equal(sms.COLLECT_SMS_DATABASE_URL,'sms-db');assert.equal(sms.COLLECT_DATABASE_URL,undefined);assert.equal(sms.SUPABASE_SECRET_KEY,undefined);
 assert.equal(hook.COLLECT_DATABASE_URL,'main-db');assert.equal(hook.AUTH_SEND_SMS_SECRET,'hook');assert.equal(hook.OPENSMS_APPLICATION_TOKEN,'otp');assert.equal(hook.SUPABASE_SECRET_KEY,undefined);assert.equal(hook.OPENSMS_RECEIPT_APPLICATION_TOKEN,undefined);
 assert.equal(jobs.COLLECT_JOB_TOKEN,'jobs');assert.equal(jobs.COLLECT_EMAIL_JOB_TOKEN,undefined);assert.equal(email.COLLECT_EMAIL_JOB_TOKEN,'email');assert.equal(email.COLLECT_JOB_TOKEN,undefined);
 assert.equal(admin.OPENSMS_RECEIPT_APPLICATION_TOKEN,'receipt');assert.equal(api.OPENSMS_RECEIPT_APPLICATION_TOKEN,undefined);assert.equal(api.AUTH_SEND_SMS_SECRET,undefined);
 assert.throws(()=>workerEnvironment('unknown',input));
});
test('gateway wake credentials cannot inherit member push identity or escape their worker',()=>{
 const input={...env,FCM_PROJECT_ID:'member-project',FCM_SERVICE_ACCOUNT_JSON:'member-account',OPENSMS_FCM_PROJECT_ID:'gateway-project',OPENSMS_FCM_CLIENT_EMAIL:'gateway-account',OPENSMS_FCM_PRIVATE_KEY:'gateway-private-key'};
 const sms=Object.fromEntries(workerEnvironment('collect-sms',input));
 assert.equal(sms.FCM_PROJECT_ID,'gateway-project');assert.equal(sms.FCM_CLIENT_EMAIL,'gateway-account');assert.equal(sms.FCM_PRIVATE_KEY,'gateway-private-key');assert.equal(sms.FCM_SERVICE_ACCOUNT_JSON,undefined);
 for(const name of ['collect-api','admin-api','collect-jobs','collect-email-jobs','send-sms-hook']){
  const scoped=Object.fromEntries(workerEnvironment(name,input));
  for(const key of ['OPENSMS_FCM_PROJECT_ID','OPENSMS_FCM_CLIENT_EMAIL','OPENSMS_FCM_PRIVATE_KEY','FCM_PRIVATE_KEY'])assert.equal(scoped[key],undefined,name+':'+key);
 }
 const missing=Object.fromEntries(workerEnvironment('collect-sms',{...env,FCM_PROJECT_ID:'member-only',FCM_SERVICE_ACCOUNT_JSON:'member-account'}));
 assert.equal(missing.FCM_PROJECT_ID,undefined);
});

test('self-hosted frontend origins remain distinct while member API may share either',async()=>{
 const folder=await mkdtemp(join(tmpdir(),'collect-web-origins-'));
 try{
  const admin=join(folder,'admin'),publicSite=join(folder,'public');await mkdir(admin);await mkdir(publicSite);
  await writeFile(join(admin,'index.html'),'ADMIN-MARKER');await writeFile(join(publicSite,'index.html'),'PUBLIC-MARKER');
  const webEnv=value=>{const valueRaw=canonicalProfile(value);return {...env,COLLECT_DEPLOYMENT_PROFILE:valueRaw,
   COLLECT_DEPLOYMENT_PROFILE_SHA256:createHash('sha256').update(valueRaw).digest('hex'),COLLECT_ADMIN_ASSET_DIR:admin,COLLECT_PUBLIC_ASSET_DIR:publicSite};};
  const collision={...profile,public_origin:profile.admin_origin};
  await assert.rejects(createWebApplication(webEnv(collision)),/Admin and public origins must differ/);
  for(const memberOrigin of [profile.admin_origin,profile.public_origin]){
   const candidate={...profile,member_api_origin:memberOrigin};
   const application=await createWebApplication(webEnv(candidate));
   const request=origin=>new Request(origin+'/',{headers:{Accept:'text/html'}});
   assert.equal(await (await application(request(candidate.admin_origin))).text(),'ADMIN-MARKER');
   assert.equal(await (await application(request(candidate.public_origin))).text(),'PUBLIC-MARKER');
  }
 }finally{await rm(folder,{recursive:true,force:true});}
});

test('self-hosted HTTP bridge handles client disconnects without late writes',async t=>{
 const originalCreate=http.createServer,originalFetch=globalThis.fetch;let handler;
 http.createServer=(_options,fn)=>{handler=fn;return{listen(){return this;}};};
 class Reply extends Writable{
  constructor(){super();this.parts=[];this.headersSent=false;this.statusCode=null;this.headCalls=0;this.endCalls=0;}
  _write(chunk,_encoding,done){this.parts.push(Buffer.from(chunk));done();}
  writeHead(status){this.headCalls++;this.statusCode=status;this.headersSent=true;return this;}
  end(...args){this.endCalls++;return super.end(...args);}
 }
 function input(stream=Readable.from([Buffer.from('{}')])){
  stream.headers={host:'api.collect.example','content-type':'application/json'};
  stream.rawHeaders=['host','api.collect.example','content-type','application/json'];stream.method='POST';stream.url='/v1/example';return stream;
 }
 try{
  await serveWeb(env);
  await t.test('normal response finishes and removes abort listeners',async()=>{
   let calls=0,outgoing;globalThis.fetch=async request=>{calls++;outgoing=request;return Response.json({ok:true});};
   const req=input(),res=new Reply(),finished=new Promise(resolve=>res.once('finish',resolve));await handler(req,res);await finished;
   assert.equal(calls,1);assert.equal(res.statusCode,200);assert.equal(outgoing.signal.aborted,false);
   assert.equal(req.listenerCount('aborted'),0);assert.equal(res.listenerCount('close'),0);
  });
  await t.test('early request abort refuses before upstream dispatch',async()=>{
   let calls=0;globalThis.fetch=async()=>{calls++;return Response.json({ok:true});};
   const req=input(new Readable({read(){}})),res=new Reply(),finished=new Promise(resolve=>res.once('finish',resolve)),pending=handler(req,res);
   req.emit('aborted');req.push('{}');req.push(null);await pending;await finished;
   assert.equal(calls,0);assert.equal(res.statusCode,504);assert.equal(req.listenerCount('aborted'),0);
  });
  await t.test('closed response after POST dispatch aborts upstream and never writes',async()=>{
   let calls=0,outgoing,ready;const dispatched=new Promise(resolve=>{ready=resolve;});
   globalThis.fetch=request=>{calls++;outgoing=request;ready();return new Promise((_,reject)=>request.signal.addEventListener('abort',()=>reject(Error('synthetic abort')),{once:true}));};
   const req=input(),res=new Reply(),pending=handler(req,res);await dispatched;
   const closed=new Promise(resolve=>res.once('close',resolve));res.destroy();await closed;await pending;
   assert.equal(calls,1);assert.equal(outgoing.signal.aborted,true);assert.equal(res.headCalls,0);assert.equal(res.endCalls,0);assert.equal(req.listenerCount('aborted'),0);
  });
  await t.test('already destroyed response never reads or dispatches',async()=>{
   let calls=0;globalThis.fetch=async()=>{calls++;return Response.json({ok:true});};
   const req=input(),res=new Reply(),closed=new Promise(resolve=>res.once('close',resolve));res.destroy();await closed;await handler(req,res);
   assert.equal(calls,0);assert.equal(res.headCalls,0);assert.equal(res.endCalls,0);assert.equal(req.listenerCount('aborted'),0);
  });
  await t.test('late uncooperative response cancellation errors are observed without writing',async()=>{
   const originalCancel=ReadableStream.prototype.cancel;
   try{for(const mode of ['throw','reject']){
    let calls=0,outgoing,send,ready,cancels=0;const dispatched=new Promise(resolve=>{ready=resolve;});
    ReadableStream.prototype.cancel=function(){cancels++;if(mode==='throw')throw Error('synthetic cancellation');return Promise.reject(Error('synthetic cancellation'));};
    globalThis.fetch=request=>{calls++;outgoing=request;ready();return new Promise(resolve=>{send=resolve;});};
    const req=input(),res=new Reply(),pending=handler(req,res);await dispatched;
    const closed=new Promise(resolve=>res.once('close',resolve));res.destroy();await closed;assert.equal(outgoing.signal.aborted,true);
    send(Response.json({ok:true}));await pending;await new Promise(resolve=>setTimeout(resolve,10));
    assert.equal(calls,1);assert.equal(cancels,1);assert.equal(res.headCalls,0);assert.equal(res.endCalls,0);assert.equal(req.listenerCount('aborted'),0);
   }}finally{ReadableStream.prototype.cancel=originalCancel;}
  });
  await t.test('response close destroys an active output stream and removes listeners',async()=>{
   const originalFromWeb=Readable.fromWeb;let output,wrote;
   const writeStarted=new Promise(resolve=>{wrote=resolve;});
   try{
    Readable.fromWeb=()=>{let sent=false;output=new Readable({read(){if(!sent){sent=true;this.push(Buffer.from('synthetic'));}}});return output;};
    globalThis.fetch=async()=>Response.json({ok:true});const req=input(),res=new Reply();
    res._write=()=>{wrote();};await handler(req,res);await writeStarted;
    assert.equal(output.destroyed,false);assert.equal(res.writableFinished,false);
    const closed=new Promise(resolve=>res.once('close',resolve));res.destroy();await closed;
    assert.equal(output.destroyed,true);assert.equal(req.listenerCount('aborted'),0);
   }finally{Readable.fromWeb=originalFromWeb;}
  });
 }finally{http.createServer=originalCreate;globalThis.fetch=originalFetch;}
});


test('public group routes intentionally serve the HTML shell for JSON and image GET or HEAD',async()=>{
 const folder=await mkdtemp(join(tmpdir(),'collect-web-group-accept-'));
 try{
  const admin=join(folder,'admin'),publicSite=join(folder,'public');await mkdir(admin);await mkdir(publicSite);await mkdir(join(publicSite,'c'));
  await writeFile(join(admin,'index.html'),'ADMIN-ROOT');await writeFile(join(publicSite,'index.html'),'PUBLIC-ROOT');await writeFile(join(publicSite,'c/index.html'),'GROUP-SHELL');
  const code='f0e5d2a1-9213-45cc-8e03-123456789abc',collision='f0e5d2a1-9213-45cc-8e03-abcdefabcdef';
  await writeFile(join(publicSite,'c',collision),'COLLIDING-FILE');
  const application=await createWebApplication({...env,COLLECT_ADMIN_ASSET_DIR:admin,COLLECT_PUBLIC_ASSET_DIR:publicSite});
  const request=(origin,path,accept,method='GET')=>application(new Request(origin+path,{method,headers:{Accept:accept}}));
  for(const accept of ['application/json','image/*'])for(const method of ['GET','HEAD']){
   for(const item of [code,'legacy-slug',collision]){
    const response=await request(profile.public_origin,'/c/'+item,accept,method);
    assert.equal(response.status,200,`${accept} ${method} ${item}`);assert.match(response.headers.get('Content-Type'),/^text\/html;\s*charset=utf-8$/);
    assert.match(response.headers.get('Cache-Control'),/no-store/);assert.equal(response.headers.get('Referrer-Policy'),'no-referrer');
    if(method==='HEAD')assert.equal(response.body,null);else assert.equal(await response.text(),'GROUP-SHELL');
   }
   for(const origin of [profile.admin_origin,profile.member_api_origin]){
    const response=await request(origin,'/c/'+code,accept,method);assert.equal(response.status,404);assert.equal(response.body,null);
   }
   for(const path of ['/c/bad--slug','/c/?slug='+code,'/group-link/?slug='+code])assert.equal((await request(profile.public_origin,path,accept,method)).status,404,path);
  }
  const memberCollision=await request(profile.member_api_origin,'/c/'+collision,'image/*');assert.equal(memberCollision.status,200);assert.equal(await memberCollision.text(),'COLLIDING-FILE');
  assert.equal((await request(profile.public_origin,'/c/'+code,'application/json','POST')).status,405);
  await rm(join(publicSite,'c/index.html'));
  for(const accept of ['application/json','image/*'])for(const method of ['GET','HEAD']){
   const response=await request(profile.public_origin,'/c/'+code,accept,method);assert.equal(response.status,503);assert.equal(response.body,null);
   assert.match(response.headers.get('Cache-Control'),/no-store/);assert.equal(response.headers.get('Referrer-Policy'),'no-referrer');
  }
 }finally{await rm(folder,{recursive:true,force:true});}
});
