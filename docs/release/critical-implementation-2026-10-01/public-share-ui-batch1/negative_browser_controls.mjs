// Real browser controls replay the two original defects in isolated responses.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import {observeCollectDiagnostics} from '../../../../scripts/qa/collect_diagnostic_observer.mjs';
const require = createRequire(import.meta.url);
const {requireLoopbackOrigin, installLocalNetworkFence} = require('../../../../scripts/qa/public_browser_local_network.cjs');
const packet = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(packet, '../../../..');
const origin = process.env.PUBLIC_WEBSITE_QA_URL;
requireLoopbackOrigin(origin);
const output = path.join(packet,'negative-browser-controls');
fs.mkdirSync(output,{recursive:false});
const oldCssFile = path.join(packet,'source-before/web/public/revolut.css');
const oldAppFile = path.join(root,'.cache/public-static-current-20261002-batch2-attempt1/app/index.html');
const hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const sources = () => Object.fromEntries([fileURLToPath(import.meta.url),oldCssFile,oldAppFile,
  path.join(root,'scripts/qa/collect_diagnostic_observer.mjs'),path.join(root,'scripts/qa/public_browser_local_network.cjs')]
  .map(file=>[path.relative(root,file),hash(file)]));
const before=sources();
const {default:playwright}=await import(process.env.PLAYWRIGHT_CORE_PATH);
const browser=await playwright.chromium.launch({executablePath:process.env.PUBLIC_WEBSITE_CHROME_PATH,headless:true});
const blocked=[];const results=[];
const viewports=[{name:'compact_320x740',width:320,height:740},{name:'mobile_390x844',width:390,height:844},
  {name:'tablet_834x1194',width:834,height:1194},{name:'desktop_1440x1000',width:1440,height:1000}];
try {
  for(const mutation of ['old-disabled-cascade','old-generic-app-copy']) for(const viewport of viewports){
    const page=await browser.newPage({viewport:{width:viewport.width,height:viewport.height},deviceScaleFactor:1,serviceWorkers:'block'});
    const diagnostics=[];const errors=[];
    observeCollectDiagnostics(page,value=>diagnostics.push(value));
    page.on('pageerror',error=>errors.push(error.name));
    page.on('console',message=>{if(['warning','error'].includes(message.type()))errors.push(message.type());});
    await installLocalNetworkFence(page,origin,blocked);
    const requestPath=mutation==='old-disabled-cascade'?'/group-link/':'/app/';
    await page.route('**/*',async route=>{
      const url=new URL(route.request().url());
      if(url.origin===new URL(origin).origin&&mutation==='old-disabled-cascade'&&url.pathname==='/revolut.css'){
        await route.fulfill({status:200,contentType:'text/css',body:fs.readFileSync(oldCssFile,'utf8')});
      }else if(url.origin===new URL(origin).origin&&mutation==='old-generic-app-copy'&&url.pathname==='/app/'&&route.request().resourceType()==='document'){
        await route.fulfill({status:200,contentType:'text/html',body:fs.readFileSync(oldAppFile,'utf8')});
      }else{await route.fallback();}
    });
    try{
      await page.goto(new URL(requestPath,origin).href,{waitUntil:'networkidle',timeout:30000});
      const metrics=await page.evaluate(()=>{
        const action=document.querySelector('[data-collect-open-link]');const style=getComputedStyle(action);
        return {background:style.backgroundColor,foreground:style.color,cursor:style.cursor,
          disabled:action.getAttribute('aria-disabled')==='true',href:action.getAttribute('href'),
          cardLabel:document.querySelector('.share-link-widget span').textContent,
          helpHeading:document.querySelector('#share-link-help-heading').textContent,
          helpText:document.querySelector('.start-section').textContent};
      });
      const wouldAccept=mutation==='old-disabled-cascade'
        ?metrics.disabled&&metrics.href===null&&metrics.background!=='rgb(255, 255, 255)'&&metrics.foreground!=='rgb(25, 28, 31)'&&metrics.cursor==='default'
        :metrics.cardLabel==='COLLECT APP LINK'&&metrics.helpHeading==='Continue in the Collect app'&&!metrics.helpText.includes('then joins only after the member signs in');
      const screenshot=path.join(output,mutation+'_'+viewport.name+'.png');
      await page.screenshot({path:screenshot,fullPage:false});
      results.push({mutation,viewport:viewport.name,expectedRejected:true,actualRejected:!wouldAccept,metrics,
        consolePageErrors:errors,diagnosticFailures:diagnostics,screenshot:path.relative(root,screenshot),
        screenshotSha256:hash(screenshot),negativeControlOnly:true,publicationReviewAllowed:false});
    }finally{await page.close();}
  }
}finally{await browser.close();}
const after=sources();
const status=results.length===8&&results.every(row=>row.actualRejected&&row.consolePageErrors.length===0&&row.diagnosticFailures.length===0)&&blocked.length===0&&JSON.stringify(before)===JSON.stringify(after)?'pass':'fail';
fs.writeFileSync(path.join(output,'report.json'),JSON.stringify({status,scope:'Eight real isolated browser negative controls replay old source CSS/copy to prove both defect guards reject those original behaviors at four viewports. These original PNGs are unmodified test pixels and cannot be published or treated as accepted UI. No complete current-source media/native/provider/hosted/store/release acceptance.',
  source_before:before,source_after:after,blockedNetworkRequests:blocked,results},null,2)+'\n');
console.log(JSON.stringify({status,cases:results.length,expectedDenials:results.filter(row=>row.actualRejected).length,blockedNetworkRequests:blocked}));
process.exit(status==='pass'?0:1);
