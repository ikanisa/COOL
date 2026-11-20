// Owned fake-token fixture. All HTTPS and socket entrypoints are mocked closed.
import assert from 'node:assert/strict';
import https from 'node:https';
import net from 'node:net';
import tls from 'node:tls';
import {syncBuiltinESMExports} from 'node:module';
import {EventEmitter} from 'node:events';
import {PassThrough} from 'node:stream';
import {createHash,randomUUID} from 'node:crypto';
import {mkdtemp,mkdir,readFile,readdir,rm,unlink,writeFile} from 'node:fs/promises';
import {join} from 'node:path';
const behavior=process.argv[2];assert(['success','status_error','project_403','metadata_403','body_json','body_no_boundary','body_gzip','body_truncated','project_network_error'].includes(behavior));
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
  else{contentType=behavior==='body_json'?'application/json; ignored=synthetic-header-secret':behavior==='body_no_boundary'?'multipart/form-data':'multipart/form-data; boundary=fixture-boundary';data=behavior==='body_json'?'{"error":"synthetic-body-secret"}':'--fixture-boundary\r\nContent-Disposition: form-data; name="metadata"\r\n\r\n{}\r\n--fixture-boundary\r\nContent-Disposition: form-data; name="file"; filename="index.ts"\r\n\r\nsynthetic-private-source\r\n--fixture-boundary--\r\n';}
  const status=behavior==='status_error'?500:behavior==='project_403'&&!slug||behavior==='metadata_403'&&slug&&!isBody?403:200;
  const req=new EventEmitter();req.destroy=()=>{};req.end=()=>queueMicrotask(()=>{if(behavior==='project_network_error'){req.emit('error',new Error('synthetic-error-secret'));return;}
   const res=new PassThrough();res.statusCode=status;res.headers={'content-type':contentType,'www-authenticate':'synthetic-header-secret'};
   if(isBody&&behavior==='body_gzip')res.headers['content-encoding']='gzip';if(isBody&&behavior==='body_truncated')res.headers['content-length']=String(Buffer.byteLength(data)+1);
   callback(res);if(res.statusCode===200&&!res.destroyed)res.end(Buffer.from(data));});return req;
 };
 syncBuiltinESMExports();
 const {captureManaged,planDigest}=await import('./core.mjs');const pin=createHash('sha256').update(await readFile(new URL('./LIVE-SOURCE-PINS.json',import.meta.url))).digest('hex');
 const plan={format:'collect.edge-capture.plan.v2',scope:'managed',operation_id:randomUUID(),archive_dir:archive,key_dir:keys,token_path:tokenPath,source_pins_sha256:pin,deadline_ms:30000,fixture:null};
 if(behavior==='success'){const r=await captureManaged({plan,expectedPlanSha256:planDigest(plan),signal:null});assert.equal(r.scope,'managed');assert.equal(r.recognized_multipart_envelope,true);assert.equal(calls,10);
  await unlink(tokenPath);const {verifyCapture}=await import('./offline.mjs');const v=await verifyCapture({plan,expectedPlanSha256:planDigest(plan)});assert.equal(v.status,'capture_verified_point_in_time');assert.equal(v.archive_sha256,r.archive_sha256);assert.equal(calls,10);}
 else{
  const expected=behavior==='body_json'||behavior==='body_no_boundary'?'UNSUPPORTED_PROVIDER_BODY':behavior==='body_gzip'?'PROVIDER_UNSUPPORTED_ENCODING':behavior==='body_truncated'?'PROVIDER_BODY_TRUNCATED':behavior==='project_network_error'?'PROVIDER_TRANSPORT_ERROR':'PROVIDER_HTTP_STATUS';
  await assert.rejects(captureManaged({plan,expectedPlanSha256:planDigest(plan),signal:null}),e=>e?.code===expected);
  assert.equal(calls,behavior==='metadata_403'?2:behavior.startsWith('body_')?3:1);
  const files=(await readdir(archive)).filter(x=>x.startsWith('EDGE-CAPTURE-PROGRESS-')).sort();assert(files.length<=128&&files.length>0);let last;
  for(const name of files){const b=await readFile(join(archive,name));assert(b.length<=2048);const text=b.toString();for(const secret of ['synthetic-token-not-real','synthetic-header-secret','synthetic-body-secret','synthetic-error-secret','synthetic-private-source'])assert(!text.includes(secret));last=JSON.parse(text);}
  assert.equal(last.event,'FAILED');assert.equal(last.phase,behavior==='metadata_403'?'METADATA_BEFORE_GET':['body_json','body_no_boundary'].includes(behavior)?'BODY_VALIDATE':behavior.startsWith('body_')?'BODY_GET':'PROJECT_GET');assert.equal(last.reason,expected);
  if(behavior==='body_json'){assert.equal(last.shape_reason,'MIME_TYPE_UNSUPPORTED');assert.equal(last.body_shape,'json_like');assert.equal(last.content_type,'json');}
  else if(behavior==='body_no_boundary'){assert.equal(last.shape_reason,'MIME_BOUNDARY_INVALID');assert.equal(last.body_shape,'multipart_like');assert.equal(last.content_type,'multipart_form_data');}
  else if(behavior==='body_gzip'){assert.equal(last.http_status,200);assert.equal(last.content_encoding,'gzip');}
  else if(behavior==='body_truncated')assert.equal(last.http_status,200);
  else if(behavior==='project_network_error'){assert.equal(last.http_status,null);assert.equal(last.content_type,'not_observed');}
  else{assert.equal(last.http_status,behavior==='status_error'?500:403);assert.equal(last.content_type,'json');}
  const outcome=JSON.parse(await readFile(join(archive,'EDGE-CAPTURE-OUTCOME.json'),'utf8'));assert.equal(outcome.provider_read_attempted,true);assert.equal(outcome.outcome,'UNCONFIRMED');
 }
 process.stdout.write(JSON.stringify({fixture:'socket-blocked fake token',behavior,request_count:calls})+'\n');
}finally{await rm(root,{recursive:true,force:true});}
