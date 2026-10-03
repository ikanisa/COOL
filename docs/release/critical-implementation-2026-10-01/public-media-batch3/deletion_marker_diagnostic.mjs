// Read-only diagnostic of the genuine failed seventh route; no capture acceptance.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {createServer} from 'node:http';
import {fileURLToPath} from 'node:url';
import {observeCollectDiagnostics} from '../../../../scripts/qa/collect_diagnostic_observer.mjs';
const packet=path.dirname(fileURLToPath(import.meta.url));
const root=path.resolve(packet,'../../../..');
const captureDir=path.join(root,'.cache/public-media-current-20261002-batch3-attempt1');
const build=path.join(captureDir,'build');
const failedReport=JSON.parse(fs.readFileSync(path.join(captureDir,'capture-report.json')));
const sha=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const packageRoot='/Users/jeanbosco/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright-core';
const chrome='/Users/jeanbosco/Library/Caches/ms-playwright/chromium-1234/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const files=d=>fs.readdirSync(d,{withFileTypes:true}).flatMap(e=>e.isDirectory()?files(path.join(d,e.name)):e.isFile()?[path.join(d,e.name)]:(()=>{throw Error('Aliased diagnostic input')})());
const watched=[fileURLToPath(import.meta.url),path.join(root,'scripts/qa/collect_diagnostic_observer.mjs'),
 path.join(root,'scripts/qa/public_browser_app_media.mjs'),path.join(captureDir,'capture-report.json'),
 process.execPath,chrome,...files(packageRoot),...files(build)];
const bindings=()=>Object.fromEntries(watched.map(p=>[p,sha(p)]));
const before=bindings();
for(const [name,expected] of Object.entries(failedReport.build_files)) if(sha(path.join(build,name))!==expected)throw Error('Compiled diagnostic input changed: '+name);
const output=path.join(packet,'deletion-marker-diagnostic');fs.mkdirSync(output,{recursive:false});
const served={},blocked=[],errors=[],diagnostics=[];
const mime={'.html':'text/html','.js':'text/javascript','.json':'application/json','.wasm':'application/wasm','.png':'image/png','.ttf':'font/ttf','.otf':'font/otf','.woff2':'font/woff2'};
const server=createServer((request,response)=>{
 try{
  const name=decodeURIComponent(new URL(request.url,'http://127.0.0.1').pathname).replace(/^\//,'')||'index.html';
  if(!(name in failedReport.build_files)||name.split('/').some(p=>p==='..'))throw Error('Foreign diagnostic resource');
  const p=path.join(build,name),bytes=fs.readFileSync(p);if(sha(p)!==failedReport.build_files[name])throw Error('Served diagnostic resource changed');
  served[name]=sha(p);response.writeHead(200,{'content-type':mime[path.extname(name)]||'application/octet-stream','cache-control':'no-store'});response.end(bytes);
 }catch(e){errors.push(e.message);response.writeHead(404);response.end();}
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const origin='http://127.0.0.1:'+server.address().port;
const imported=await import(path.join(packageRoot,'index.js'));const chromium=imported.chromium||imported.default.chromium;
const browser=await chromium.launch({executablePath:chrome,headless:true,args:['--disable-background-networking','--disable-component-update','--disable-sync']});
let report;
try{
 const context=await browser.newContext({viewport:{width:390,height:844},deviceScaleFactor:3,colorScheme:'dark',reducedMotion:'reduce',locale:'en-US'});
 await context.route('**/*',async route=>{if(new URL(route.request().url()).origin===origin)return route.continue();blocked.push(route.request().url());return route.abort();});
 const page=await context.newPage();page.on('pageerror',e=>errors.push(e.message));observeCollectDiagnostics(page,v=>diagnostics.push(v));
 await page.goto(origin+'/#/settings/account/delete',{waitUntil:'networkidle',timeout:90000});
 await page.waitForFunction(()=>document.querySelector('flt-semantics-placeholder')||document.querySelectorAll('flt-semantics').length>5,null,{timeout:90000});
 await page.evaluate(()=>document.querySelector('flt-semantics-placeholder')?.click());
 await page.waitForFunction(()=>[...document.querySelectorAll('flt-semantics')].some(n=>((n.getAttribute('aria-label')||'')+n.textContent).includes('Request service unavailable')),null,{timeout:30000});
 await page.waitForTimeout(1800);
 const semantics=await page.evaluate(()=>[...document.querySelectorAll('flt-semantics')].filter(n=>{const r=n.getBoundingClientRect();return r.width>0&&r.height>0}).map(n=>({label:n.getAttribute('aria-label'),text:n.textContent,role:n.getAttribute('role')})));
 const screenshot=path.join(output,'account-deletion-unavailable.png');await page.screenshot({path:screenshot,animations:'disabled',fullPage:false});
 const after=bindings();const text=semantics.map(n=>(n.label||'')+' '+n.text).join('\n');
 report={status:'observed_unavailable_state_not_retired_marker',route:page.url(),title:await page.title(),semantics,
  actual_unavailable_state:text.includes('Request service unavailable'),help_action_present:text.includes('Get help'),retired_marker_present:text.includes('Select a reason to submit.'),
  screenshot:path.relative(root,screenshot),screenshot_sha256:sha(screenshot),served_resources:served,blocked_before_remote_http:blocked,errors,diagnostics,
  before,after,listed_inputs_unchanged:JSON.stringify(before)===JSON.stringify(after),scope:'Actual read-only loopback diagnostic of failed seventh route from its unchanged compiled fixture. No marker replacement, native/fidelity/provider/hosted/publication acceptance.'};
 fs.writeFileSync(path.join(output,'report.json'),JSON.stringify(report,null,2)+'\n');
 console.log(JSON.stringify({status:report.status,actual_unavailable_state:report.actual_unavailable_state,retired_marker_present:report.retired_marker_present,listed_inputs_unchanged:report.listed_inputs_unchanged,errors,diagnostics,blocked}));
 if(!report.actual_unavailable_state||report.retired_marker_present||!report.listed_inputs_unchanged||errors.length||diagnostics.length)process.exitCode=1;
}finally{await browser.close();await new Promise(r=>server.close(r));}
