import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';

// A bounded synthetic DOM for the actual served HTML and mount function. It
// implements only the element/event/focus APIs that mountPrivacyPortal uses;
// it is not a browser, layout engine or accessibility/visual qualification.
class Events {
 constructor(){this.listeners=new Map();}
 addEventListener(type,fn){const list=this.listeners.get(type)??[];list.push(fn);this.listeners.set(type,list);}
 removeEventListener(type,fn){this.listeners.set(type,(this.listeners.get(type)??[]).filter(f=>f!==fn));}
 emit(type,event={}){event.preventDefault??=()=>{};for(const fn of [...(this.listeners.get(type)??[])])fn(event);}
}
class Element extends Events {
 constructor(tag,document){super();this.tagName=tag.toUpperCase();this.document=document;this.children=[];this.attributes=new Map();this.dataset={};this.hidden=false;this.disabled=false;this.value='';this.textContent='';this.parentNode=null;if(tag==='iframe')this.contentWindow={};}
 setAttribute(key,value){this.attributes.set(key,String(value));if(key==='id'){this.id=String(value);this.document.ids.set(this.id,this);}if(key==='hidden')this.hidden=true;if(key.startsWith('data-'))this.dataset[key.slice(5).replace(/-([a-z])/g,(_,c)=>c.toUpperCase())]=String(value);}
 getAttribute(key){return this.attributes.get(key)??null;}
 removeAttribute(key){this.attributes.delete(key);}
 append(child){child.parentNode=this;this.children.push(child);}
 insertBefore(child,before){const index=this.children.indexOf(before);assert.ok(index>=0);child.parentNode=this;this.children.splice(index,0,child);if(child.tagName==='IFRAME')queueMicrotask(()=>{const url=new URL(child.src);this.document.window.emit('message',{origin:this.document.origin,source:child.contentWindow,data:{type:'collect.turnstile.v1',attempt_id:url.searchParams.get('attempt_id'),token:'synthetic-mounted-captcha'}});});}
 remove(){if(this.parentNode)this.parentNode.children=this.parentNode.children.filter(child=>child!==this);this.parentNode=null;}
 get isConnected(){return this===this.document.root||!!this.parentNode?.isConnected;}
 get offsetParent(){for(let node=this;node;node=node.parentNode)if(node.hidden)return null;return this.parentNode;}
 querySelectorAll(selector){assert.equal(selector,'button,input');const result=[];const visit=node=>{for(const child of node.children){if(['BUTTON','INPUT'].includes(child.tagName))result.push(child);visit(child);}};visit(this);return result;}
 querySelector(selector){assert.equal(selector,'h2');const visit=node=>{for(const child of node.children){if(child.tagName==='H2')return child;const found=visit(child);if(found)return found;}return null;};return visit(this);}
 focus(){this.document.activeElement=this;}
 showModal(){this.open=true;}
 close(){this.open=false;}
}
function documentFrom(html,origin,window){
 const document={ids:new Map(),origin,window,getElementById(id){const node=this.ids.get(id);assert.ok(node,'Served HTML missing #'+id);return node;},createElement(tag){return new Element(tag,this);}};
 document.root=new Element('root',document);const stack=[document.root],voids=new Set(['meta','link','input','br','hr','img']);
 for(const match of html.matchAll(/<(\/?)([a-z][a-z0-9-]*)\b([^>]*)>/gi)){
  const [,closing,rawTag,attrs]=match,tag=rawTag.toLowerCase();
  if(closing){assert.equal(stack.at(-1).tagName,tag.toUpperCase(),'Synthetic parser only accepts the served balanced HTML');stack.pop();continue;}
  const node=new Element(tag,document);for(const attr of attrs.matchAll(/([^\s=]+)(?:="([^"]*)")?/g))node.setAttribute(attr[1],attr[2]??'');stack.at(-1).append(node);if(tag==='body')document.body=node;if(!voids.has(tag))stack.push(node);
 }
 assert.equal(stack.length,1);assert.ok(document.body);document.activeElement=document.body;return document;
}
const encodedJwt=claims=>Buffer.from('{"alg":"ES256"}').toString('base64url')+'.'+Buffer.from(JSON.stringify(claims)).toString('base64url')+'.synthetic';
const instant=now=>new Date(now).toISOString().replace(/\.(\d{3})Z$/,'.$1000Z');

export async function withMountedPrivacyPortal({client,route,phoneAvailable=false,failFirstChallenge=false,failLogout=false},check){
 let clock=Date.now(),created=null,challengeCalls=0;const calls=[],timers=new Map(),window=new Events(),origin='https://collect.example';
 const saved=Object.fromEntries(['document','window','location','sessionStorage','fetch','setInterval','clearInterval'].map(key=>[key,{exists:Object.hasOwn(globalThis,key),value:globalThis[key]}])),savedNow=Date.now;
 const env={SUPABASE_URL:'https://rrlduytparvsjfmegalh.supabase.co',SUPABASE_PUBLISHABLE_KEY:'sb_publishable_fixture_only',AUTH_PHONE_ENABLED:phoneAvailable?'true':'false',TURNSTILE_SITE_KEY:'synthetic-site-key'};
 const html=await route(new Request(origin+'/privacy/account-deletion'),env).text();const document=documentFrom(html,origin,window),storage=new Map();
 const principal=randomUUID(),managed=randomUUID(),sid=randomUUID(),email='mounted.member@example.test';
 const envelope=body=>({...Object.fromEntries(['contract_version','purpose','mode','challenge_id','challenge_context'].map(key=>[key,body[key]])),identity_type:'email',channel:'email'});
 const descriptor=body=>({...envelope(body),destination_hint:'m***@example.test',retry_after:60,created_at:created,expires_at:created+300,delivery_status:'not_disclosed',verification_state:'not_started',operation_id:body.operation_id??null,cancelled:false,candidate_cleanup:'not_required'});
 function candidate(body){const claims={iss:'https://rrlduytparvsjfmegalh.supabase.co/auth/v1',sub:managed,session_id:sid,aud:'authenticated',role:'authenticated',iat:created,exp:created+3600,amr:[{method:'otp',timestamp:created}]};return{...envelope(body),operation_id:body.operation_id,access_token:encodedJwt(claims),refresh_token:'synthetic-mounted-refresh',token_type:'bearer',expires_at:claims.exp,expires_in:3600,user:{id:principal,auth_user_id:managed,email,email_confirmed_at:instant(clock-1000),is_anonymous:false},auth_event:{method:'otp',timestamp:created},purpose_proof:{purpose:'account_deletion_request',challenge_id:body.challenge_id,user_id:principal,auth_user_id:managed,initiating_session_id:null,session_id:sid,method:'otp',authenticated_at:created,expires_at:created+300}};}
 const fetch=async(path,init)=>{
  assert.equal(init.method,'POST');const body=JSON.parse(init.body);calls.push({path,body,headers:init.headers});
  if(path.startsWith('/v1/privacy/email/'))assert.equal(Object.hasOwn(init.headers,'Authorization'),false);
  if(path.endsWith('/challenge')){created=Math.floor(clock/1000);if(failFirstChallenge&&++challengeCalls===1)throw Error('SYNTHETIC_LOST_CHALLENGE_REPLY');return Response.json(descriptor(body),{status:202});}
  if(path.endsWith('/verify'))return Response.json(candidate(body));
  if(path.endsWith('/cancel'))return Response.json({...descriptor(body),cancelled:true});
  if(path==='/v1/rpc/get_current_account_deletion_request_status_v1')return Response.json(null);
  if(path==='/v1/auth/logout'){if(failLogout)throw Error('SYNTHETIC_LOGOUT_UNKNOWN');return Response.json({ok:true});}
  assert.fail('Unexpected mounted test endpoint '+path);
 };
 async function settle(){for(let turn=0;turn<32;turn++){await new Promise(resolve=>setImmediate(resolve));if(document.getElementById('page').getAttribute('aria-busy')!=='true')return;}assert.fail('Mounted action did not settle');}
 const surface={document,calls,email,node:id=>document.getElementById(id),visible:id=>document.getElementById(id).offsetParent!==null,async click(id){const node=this.node(id);assert.ok(this.visible(id)&&!node.disabled,'Actual mounted button must be reachable: '+id);node.emit('click');await settle();},async submit(id){const node=this.node(id);assert.ok(this.visible(id),'Actual mounted form must be reachable: '+id);node.emit('submit');await settle();},async signIn(){if(!this.visible('email-form'))await this.click('use-email');this.node('email').value=email;await this.submit('email-form');assert.ok(this.visible('email-code-form'));this.node('email-code').value='123456';await this.submit('email-code-form');assert.ok(this.visible('step-request'));},async expire(){clock+=3601*1000;for(const timer of timers.values())timer();await settle();}};
 try{
  Object.assign(globalThis,{document,window,location:{origin,reload(){assert.fail('Unexpected reload');}},sessionStorage:{getItem:key=>storage.get(key)??null,setItem:(key,value)=>storage.set(key,value),removeItem:key=>storage.delete(key)},fetch,setInterval:fn=>{const id=timers.size+1;timers.set(id,fn);return id;},clearInterval:id=>timers.delete(id)});Date.now=()=>clock;client.mountPrivacyPortal();await check(surface);
 }finally{window.emit('pagehide');Date.now=savedNow;for(const[key,old]of Object.entries(saved)){if(old.exists)globalThis[key]=old.value;else delete globalThis[key];}}
}
