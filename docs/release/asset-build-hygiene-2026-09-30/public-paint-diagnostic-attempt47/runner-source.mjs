import {createServer} from 'node:http';
import {readFile, writeFile, mkdir, realpath} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join, resolve, extname} from 'node:path';

const root='/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL';
const packet=join(root,'docs/release/asset-build-hygiene-2026-09-30/public-paint-diagnostic-attempt47');
const out=join(root,'.cache/public-paint-diagnostic-attempt47');
const original=join(root,'.cache/public-app-media-attempt42');
const build=join(original,'build');
const sha=b=>createHash('sha256').update(b).digest('hex');
await mkdir(packet,{recursive:false});await mkdir(out,{recursive:false});
const caller=await readFile(new URL(import.meta.url));await writeFile(join(packet,'runner-source.mjs'),caller);
const report=JSON.parse(await readFile(join(original,'capture-report.json'),'utf8'));
const playwright=await import('/Users/jeanbosco/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright-core/index.js');const {chromium}=playwright.chromium?playwright:playwright.default;
const chrome='/Volumes/PRO-G40/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const mime={'.html':'text/html','.js':'text/javascript','.json':'application/json','.wasm':'application/wasm','.png':'image/png','.webp':'image/webp','.ttf':'font/ttf','.otf':'font/otf','.woff2':'font/woff2','.css':'text/css'};
const result={status:'running',scope:'Readonly actual screenshots of the exact preserved capture42 build, before/after semantics activation and in headed/headless Chrome; no new build or publication, native/device/whole-goal acceptance',caller_sha256:sha(caller),source_capture_report_sha256:sha(await readFile(join(original,'capture-report.json'))),source_runtime_sha256:report.runtime_before_sha256,source_build_manifest_sha256:report.build_manifest_sha256,chrome_sha256:sha(await readFile(chrome)),captures:[],resources:{},errors:[],blocked_requests:[],network_calls:0};
function save(){return writeFile(join(packet,'diagnosis.json'),JSON.stringify(result,null,2)+'\n');}
let browser;
const server=createServer(async(req,res)=>{
  try{
    const relative=decodeURIComponent(new URL(req.url,'http://localhost').pathname).replace(/^\//,'')||'index.html';
    const target=resolve(build,relative);if(!target.startsWith(build+'/')||await realpath(target)!==target)throw Error('Invalid requested path');
    const bytes=await readFile(target);if(sha(bytes)!==report.build_files[relative])throw Error('Actual served build hash mismatch: '+relative);
    result.resources[relative]=sha(bytes);res.setHeader('Content-Type',mime[extname(target)]||'application/octet-stream');res.end(bytes);
  }catch(e){result.errors.push(String(e));res.statusCode=404;res.end('Not found');}
});
await new Promise(ok=>server.listen(0,'127.0.0.1',ok));const origin='http://127.0.0.1:'+server.address().port;
try{
  for(const headless of [true,false]){
    const mode=headless?'headless':'headed';browser=await chromium.launch({executablePath:chrome,headless,args:['--disable-background-networking','--disable-component-update','--disable-sync']});result.browser_version=browser.version();
    for(const [id,route] of [['group-detail','/groups/qa-private-group'],['terms','/settings/legal/terms'],['privacy','/settings/legal/privacy']]){
      const context=await browser.newContext({viewport:{width:390,height:844},deviceScaleFactor:3,colorScheme:'dark',reducedMotion:'reduce',locale:'en-US'});
      await context.route('**/*',r=>{const url=r.request().url();if(new URL(url).origin===origin)return r.continue();result.blocked_requests.push({mode,id,url});return r.abort();});
      const page=await context.newPage();page.on('pageerror',e=>result.errors.push({mode,id,message:e.message}));
      await page.goto(origin+'/#'+route,{waitUntil:'networkidle',timeout:90000});await page.waitForTimeout(3000);
      for(const [phase,wait] of [['before-semantics',0],['after-semantics',2000],['settled-semantics',8000]]){
        if(phase==='after-semantics')await page.evaluate(()=>document.querySelector('flt-semantics-placeholder')?.click());
        if(wait)await page.waitForTimeout(wait);
        const relative=mode+'-'+id+'-'+phase+'.png';const path=join(out,relative);await page.screenshot({path,animations:'disabled',fullPage:false});
        const bytes=await readFile(path);const observation=await page.evaluate(()=>({document_fonts_status:document.fonts.status,semantics:[...document.querySelectorAll('flt-semantics')].map(n=>({label:n.getAttribute('aria-label'),text:n.textContent,rect:{x:n.getBoundingClientRect().x,y:n.getBoundingClientRect().y,width:n.getBoundingClientRect().width,height:n.getBoundingClientRect().height}})).filter(n=>n.label||n.text)}));
        result.captures.push({mode,id,route,phase,path,sha256:sha(bytes),bytes:bytes.length,width:bytes.readUInt32BE(16),height:bytes.readUInt32BE(20),observation});await save();console.log(mode,id,phase,sha(bytes));
      }
      await context.close();
    }
    await browser.close();browser=undefined;
  }
  if(result.errors.length)throw Error('Actual diagnostic browser/server errors');
  if(!result.resources['main.dart.js'])throw Error('Compiled application was not served');
  if(sha(await readFile(join(build,'main.dart.js')))!==report.build_files['main.dart.js'])throw Error('Preserved compiled app changed');
  result.status='captured_pending_visual_diagnosis';await save();console.log('PAINT DIAGNOSTIC CAPTURE COMPLETE');
}catch(e){result.status='fail';result.failure=String(e);await save();throw e;}
finally{await browser?.close();await new Promise(ok=>server.close(ok));}
