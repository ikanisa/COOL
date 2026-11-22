// Qualification-only managed SMS request witness. No network, credential
// acquisition, provider call, listener or production handler is created.
import {verifyDeploymentProfile} from '../../../supabase/functions/_shared/deployment-profile.js';
import {applicationWorkTuple} from '../../../supabase/functions/_shared/application-fence.js';
import {consumeSyntheticSmsNonce} from './synthetic-nonce-adapter.mjs';
const HEADER='x-collect-sms-ingress',FORMAT='collect.sms-ingress.fixture.v1',PROOF='collect.sms-ingress.fixture-proof.v1';
const MAX_BODY=262144,MAX_AGE=30000,BODY_READ_TIMEOUT_MS=5000,enc=new TextEncoder(),tokens=new WeakMap(),claimers=new WeakMap();
const names=new Set(['accept','apikey','authorization','content-type','idempotency-key','origin','x-request-id']);
const hex=b=>Array.from(new Uint8Array(b),x=>x.toString(16).padStart(2,'0')).join('');
const sha=async b=>hex(await crypto.subtle.digest('SHA-256',b));
const validHex=x=>typeof x==='string'&&/^[a-f0-9]{64}$/.test(x);
const need=(x,code='sms_ingress_denied')=>{if(!x)throw Error(code);};
const canonical=x=>JSON.stringify(Object.fromEntries(Object.keys(x).sort().map(k=>[k,x[k]])));
const packed=x=>btoa(String.fromCharCode(...enc.encode(JSON.stringify(x)))).replaceAll('+','-').replaceAll('/','_').replace(/=+$/,'');
function unpack(value){try{
 need(typeof value==='string'&&value.length<=2048&&/^[A-Za-z0-9_-]+$/.test(value));
 const bytes=Uint8Array.from(atob(value.replaceAll('-','+').replaceAll('_','/')+'='.repeat((4-value.length%4)%4)),x=>x.charCodeAt(0));
 const x=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));need(Array.isArray(x)&&x.length===9&&packed(x)===value);return x;
 }catch{throw Error('sms_ingress_denied');}}
function keyBytes(value){try{need(typeof value==='string'&&value.length===44);const b=Uint8Array.from(atob(value),c=>c.charCodeAt(0));need(b.length===32&&btoa(String.fromCharCode(...b))===value);return b;}catch{throw Error('sms_ingress_unconfigured');}}
function active(request){need(request instanceof Request&&!request.signal.aborted,'sms_ingress_cancelled');}
function route(request,origin){
 active(request);const u=new URL(request.url);need(u.origin===origin&&!u.username&&!u.password&&!u.hash&&u.href.length<=8192);
 need(['GET','POST','OPTIONS'].includes(request.method));
 const p=u.pathname;need(!p.includes('\\')&&!p.includes('//')&&!/%(?![0-9a-f]{2})/i.test(p)&&!/%(?:2f|5c|00|0[1-9a-f]|1[0-9a-f]|7f)/i.test(p));
 let path=null;for(const prefix of ['/functions/v1/collect-sms','/collect-sms'])if(p===prefix||p.startsWith(prefix+'/')){path=p.slice(prefix.length)||'/';break;}
 need(path!==null);return {path,query:u.search};
}
function cleanHeaders(headers,{forward=false}={}){
 const h=new Headers();let count=0;for(const [n,v] of headers){if(!names.has(n))continue;need(n.length<=128&&v.length<=8192&&(count+=n.length+v.length)<=32768);h.set(n,v);}
 if(forward)need(!h.has(HEADER));return h;
}
async function bytes(request){
 active(request);const declared=request.headers.get('content-length');
 if(declared!==null)need(/^(0|[1-9][0-9]{0,5})$/.test(declared)&&Number(declared)<=MAX_BODY,'sms_ingress_body_refused');
 if(['GET','OPTIONS'].includes(request.method)){need(!request.body&&(declared===null||declared==='0'),'sms_ingress_body_refused');return new Uint8Array();}
 if(!request.body){need(declared===null||declared==='0','sms_ingress_body_refused');return new Uint8Array();}
 const reader=request.body.getReader(),chunks=[];let n=0,reads=0,done=false;
 const deadline=Date.now()+BODY_READ_TIMEOUT_MS;
 const read=()=>new Promise((resolve,reject)=>{let finished=false,timer;const finish=(error,value)=>{if(finished)return;finished=true;clearTimeout(timer);request.signal.removeEventListener('abort',onAbort);error?reject(Error('sms_ingress_body_refused')):resolve(value);};
  const onAbort=()=>finish(true);request.signal.addEventListener('abort',onAbort,{once:true});
  timer=setTimeout(()=>finish(true),Math.max(0,deadline-Date.now()));if(request.signal.aborted)onAbort();else reader.read().then(x=>finish(false,x),()=>finish(true));});
 try{while(true){active(request);need(++reads<=16384,'sms_ingress_body_refused');const x=await read();active(request);if(x.done){done=true;break;}need(x.value instanceof Uint8Array&&(n+=x.value.length)<=MAX_BODY,'sms_ingress_body_refused');chunks.push(x.value);}
  need(declared===null||Number(declared)===n,'sms_ingress_body_refused');const all=new Uint8Array(n);let p=0;for(const c of chunks){all.set(c,p);p+=c.length;}return all;
 }finally{if(!done)try{void reader.cancel().catch(()=>{});}catch{}try{reader.releaseLock();}catch{}}
}
async function headerHash(h){return sha(enc.encode(JSON.stringify([...h.entries()].sort(([a],[b])=>a.localeCompare(b)))));}
async function config(settings,clock){
 const profile=await verifyDeploymentProfile(settings),now=clock();
 need(settings.COLLECT_DEPLOYMENT_PROFILE!==undefined&&profile.mode==='managed'&&profile.environment==='qualification'&&settings.APP_ENVIRONMENT==='qualification'&&
  settings.SUPABASE_URL===profile.supabase_origin&&settings.COLLECT_SMS_ENABLED==='true'&&Number.isSafeInteger(now),'sms_ingress_unconfigured');
 const raw=settings.COLLECT_SMS_INGRESS_PROOF_JSON,digest=settings.COLLECT_SMS_INGRESS_PROOF_SHA256;let proof;
 try{need(typeof raw==='string'&&enc.encode(raw).length<=8192,'sms_ingress_unconfigured');proof=JSON.parse(raw);}catch{throw Error('sms_ingress_unconfigured');}
 const fields=['evidenceSha256','format','frontdoorOrigin','profileSha256','reviewedAt','status','supabaseOrigin','workerGuard'];
 need(proof&&typeof proof==='object'&&!Array.isArray(proof)&&Object.keys(proof).sort().join('|')===fields.join('|')&&canonical(proof)===raw&&
  validHex(digest)&&await sha(enc.encode(raw))===digest&&proof.format===PROOF&&proof.status==='synthetic'&&proof.profileSha256===settings.COLLECT_DEPLOYMENT_PROFILE_SHA256&&
  proof.supabaseOrigin===profile.supabase_origin&&proof.frontdoorOrigin===profile.member_api_origin&&proof.frontdoorOrigin!==profile.supabase_origin&&
  proof.workerGuard==='synthetic_cf_worker_reject'&&validHex(proof.evidenceSha256)&&Number.isSafeInteger(proof.reviewedAt)&&proof.reviewedAt>0&&proof.reviewedAt<=now,'sms_ingress_unconfigured');
 const rawKey=settings.COLLECT_SMS_INGRESS_KEY_BASE64,key=keyBytes(rawKey),id=settings.COLLECT_SMS_INGRESS_KEY_ID;
 let root;try{
  need(typeof id==='string'&&/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/.test(id),'sms_ingress_unconfigured');
  for(const name of ['COLLECT_NATIVE_INGRESS_KEY_BASE64','DATA_ENCRYPTION_KEY','SESSION_ENCRYPTION_KEY','OTP_HMAC_KEY','ROOT_ADMIN_TOKEN']){
   const value=settings[name];need(!value||value!==rawKey,'sms_ingress_unconfigured');
   if(value){const raw=enc.encode(value);need(raw.length!==key.length||!raw.every((v,i)=>v===key[i]),'sms_ingress_unconfigured');}
  }
  for(const name of ['DATA_DECRYPTION_KEYS_JSON','SESSION_DECRYPTION_KEYS_JSON'])if(settings[name]){
   let ring;try{need(settings[name].length<=4096);ring=JSON.parse(settings[name]);}catch{throw Error('sms_ingress_unconfigured');}
   need(ring&&typeof ring==='object'&&!Array.isArray(ring)&&Object.keys(ring).length<=8&&Object.values(ring).every(x=>typeof x==='string'&&x!==rawKey),'sms_ingress_unconfigured');
  }
  root=await crypto.subtle.importKey('raw',key,{name:'HMAC',hash:'SHA-256'},false,['sign']);
 }finally{key.fill(0);}
 const derived=await crypto.subtle.sign('HMAC',root,enc.encode('collect.sms-ingress.signing-key.fixture.v1'));
 return {profile,proofDigest:digest,profileDigest:settings.COLLECT_DEPLOYMENT_PROFILE_SHA256,id,key:await crypto.subtle.importKey('raw',derived,{name:'HMAC',hash:'SHA-256'},false,['sign','verify']),clock};
}
const signedMessage=(parts,method,path)=>JSON.stringify([FORMAT,...parts,method,'collect-sms',path]);
function makeRequest(url,method,headers,body,signal){return new Request(url,{method,headers,body:method==='GET'||method==='OPTIONS'?undefined:body,signal});}
export async function createSyntheticSmsSigner(settings,{clock=()=>Date.now()}={}){
 const c=await config(settings,clock);
 return async request=>{
  active(request);need(!request.headers.has('cf-worker'),'sms_ingress_network_denied');const x=route(request,c.profile.member_api_origin),h=cleanHeaders(request.headers,{forward:true}),b=await bytes(request),now=c.clock();
  need(Number.isSafeInteger(now));const parts=[1,c.id,c.profileDigest,c.proofDigest,now,crypto.randomUUID(),await sha(b),await headerHash(h)];
  parts.push(hex(await crypto.subtle.sign('HMAC',c.key,enc.encode(signedMessage(parts,request.method,x.path+x.query)))));h.set(HEADER,packed(parts));
  return makeRequest(c.profile.supabase_origin+'/functions/v1/collect-sms'+(x.path==='/'?'':x.path)+x.query,request.method,h,b,request.signal);
 };
}
export async function createSyntheticSmsVerifier(settings,{clock=()=>Date.now()}={}){
 const c=await config(settings,clock);
 return async request=>{
  const x=route(request,c.profile.supabase_origin),parts=unpack(request.headers.get(HEADER)),sig=parts.pop();
  const [version,id,profile,proof,issued,nonce,bodyHash,headersHash]=parts,now=c.clock();
  need(version===1&&id===c.id&&profile===c.profileDigest&&proof===c.proofDigest&&Number.isSafeInteger(now)&&Number.isSafeInteger(issued)&&issued<=now+2000&&now-issued<=MAX_AGE&&
   /^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/.test(nonce??'')&&validHex(bodyHash)&&validHex(headersHash)&&validHex(sig));
  need(await crypto.subtle.verify('HMAC',c.key,Uint8Array.from(sig.match(/../g),x=>parseInt(x,16)),enc.encode(signedMessage(parts,request.method,x.path+x.query))));
  const h=cleanHeaders(request.headers),b=await bytes(request);need(await headerHash(h)===headersHash&&await sha(b)===bodyHash);active(request);
  const token=Object.freeze({});tokens.set(token,{request:makeRequest(c.profile.supabase_origin+x.path+x.query,request.method,h,b,request.signal),nonce,profile,policy:proof,issued,clock:c.clock});return token;
 };
}
// Only this factory may mint a claimer. It uses the real GatewayDatabase
// constructor and explicitly rebinds any previously bound wrapper to this
// exact ApplicationWork context before preparing the nonce statement.
export async function createSyntheticSmsNonceClaimer(db,work){
 applicationWorkTuple(work);let GatewayDatabase;try{({GatewayDatabase}=await import('../../../deploy/collect-sms/src/postgres.ts'));}catch{throw Error('sms_ingress_unconfigured');}
 need(db instanceof GatewayDatabase,'sms_ingress_unconfigured');
 const bound=Object.freeze(GatewayDatabase.prototype.withApplicationWork.call(db,work));
 const consume=value=>consumeSyntheticSmsNonce(bound,work,value);claimers.set(consume,work);return Object.freeze(consume);
}
// Only a factory-minted claimer for this exact work can resolve the claim.
// Missing, false, rejected, late or lost acknowledgement never releases it.
export async function claimSyntheticSmsIngress(token,work,consume,{timeoutMs=8000}={}){
 const s=tokens.get(token);need(s,'sms_ingress_denied');tokens.delete(token);
 applicationWorkTuple(work);need(typeof consume==='function'&&claimers.get(consume)===work&&Number.isSafeInteger(timeoutMs)&&timeoutMs>=25&&timeoutMs<=8000,'sms_ingress_unconfigured');
 claimers.delete(consume);
 const now=s.clock();need(Number.isSafeInteger(now)&&s.issued<=now+2000&&now-s.issued<=MAX_AGE);active(s.request);await work.assert();
 let timer,result;try{
  const operation=work.waitUntil(Promise.resolve().then(()=>consume({nonce:s.nonce,profile:s.profile,policy:s.policy,issuedAtMs:s.issued})));
  result=await Promise.race([operation,new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('timeout')),timeoutMs);})]);
 }catch{try{work.abandon('work_lost');}catch{}throw Error('sms_ingress_claim_unconfirmed');}finally{clearTimeout(timer);}
 need(result===true);active(s.request);const after=s.clock();need(Number.isSafeInteger(after)&&s.issued<=after+2000&&after-s.issued<=MAX_AGE);await work.assert();return s.request;
}
export const managedSmsGatewayUnavailable=()=>Response.json({error:{code:'gateway_unavailable',message:'The SMS gateway is not enabled.'}},{status:503,headers:{'cache-control':'no-store'}});
