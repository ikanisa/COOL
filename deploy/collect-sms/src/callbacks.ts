import type {Context} from "npm:hono@4.13.13";
import type {AppEnv,Env} from "./types.ts";
import {admin,adminActor} from "./auth.ts";
import {ApiError,hmac,integer,isoNow,randomToken,string,uid} from "./util.ts";
const utf8=new TextEncoder();
function urlAllowed(env:Env,value:string):string {
 let u:URL;try{u=new URL(value);}catch{throw new ApiError(400,'invalid_callback_url','Use an absolute HTTPS receiver URL');}
 const local=env.ENVIRONMENT==='development'&&env.CALLBACK_ALLOW_LOCAL_TEST==='true'&&['localhost','127.0.0.1','[::1]'].includes(u.hostname);
 const hosts=(env.CALLBACK_ALLOWED_HOSTS??'').split(',').map(v=>v.trim().toLowerCase()).filter(Boolean);
 if(u.username||u.password||u.hash||u.search||(!local&&(u.protocol!=='https:'||u.port&&u.port!=='443'||!hosts.includes(u.hostname)||/^[\d.]+$/.test(u.hostname)||u.hostname.includes(':')))||local&&!['http:','https:'].includes(u.protocol))
 throw new ApiError(400,'callback_host_denied','Receiver must be an explicitly allowed HTTPS host, without URL credentials, query or fragment');
 return u.href;
}
async function encryptionKey(env:Env) {
 if(!/^[a-fA-F0-9]{64}$/.test(env.CALLBACK_ENCRYPTION_KEY??''))throw new ApiError(503,'callback_unconfigured','Configure a dedicated 32-byte hex callback encryption key');
 return crypto.subtle.importKey('raw',Uint8Array.from(env.CALLBACK_ENCRYPTION_KEY!.match(/../g)!,h=>parseInt(h,16)),{name:'AES-GCM'},false,['encrypt','decrypt']);
}
async function encrypt(env:Env,secret:string,id:string){const iv=crypto.getRandomValues(new Uint8Array(12));const b=new Uint8Array(await crypto.subtle.encrypt({name:'AES-GCM',iv,additionalData:utf8.encode(id)},await encryptionKey(env),utf8.encode(secret)));return JSON.stringify({v:1,iv:Array.from(iv),cipher:Array.from(b)});}
async function decrypt(env:Env,encoded:string,id:string){const p=JSON.parse(encoded);if(p.v!==1)throw new Error('Unsupported envelope');return new TextDecoder().decode(await crypto.subtle.decrypt({name:'AES-GCM',iv:Uint8Array.from(p.iv),additionalData:utf8.encode(id)},await encryptionKey(env),Uint8Array.from(p.cipher)));}
export async function configureCallback(c:Context<AppEnv>,body:Record<string,unknown>) {
 admin(c,'applications:write');const applicationId=body.application_id===null?null:string(body.application_id,'application_id',1,200);
 if(applicationId&&!await c.env.DB.prepare('SELECT 1 FROM applications WHERE application_id=? AND revoked_at IS NULL').bind(applicationId).first())throw new ApiError(404,'not_found','Application not found');
 const url=urlAllowed(c.env,string(body.url,'url',1,2000)),now=isoNow();
 const prior=await c.env.DB.prepare('SELECT endpoint_id FROM webhook_endpoints WHERE application_id IS ?').bind(applicationId).first<{endpoint_id:string}>();
 const id=prior?.endpoint_id??uid('endpoint'),secret=randomToken('hook_'),cipher=await encrypt(c.env,secret,id),actor=adminActor(c);
 await c.env.DB.batch([
 c.env.DB.prepare(`INSERT INTO webhook_endpoints(endpoint_id,application_id,url,secret_cipher,enabled,created_at,updated_at) VALUES(?,?,?,?,1,?,?)
 ON CONFLICT(endpoint_id) DO UPDATE SET url=excluded.url,secret_cipher=excluded.secret_cipher,enabled=1,generation=webhook_endpoints.generation+1,updated_at=excluded.updated_at`).bind(id,applicationId,url,cipher,now,now),
 c.env.DB.prepare("UPDATE webhook_deliveries SET state='cancelled',updated_at=?,lease_id=NULL,lease_until=NULL WHERE endpoint_id=? AND state IN('pending','sending')").bind(now,id),
 c.env.DB.prepare('INSERT INTO audit_events(event_id,actor_type,actor_id,action,resource_id,at) VALUES(?,?,?,?,?,?)').bind(uid('audit'),actor.type,actor.id,'callback_configured',id,now)]);
 return c.json({endpoint_id:id,application_id:applicationId,url,signing_secret:secret,notice:'Secret shown once. Old queued deliveries were cancelled; an in-flight HTTP request may finish.'},201);
}
export async function disableCallback(c:Context<AppEnv>){
 admin(c,'applications:write');const id=c.req.param('id'),now=isoNow(),actor=adminActor(c);
 if(!await c.env.DB.prepare('SELECT endpoint_id FROM webhook_endpoints WHERE endpoint_id=?').bind(id).first())throw new ApiError(404,'not_found','Callback endpoint not found');
 await c.env.DB.batch([
 c.env.DB.prepare('UPDATE webhook_endpoints SET enabled=0,generation=generation+1,updated_at=? WHERE endpoint_id=?').bind(now,id),
 c.env.DB.prepare("UPDATE webhook_deliveries SET state='cancelled',updated_at=?,lease_id=NULL,lease_until=NULL WHERE endpoint_id=? AND state IN('pending','sending')").bind(now,id),
 c.env.DB.prepare('INSERT INTO audit_events(event_id,actor_type,actor_id,action,resource_id,at) VALUES(?,?,?,?,?,?)').bind(uid('audit'),actor.type,actor.id,'callback_disabled',id,now)]);
 return c.json({endpoint_id:id,enabled:false});
}
export async function listCallbacks(c:Context<AppEnv>){admin(c,'applications:write');const [a,b]=await c.env.DB.batch([c.env.DB.prepare('SELECT endpoint_id,application_id,url,enabled,generation,created_at,updated_at FROM webhook_endpoints ORDER BY created_at DESC LIMIT 250'),c.env.DB.prepare('SELECT delivery_id,endpoint_id,event_key,state,attempts,next_at,last_error,created_at,updated_at FROM webhook_deliveries ORDER BY created_at DESC LIMIT 250')]);return c.json({endpoints:a!.results,deliveries:b!.results});}
/** The only retries here repeat a callback, never a phone send or business event. */
export async function flushCallbacks(env:Env,transport:typeof fetch=env.FETCH??fetch,limit=10) {
 integer(limit,'limit',1,25);let delivered=0,failed=0;
 for(let n=0;n<limit;n++){
  const now=isoNow(),lease=uid('lease');
  const d=await env.DB.prepare(`UPDATE webhook_deliveries SET state='sending',lease_id=?,lease_until=?,attempts=attempts+1,updated_at=?
 WHERE delivery_id=(SELECT d.delivery_id FROM webhook_deliveries d JOIN webhook_endpoints e ON e.endpoint_id=d.endpoint_id
 WHERE e.enabled=1 AND e.generation=d.endpoint_generation AND ((d.state='pending' AND d.next_at<=?) OR(d.state='sending' AND d.lease_until<=?))
 ORDER BY d.next_at,d.delivery_id LIMIT 1) RETURNING *`).bind(lease,new Date(Date.now()+30000).toISOString(),now,now,now).first<Record<string,unknown>>();
  if(!d)break;
  const endpoint=await env.DB.prepare('SELECT * FROM webhook_endpoints WHERE endpoint_id=? AND enabled=1 AND generation=?').bind(String(d.endpoint_id),Number(d.endpoint_generation)).first<Record<string,unknown>>();
  let error='endpoint_changed',ok=false;
  if(endpoint){
   const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),8000);
   try{
    const url=urlAllowed(env,String(endpoint.url)),secret=await decrypt(env,String(endpoint.secret_cipher),String(endpoint.endpoint_id));
    const at=String(Math.floor(Date.now()/1000)),payload=JSON.stringify({event_id:d.delivery_id,...JSON.parse(String(d.payload_json))});
    const signature=await hmac(secret,`${d.delivery_id}.${at}.${payload}`);
    const response=await transport(url,{method:'POST',body:payload,headers:{'Content-Type':'application/json','X-Collect-Event':String(d.delivery_id),'X-Collect-Timestamp':at,'X-Collect-Signature':'v1='+signature},signal:controller.signal,redirect:'manual'});
    ok=response.status>=200&&response.status<300;error=ok?'':`http_${response.status}`;
    await response.body?.cancel();
   }catch(e){error=e instanceof ApiError?e.code:controller.signal.aborted?'timeout':'transport_or_key_error';}
   finally{clearTimeout(timer);}
  }
  const terminal=Number(d.attempts)>=8||!endpoint;
  await env.DB.prepare(`UPDATE webhook_deliveries SET state=?,next_at=?,updated_at=?,last_error=?,lease_id=NULL,lease_until=NULL WHERE delivery_id=? AND lease_id=? AND state='sending'`)
   .bind(ok?'delivered':terminal?'failed':'pending',new Date(Date.now()+Math.min(86400000,1000*2**Number(d.attempts))).toISOString(),isoNow(),ok?null:error,String(d.delivery_id),lease).run();
  if(ok)delivered++;else failed++;
 }
 return {delivered,failed};
}
