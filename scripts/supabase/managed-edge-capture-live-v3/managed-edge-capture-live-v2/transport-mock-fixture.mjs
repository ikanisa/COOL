// Owned fake-token fixture. All HTTPS and socket entrypoints are mocked closed.
import assert from 'node:assert/strict';
import https from 'node:https';
import net from 'node:net';
import tls from 'node:tls';
import {syncBuiltinESMExports} from 'node:module';
import {EventEmitter} from 'node:events';
import {PassThrough} from 'node:stream';
import {createHash,randomUUID} from 'node:crypto';
import {mkdtemp,mkdir,readFile,rm,unlink,writeFile} from 'node:fs/promises';
import {join} from 'node:path';
const behavior=process.argv[2];assert(['success','status_error'].includes(behavior));
const root=await mkdtemp('/private/tmp/collect-edge-capture-test-'),archive=join(root,'archive'),keys=join(root,'key'),tokenPath=join(root,'fake-token');
await mkdir(archive,{mode:0o700});await mkdir(keys,{mode:0o700});await writeFile(tokenPath,'synthetic-token-not-real-1234567890',{mode:0o600});
let calls=0;const slugs=['collect-api','admin-api','collect-jobs'];
try{
 net.connect=()=>{throw Error('socket blocked');};net.createConnection=()=>{throw Error('socket blocked');};tls.connect=()=>{throw Error('socket blocked');};
 https.request=(url,options,callback)=>{
  calls++;assert.equal(url.origin,'https://api.supabase.com');assert(url.pathname.startsWith('/v1/projects/rrlduytparvsjfmegalh'));
  assert.equal(options.method,'GET');assert.equal(options.rejectUnauthorized,true);assert.equal(options.agent,false);assert.equal(options.headers.Authorization,'Bearer synthetic-token-not-real-1234567890');assert.equal(options.headers['Accept-Encoding'],'identity');
  const slug=slugs.find(s=>url.pathname.includes('/functions/'+s)),isBody=url.pathname.endsWith('/body');
  assert.equal(options.headers.Accept,isBody?'multipart/form-data':'application/json');
  let data,contentType='application/json';
  if(!slug)data=JSON.stringify({id:'rrlduytparvsjfmegalh',ref:'rrlduytparvsjfmegalh',organization_id:'ghnjnepwvwknswrwzepn',status:'ACTIVE_HEALTHY'});
  else if(!isBody)data=JSON.stringify({slug,id:['aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','cccccccc-cccc-4ccc-8ccc-cccccccccccc'][slugs.indexOf(slug)],status:'ACTIVE',version:2,updated_at:123,verify_jwt:true});
  else{contentType='multipart/form-data; boundary=fixture-boundary';data='--fixture-boundary\r\nContent-Disposition: form-data; name="metadata"\r\n\r\n{}\r\n--fixture-boundary\r\nContent-Disposition: form-data; name="file"; filename="index.ts"\r\n\r\nsynthetic-private-source\r\n--fixture-boundary--\r\n';}
  const req=new EventEmitter();req.destroy=()=>{};req.end=()=>queueMicrotask(()=>{const res=new PassThrough();res.statusCode=behavior==='status_error'?500:200;res.headers={'content-type':contentType};callback(res);if(res.statusCode===200)res.end(Buffer.from(data));});return req;
 };
 syncBuiltinESMExports();
 const {captureManaged,planDigest}=await import('./core.mjs');const pin=createHash('sha256').update(await readFile(new URL('./LIVE-SOURCE-PINS.json',import.meta.url))).digest('hex');
 const plan={format:'collect.edge-capture.plan.v2',scope:'managed',operation_id:randomUUID(),archive_dir:archive,key_dir:keys,token_path:tokenPath,source_pins_sha256:pin,deadline_ms:30000,fixture:null};
 if(behavior==='success'){const r=await captureManaged({plan,expectedPlanSha256:planDigest(plan),signal:null});assert.equal(r.scope,'managed');assert.equal(r.recognized_multipart_envelope,true);assert.equal(calls,10);
  await unlink(tokenPath);const {verifyCapture}=await import('./offline.mjs');const v=await verifyCapture({plan,expectedPlanSha256:planDigest(plan)});assert.equal(v.status,'capture_verified_point_in_time');assert.equal(v.archive_sha256,r.archive_sha256);assert.equal(calls,10);}
 else{await assert.rejects(captureManaged({plan,expectedPlanSha256:planDigest(plan),signal:null}),e=>e?.code==='PROVIDER_UNCONFIRMED');assert.equal(calls,1);}
 process.stdout.write(JSON.stringify({fixture:'socket-blocked fake token',behavior,request_count:calls})+'\n');
}finally{await rm(root,{recursive:true,force:true});}
