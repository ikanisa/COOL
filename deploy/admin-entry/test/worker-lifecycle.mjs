import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {createServer} from 'node:http';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {extname, resolve, sep} from 'node:path';
import entry from '../src/index.mjs';

const require=createRequire(new URL('../../../admin-web/package.json',import.meta.url));
const {chromium}=require('playwright-core');
if (!process.argv[2]) throw new Error('Pass the retained Admin shell artifact directory.');
const bundle=resolve(process.argv[2]);
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const receiptPath=process.argv[3]||bundle+'-artifact.json';
const archive=JSON.parse(await readFile(receiptPath,'utf8'));
const cutover=archive.format==='collect.admin.immutable-worker-shell.v1';
const securityStage=archive.format==='collect.admin.security-stage-shell.v1';
const pages=archive.format==='collect.admin.pages.predecessor-shell.v2';
const pagesBytes=pages ? await readFile(process.argv[4]) : null;
const replacement=pages ? (await import('data:text/javascript;base64,'+pagesBytes.toString('base64'))).default : entry;
const restored=cutover||securityStage||pages;
const workerName=restored?'custom-sw.js':'admin-shell-sw.js';
const script=await readFile(resolve(bundle,workerName));
const files=restored?archive.entries.map(i=>({path:i.restore_as,sha256:i.sha256})):archive.files;
const registeredPath=pages?archive.registered_worker:'/'+workerName+(cutover?'?v='+archive.cache_name:'');
const mainAsset=securityStage?files.find(i=>i.path.startsWith('_build/')&&i.path.endsWith('/main.dart.js')).path:'main.dart.js';
const shellHash=sha(script);
assert.ok(files.some(i=>i.path===workerName&&i.sha256===shellHash));
const MIME={'.js':'text/javascript','.html':'text/html','.json':'application/json','.wasm':'application/wasm'};
const old=pages?'https://cool-admin-212.pages.dev':securityStage?'https://admin16-security-stage.collect.ikanisa.com':cutover?'https://admin.collect.ikanisa.com':'https://admin-preview.collect.ikanisa.com';
let retired=false, replacements=0;
const server=createServer(async(req,res)=>{
  try {
    const url=new URL(req.url,'http://127.0.0.1');
    if(url.pathname==='/fixture-editor') {
      res.writeHead(200,{'Content-Type':'text/html','Cache-Control':'no-store'});
      return res.end('<!doctype html><title>Synthetic editor</title><label>Draft <input id="draft"></label>');
    }
    if(retired){
      const response=replacement.fetch(new Request(old+url.pathname+url.search,{method:req.method,headers:req.headers}));
      if(url.pathname==='/'+workerName&&response.status===200) replacements++;
      res.writeHead(response.status,Object.fromEntries(response.headers));
      return res.end(Buffer.from(await response.arrayBuffer()));
    }
    const recorded=pages&&archive.entries.find(row=>row.url_path===url.pathname+url.search);
    if (recorded?.redirects?.length) {
      const initial=recorded.redirects[0];res.writeHead(initial.status,{Location:initial.location});return res.end();
    }
    const path=resolve(bundle,'.'+(url.pathname==='/'?'/index.html':url.pathname));
    assert.ok(path.startsWith(bundle+sep));
    const bytes=await readFile(path);
    res.writeHead(recorded?.status||200,{'Content-Type':recorded?.content_type||MIME[extname(path)]||'application/octet-stream','Cache-Control':'no-store'});
    res.end(bytes);
  } catch {res.writeHead(404);res.end();}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const origin='http://127.0.0.1:'+server.address().port;
const browser=await chromium.launch({executablePath:process.env.CHROME_PATH||'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  args:['--disable-background-networking','--host-resolver-rules=MAP * 127.0.0.1']});
try {
  const context=await browser.newContext();
  const page=await context.newPage();
  await page.goto(origin+'/fixture-editor');
  await page.evaluate(async path=>{await navigator.serviceWorker.register(path,{updateViaCache:'none'});await navigator.serviceWorker.ready;},registeredPath);
  await page.reload();
  await page.waitForFunction(path=>navigator.serviceWorker.controller?.scriptURL.endsWith(path),registeredPath);
  const peer=await context.newPage();
  await peer.goto(origin+'/fixture-editor');
  await peer.waitForFunction(()=>navigator.serviceWorker.controller!==null);
  // This predecessor supplies its cached Flutter shell for every navigation.
  // Attach the synthetic editor to that real controlled document.
  if (securityStage) await page.evaluate(()=>{
    const field=document.createElement('input');
    field.id='draft';
    Object.assign(field.style,{position:'fixed',top:'1rem',left:'1rem',zIndex:'2147483647'});
    document.body.append(field);
  });
  await page.locator('#draft').fill('unsaved synthetic editor text');
  await page.evaluate(()=>{
    sessionStorage.setItem('collect.admin.pending-attempts.v1','uncertain-original-id');
    localStorage.setItem('synthetic-legacy-record','same-principal-record');
  });
  retired=true;
  await page.evaluate(async()=>{const reg=await navigator.serviceWorker.getRegistration();await reg.update();});
  await page.waitForFunction(async()=>Boolean((await navigator.serviceWorker.getRegistration())?.waiting));
  assert.ok(replacements>0);
  await context.setOffline(true);
  assert.equal(await page.locator('#draft').inputValue(),'unsaved synthetic editor text');
  const engine=await page.evaluate(async path=>{
    const response=await fetch('/'+path);
    const hash=await crypto.subtle.digest('SHA-256',await response.arrayBuffer());
    return Array.from(new Uint8Array(hash),b=>b.toString(16).padStart(2,'0')).join('');
  },mainAsset);
  assert.ok(files.some(i=>i.path===mainAsset&&i.sha256===engine));
  await context.setOffline(false);
  assert.equal(await page.evaluate(()=>sessionStorage.getItem('collect.admin.pending-attempts.v1')),'uncertain-original-id');
  await peer.close();
  assert.equal(await page.evaluate(async()=>Boolean((await navigator.serviceWorker.getRegistration())?.waiting)),true);
  await page.close();
  const probe=await context.newPage();
  await probe.goto(origin+'/fixture-editor');
  await probe.waitForFunction(async()=>!(await navigator.serviceWorker.getRegistration()),{},{timeout:15000});
  assert.equal(await probe.evaluate(()=>localStorage.getItem('synthetic-legacy-record')),'same-principal-record');
  const names=await probe.evaluate(()=>caches.keys());
  assert.ok(names.some(s=>restored?s===archive.cache_name:s.startsWith('collect-admin-shell-')));
  if (pages) {
    const retained=await probe.evaluate(async path=>{const response=await caches.match('/'+path);const hash=await crypto.subtle.digest('SHA-256',await response.arrayBuffer());return Array.from(new Uint8Array(hash),b=>b.toString(16).padStart(2,'0')).join('');},mainAsset);
    assert.equal(retained,engine);
  }
  const description=pages?'Distributed Pages predecessor and original registration URL.':securityStage?'Distributed security-stage version 5 service worker and integrity manifest.':cutover?'Distributed original version 41 service worker and cache manifest.':'Retained October 16 build, distinct from the public preview version.';
  console.log(JSON.stringify({format:'collect.admin.archived-worker-lifecycle.v1',status:'PASS',browser:browser.version(),artifact_sha256:sha(await readFile(receiptPath)),worker_sha256:shellHash,offline_main_sha256:engine,waiting_with_open_tabs:true,live_draft_survived:true,old_request_id_survived:true,retired_after_last_controlled_tab_closed:true,old_cache_and_local_storage_retained:true,...(pages?{pages_bundle_sha256:sha(pagesBytes),registered_url:registeredPath,provider_deployment:archive.provider_id,closed_client_cached_main_sha256:engine}:{}),scope:description+' Synthetic open editor and records on loopback.'},null,2));
  await context.close();
} finally {await browser.close();await new Promise(done=>server.close(done));}
