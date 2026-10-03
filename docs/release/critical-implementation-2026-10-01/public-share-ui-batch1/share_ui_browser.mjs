// Actual static share entries omitted from the maintained sitemap route suite.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import {observeCollectDiagnostics} from '../../../../scripts/qa/collect_diagnostic_observer.mjs';
const require = createRequire(import.meta.url);
const {requireLoopbackOrigin, installLocalNetworkFence} = require('../../../../scripts/qa/public_browser_local_network.cjs');
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../..');
const packet = path.dirname(fileURLToPath(import.meta.url));
const origin = process.env.PUBLIC_WEBSITE_QA_URL;
requireLoopbackOrigin(origin);
const build = process.env.PUBLIC_BUILD_DIR;
const output = path.join(packet, 'browser-share-ui');
fs.mkdirSync(output, {recursive: false});
const sha = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const sources = () => Object.fromEntries([
  fileURLToPath(import.meta.url), path.join(root, 'scripts/qa/collect_diagnostic_observer.mjs'),
  path.join(root, 'scripts/qa/public_browser_local_network.cjs'),
].map(file => [path.relative(root, file), sha(file)]));
const before = sources();
const {default: playwright} = await import(process.env.PLAYWRIGHT_CORE_PATH);
const browser = await playwright.chromium.launch({executablePath: process.env.PUBLIC_WEBSITE_CHROME_PATH, headless: true});
const blocked = [];
const results = [];
const android = 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/140.0.0.0 Mobile Safari/537.36';
const ios = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1';
const play = 'https://play.google.com/store/apps/details?id=app.cool.mobile';
const apple = 'https://apps.apple.com/app/id6783960331';
const viewports = [{name:'compact_320x740',width:320,height:740}, {name:'mobile_390x844',width:390,height:844},
  {name:'tablet_834x1194',width:834,height:1194}, {name:'desktop_1440x1000',width:1440,height:1000}];
const cases = [
  {name:'group-valid-syntax', route:'/group-link/?slug=qa-valid-group', kind:'group', native:'collect://group/qa-valid-group', store:play, canonical:'/c/qa-valid-group'},
  {name:'group-expired-safe-syntax', route:'/group-link/?slug=expired-link-audit', kind:'group', native:'collect://group/expired-link-audit', store:play, canonical:'/c/expired-link-audit'},
  {name:'group-invalid-code', route:'/group-link/?slug=INVALID%20CODE', kind:'group', native:null, store:play, canonical:'/group-link/'},
  {name:'group-oversized-code', route:'/group-link/?slug='+'a'.repeat(141), kind:'group', native:null, store:play, canonical:'/group-link/'},
  {name:'app-direct', route:'/app/', kind:'app', native:'collect://app', store:play, canonical:'/app/'},
  {name:'group-c-direct', route:'/c/', kind:'group', native:null, store:play, canonical:'/c/'},
  {name:'group-link-direct', route:'/group-link/', kind:'group', native:null, store:play, canonical:'/group-link/'},
  {name:'app-invite-android', route:'/app/?publicId=QA_invite-01', kind:'app', native:'collect://invite/QA_invite-01', store:play, canonical:'/invite/QA_invite-01', ua:android},
  {name:'app-invite-ios', route:'/app/?publicId=QA_invite-01', kind:'app', native:'collect://invite/QA_invite-01', store:apple, canonical:'/invite/QA_invite-01', ua:ios},
  {name:'app-invalid-invite-ios', route:'/app/?publicId=%3Cscript%3E', kind:'app', native:'collect://app', store:apple, canonical:'/app/', ua:ios},
  {name:'app-oversized-invite-android', route:'/app/?publicId='+'a'.repeat(65), kind:'app', native:'collect://app', store:play, canonical:'/app/', ua:android},
];
try {
  for (const fixture of cases) for (const viewport of viewports) {
    const page = await browser.newPage({viewport:{width:viewport.width,height:viewport.height}, deviceScaleFactor:1,
      isMobile:viewport.width<=390, ...(fixture.ua ? {userAgent:fixture.ua}:{}), serviceWorkers:'block'});
    const consoleFailures = [];
    const diagnostics = [];
    const pageErrors = [];
    observeCollectDiagnostics(page, value => diagnostics.push(value));
    page.on('console', message => {if(['warning','error'].includes(message.type())) consoleFailures.push(message.type());});
    page.on('pageerror', error => pageErrors.push(error.name));
    await installLocalNetworkFence(page, origin, blocked);
    try {
      const response = await page.goto(new URL(fixture.route,origin).href,{waitUntil:'networkidle',timeout:30000});
      await page.locator('h1').waitFor({state:'visible',timeout:10000});
      const metrics = await page.evaluate(() => {
        const open = document.querySelector('[data-collect-open-link]');
        const store = document.querySelector('.hero-actions [data-collect-store-link]');
        const copy = document.querySelector('[data-collect-copy-link]');
        const boxes = [open,store,copy].map(el => {const r=el.getBoundingClientRect();const s=getComputedStyle(el);return {width:r.width,height:r.height,visible:s.display!=='none'&&s.visibility!=='hidden'&&Number(s.opacity)>0};});
        return {landingKind:document.body.dataset.shareLanding, heading:document.querySelector('h1').textContent,
          openBackground:getComputedStyle(open).backgroundColor,openForeground:getComputedStyle(open).color,openCursor:getComputedStyle(open).cursor,cardLabel:document.querySelector('.share-link-widget span').textContent,helpHeading:document.querySelector('#share-link-help-heading').textContent,helpText:document.querySelector('.start-section').textContent,disabledBackground:getComputedStyle(document.documentElement).getPropertyValue('--web-card-border').trim(),disabledForeground:getComputedStyle(document.documentElement).getPropertyValue('--web-secondary').trim(),openHref:open.getAttribute('href'), disabled:open.getAttribute('aria-disabled')==='true',
          storeHref:store.getAttribute('href'), storeName:store.getAttribute('aria-label'),
          canonical:document.querySelector('[data-share-canonical]').getAttribute('href'),
          smartBanner:document.querySelector('[data-share-smart-banner]').getAttribute('content'),
          code:document.querySelector('[data-share-code]').textContent,
          status:document.querySelector('[data-share-status]').textContent,
          bodyText:document.body.innerText, horizontalOverflow:Math.max(document.body.scrollWidth,document.documentElement.scrollWidth)>innerWidth+1,
          actions:boxes, title:document.title};
      });
      const cssRgb=hex=>'rgb('+hex.slice(1).match(/../g).map(value=>parseInt(value,16)).join(', ')+')';
      const checks = {truthfulCardLabel:metrics.cardLabel===(fixture.kind==='group'?'COLLECT GROUP LINK':'COLLECT APP LINK'),truthfulHelp:fixture.kind==='group'?metrics.helpHeading==='A link that survives onboarding':metrics.helpHeading==='Continue in the Collect app'&&!metrics.helpText.includes('then joins only after the member signs in'),visiblyDisabled:fixture.native!==null||(metrics.openBackground===cssRgb(metrics.disabledBackground)&&metrics.openForeground===cssRgb(metrics.disabledForeground)&&metrics.openCursor==='default'&&metrics.openBackground!=='rgb(255, 255, 255)'),enabledStylePreserved:fixture.native===null||metrics.openBackground==='rgb(255, 255, 255)',actualHttp200:response?.status()===200, correctLandingKind:metrics.landingKind===fixture.kind,
        noHorizontalOverflow:!metrics.horizontalOverflow, titleAndHeading:Boolean(metrics.title&&metrics.heading),
        exactNativeTarget:metrics.openHref===fixture.native, groupMissingCodeDenied:fixture.kind!=='group'||fixture.native!==null||(metrics.disabled&&metrics.code==='This group link is invalid.'&&metrics.status==='Ask the group member to share a new link.'),
        exactStoreDestination:metrics.storeHref===fixture.store, namedStoreAction:Boolean(metrics.storeName),
        exactCanonical:metrics.canonical===new URL(fixture.canonical,origin).href,
        exactSmartBanner:metrics.smartBanner==='app-id=6783960331, app-argument='+new URL(fixture.canonical,origin).href,
        visibleActions:metrics.actions.every(box=>box.visible&&box.width>0&&box.height>=44),
        noFalseInvitationAcceptance:!/invitation (is|has been) valid|you (have )?joined/i.test(metrics.bodyText),
        noConsoleOrPageOrDiagnosticFailures:consoleFailures.length===0&&pageErrors.length===0&&diagnostics.length===0};
      if(fixture.native===null&&metrics.openHref===null&&metrics.disabled){
        const initialUrl=page.url();const rect=await page.locator('[data-collect-open-link]').boundingBox();await page.mouse.click(rect.x+rect.width/2,rect.y+rect.height/2);await page.waitForTimeout(120);checks.disabledPointerCannotNavigate=page.url()===initialUrl;
        const focus=[];for(let step=0;step<9;step++){await page.keyboard.press('Tab');focus.push(await page.evaluate(()=>document.activeElement===document.querySelector('[data-collect-open-link]')));}
        checks.disabledNotInTabOrder=focus.every(value=>!value);
      }
      await page.evaluate(()=>{document.activeElement?.blur();window.scrollTo(0,0);});
      const screenshot = path.join(output, fixture.name+'_'+viewport.name+'.png');
      await page.screenshot({path:screenshot, fullPage:false});
      results.push({scenario:fixture.name, route:fixture.route, viewport:viewport.name, userAgentEmulationOnly:Boolean(fixture.ua),
        checks, failures:Object.entries(checks).filter(([,value])=>!value).map(([key])=>key),
        metrics, consoleFailures,pageErrors,diagnosticFailures:diagnostics,
        screenshot:path.relative(root,screenshot), screenshotSha256:sha(screenshot)});
    } finally {await page.close();}
  }
} finally {await browser.close();}
const after = sources();
const status = blocked.length===0 && results.every(row=>row.failures.length===0) && JSON.stringify(before)===JSON.stringify(after) ? 'pass':'fail';
fs.writeFileSync(path.join(output,'report.json'),JSON.stringify({status,checkedAt:new Date().toISOString(),
  scope:'Actual isolated maintained share renderer/styles/site.js fixture across four viewports, app/group copy and visibly disabled invalid-link behavior, plus synthetic invitation/UA targets. Invalid actions receive guarded real pointer clicks and keyboard checks; valid scheme/store links remain unclicked. No complete current-media gate, native/provider/hosted/store/release acceptance.',
  source_before:before,source_after:after,artifact_build:build,blockedNetworkRequests:blocked,results,
  nativeAcceptance:false,providerAcceptance:false,hostedAcceptance:false},null,2)+'\n');
console.log(JSON.stringify({status,cases:results.length,failures:results.flatMap(row=>row.failures.map(f=>row.scenario+' '+row.viewport+' '+f)),blockedNetworkRequests:blocked}));
process.exit(status==='pass'?0:1);
