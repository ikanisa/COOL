import fs from 'node:fs/promises';
import http from 'node:http';
import path from 'node:path';
import crypto from 'node:crypto';
import { chromium } from '/Users/jeanbosco/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright-core/index.mjs';
const root=process.cwd(), output=path.resolve(process.env.COLLECT_AUTH_REFERENCE_PACKET ?? '.cache/browser-auth-reference/attempt1');
await fs.mkdir(output,{recursive:true});
const source=path.join(root,'.cache/l17-shared-ui/browser-auth-fixture.js');
const bundle=await fs.readFile(source), digest=b=>crypto.createHash('sha256').update(b).digest('hex');
const actor='99890000-0000-4000-8000-000000000001';
const ids={A:'99890000-0000-4000-8000-000000000011',B:'99890000-0000-4000-8000-000000000012'};
const session=(which)=>({access_token:`e30.${Buffer.from(JSON.stringify({sub:actor,session_id:ids[which],exp:Math.floor(Date.now()/1000)+3600})).toString('base64url')}.synthetic`,refresh_token:`synthetic-refresh-${which}`,token_type:'bearer',expires_in:3600,user:{id:actor,aud:'authenticated',app_metadata:{},user_metadata:{},created_at:'2026-09-30T00:00:00Z'}});
const requests=[],checks=[],errors=[];let rejectRefresh=false;
const server=http.createServer(async(req,res)=>{
  requests.push({method:req.method,path:new URL(req.url,'http://fixture').pathname});
  if(req.url==='/fixture.js'){res.setHeader('content-type','application/javascript');res.end(bundle);return;}
  if(req.url==='/fixture-control/reject-refresh'){rejectRefresh=true;res.end('ok');return;}
  if(req.url==='/'||req.url==='/?cleanup'){res.setHeader('content-type','text/html');res.end('<!doctype html><title>Synthetic Auth privacy fixture</title><script defer src="/fixture.js"></script>');return;}
  if(req.url.startsWith('/auth/v1/')){
    let body='';for await(const part of req)body+=part;
    if(req.url.endsWith('/logout')){res.writeHead(204);res.end();return;}
    if(rejectRefresh&&req.url.startsWith('/auth/v1/token')){res.writeHead(400,{'content-type':'application/json'});res.end(JSON.stringify({code:'refresh_token_not_found',msg:'Synthetic revoked refresh'}));return;}
    let which='A';try{const value=JSON.parse(body);which=value.token==='B'||value.refresh_token==='synthetic-refresh-B'?'B':'A';}catch{}
    res.setHeader('content-type','application/json');res.end(JSON.stringify(session(which)));return;
  }
  res.writeHead(404);res.end();
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const origin=`http://127.0.0.1:${server.address().port}`, project=`${origin}/auth/v1`;
const browser=await chromium.launch({executablePath:'/Users/jeanbosco/.cache/selenium/chrome/mac-arm64/151.0.7922.34/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing',headless:true});
const context=await browser.newContext();
await context.route('**/*',route=>route.request().url().startsWith(origin)?route.continue():route.abort());
const pages=[];
const state=async page=>JSON.parse(await page.locator('#status').textContent());
const settle=()=>new Promise(r=>setTimeout(r,150));
function check(id,pass,detail={}){checks.push({id,pass,...detail});if(!pass)throw new Error(id);}
const open=async()=>{const p=await context.newPage();pages.push(p);p.on('pageerror',e=>errors.push({kind:'runtime',message:e.message.replace(/e30\.[A-Za-z0-9_-]+\.synthetic/g,'[redacted]')}));await p.goto(origin);await p.locator('#status').waitFor();await p.evaluate(()=>{window.qaChannel=new BroadcastChannel('sb-127-auth-token');window.qaMessages=[];window.qaChannel.onmessage=e=>{const v=e.data;window.qaMessages.push({keys:v&&typeof v==='object'?Object.keys(v).sort():[],credential_present:JSON.stringify(v).includes('access_token')||JSON.stringify(v).includes('refresh_token'),actor:v?.actor,session:v?.session});};});return p;};
const click=async(p,id)=>{await p.locator(`#${id}`).click();await settle();};
const inject=async(p,value)=>{await p.evaluate(v=>{const c=new BroadcastChannel('sb-127-auth-token');c.postMessage(v);c.close();},value);await settle();};
const invalidate=(which,override={})=>({protocol:'collect.auth.departed-session',version:1,event:'SIGNED_OUT',project,actor,session:ids[which],issued:Math.floor(Date.now()/1000),expires:Math.floor(Date.now()/1000)+30,...override});
let status='running';
try{
 const a=await open(), b=await open();
 await click(a,'sign-in-a');check('explicit-sign-in-authenticates-only-initiating-tab',(await state(a)).session===ids.A&&!(await state(b)).authenticated);
 await click(a,'refresh');check('refresh-does-not-authenticate-peer',!(await state(b)).authenticated);
 check('sign-in-refresh-send-no-channel-credentials',(await b.evaluate(()=>window.qaMessages)).length===0);
 await b.reload();await b.locator('#status').waitFor();await click(a,'refresh');check('full-page-reload-remains-signed-out-after-peer-refresh',!(await state(b)).authenticated);
 await inject(a,{event:'TOKEN_REFRESHED',session:session('A')});check('legacy-token-message-is-never-adopted',!(await state(b)).authenticated);
 await click(b,'sign-in-b');await inject(a,invalidate('A'));check('old-A-invalidation-cannot-remove-new-B',(await state(b)).session===ids.B);await click(a,'sign-in-a');
 for(const [id,message] of [['foreign',{...invalidate('B'),project:'https://foreign.invalid/auth/v1'}],['expired',{...invalidate('B'),issued:Math.floor(Date.now()/1000)-60,expires:Math.floor(Date.now()/1000)-30}],['future',{...invalidate('B'),issued:Math.floor(Date.now()/1000)+5,expires:Math.floor(Date.now()/1000)+35}],['wrong-version',{...invalidate('B'),version:2}],['nested-credentials',{...invalidate('B'),payload:session('B')}],['array',[invalidate('B')]],['malformed',{event:'SIGNED_OUT'}]]){await inject(a,message);check(`${id}-input-does-not-invalidate-B`,(await state(b)).session===ids.B);}
 await inject(a,invalidate('B'));check('matching-session-revocation-clears-only-B',!(await state(b)).authenticated&&(await state(a)).session===ids.A,{a:await state(a),b:await state(b)});
 const c=await open();await click(c,'sign-in-a');await click(a,'logout');check('genuine-logout-clears-same-session-peer',!(await state(c)).authenticated);
 const departure=(await c.evaluate(()=>window.qaMessages)).at(-1);check('logout-channel-shape-is-flat-reference-only',departure&&!departure.credential_present&&JSON.stringify(departure.keys)===JSON.stringify(['actor','event','expires','issued','project','protocol','session','version']));
 await click(a,'sign-in-a');await click(c,'sign-in-a');await click(a,'hold-logout');await click(a,'sign-in-b');await click(a,'release-logout');check('late-old-logout-keeps-new-B-sdk-session',(await state(a)).session===ids.B);check('late-old-logout-invalidates-departed-A-peer',!(await state(c)).authenticated);
 check('late-old-logout-emits-no-spurious-local-B-signedOut',(await state(a)).events.at(-1).event==='signedIn');
 await click(a,'sign-in-a');await click(c,'sign-in-a');await click(a,'hold-logout');await click(a,'refresh-a-explicit');await click(a,'release-logout');check('same-session-refresh-cannot-undo-pending-logout',!(await state(a)).authenticated&&!(await state(c)).authenticated);
 await click(a,'sign-in-b');await click(c,'sign-in-b');await context.request.post(origin+'/fixture-control/reject-refresh');await click(a,'refresh');check('actual-server-refresh-revocation-clears-current-and-peer',!(await state(a)).authenticated&&!(await state(c)).authenticated);check('server-revocation-retains-sessionExpired-event-reason',(await state(a)).events.some(e=>e.event==='signedOut'&&e.reason==='sessionExpired'));
 const ownedKeys=['sb-127-auth-token','flutter.sb-127-auth-token','supabase.auth.token-code-verifier','flutter.supabase.auth.token-code-verifier'];
 await b.evaluate(keys=>{for(const store of [localStorage,sessionStorage]){for(const key of keys)store.setItem(key,'synthetic-legacy-credential');store.setItem('unrelated-project-reference','keep');}},ownedKeys);
 await b.goto(origin+'/?cleanup');await b.locator('#status').waitFor();const cleaned=await b.evaluate(keys=>({owned:keys.some(k=>localStorage.getItem(k)!==null||sessionStorage.getItem(k)!==null),unrelated:localStorage.getItem('unrelated-project-reference')==='keep'&&sessionStorage.getItem('unrelated-project-reference')==='keep'}),ownedKeys);check('actual-owned-legacy-keys-cleaned-with-unrelated-values-preserved',!cleaned.owned&&cleaned.unrelated);await b.evaluate(()=>{localStorage.removeItem('unrelated-project-reference');sessionStorage.removeItem('unrelated-project-reference');});
 await b.evaluate(src=>{const iframe=document.createElement('iframe');iframe.id='denied-storage';iframe.sandbox='allow-scripts';iframe.src=src;document.body.append(iframe);},origin+'/?cleanup');const denied=b.frameLocator('#denied-storage');await denied.locator('#status').waitFor();check('actual-sandboxed-storage-denial-prevents-auth-initialization',JSON.parse(await denied.locator('#status').textContent()).cleanup_denied===true);
 for(let i=0;i<pages.length;i++){const storage=await pages[i].evaluate(async()=>({local:Object.keys(localStorage),session:Object.keys(sessionStorage),indexed:(await indexedDB.databases()).map(d=>d.name),caches:await caches.keys(),cookie:document.cookie}));check(`tab${i}-no-persisted-browser-auth-credentials`,storage.local.length===0&&storage.session.length===0&&storage.indexed.length===0&&storage.caches.length===0&&storage.cookie==='');}
 check('no-unhandled-runtime-errors',errors.length===0);status='pass';
}catch(error){status='fail';errors.push({kind:'assertion',message:error.message});}
finally{await fs.writeFile(path.join(output,'report.json'),JSON.stringify({status,kind:'actual_Chrome_real_vendored_GoTrue_loopback_fixture',origin,bundle_sha256:digest(bundle),checks,errors,requests,hosted_calls:0,provider_calls:0,database_calls:0},null,2)+'\n');await context.close();await browser.close();await new Promise(r=>server.close(r));}
console.log(JSON.stringify({status,checks:checks.length,errors:errors.length,output}));if(status!=='pass')process.exitCode=1;
