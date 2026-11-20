import assert from 'node:assert/strict';
import {readFile, stat} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {extname, resolve, sep} from 'node:path';
import {fileURLToPath} from 'node:url';
import entry from '../src/index.mjs';

const require = createRequire(new URL('../../../admin-web/package.json', import.meta.url));
const {chromium} = require('playwright-core');
if (!process.argv[2] || !process.argv[3]) throw new Error('Pass verified production and qualification React Admin package directories.');
const productionPackage=resolve(process.argv[2]), qualificationPackage=resolve(process.argv[3]);
const original = 'https://admin.collect.ikanisa.com';
const preview = 'https://admin-preview.collect.ikanisa.com';
const securityStage='https://admin16-security-stage.collect.ikanisa.com';
const pagesOrigin='https://cool-admin-212.pages.dev';
const pagesBytes=process.argv[4] ? await readFile(process.argv[4]) : null;
const pagesWorker=pagesBytes ? (await import('data:text/javascript;base64,'+pagesBytes.toString('base64'))).default : null;
const production='https://platform-admin.collect.ikanisa.com', qualification='https://admin-supabase-qa.collect.ikanisa.com';
const javascript = 'text/javascript; charset=utf-8';
const types = {'.html':'text/html', '.js':javascript, '.css':'text/css', '.json':'application/json', '.png':'image/png', '.woff2':'font/woff2', '.ttf':'font/ttf'};
const draftKey = 'collect.admin.pending-attempts.v1';
const draft = '{"version":1,"entries":[{"key":"original-synthetic-request","binding":"previous-actor","state":"unconfirmed"}]}';
const browser = await chromium.launch({
  executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  headless: true,
  args: ['--disable-background-networking', '--host-resolver-rules=MAP * 127.0.0.1'],
});
const checks = [];
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
async function packageIdentity(artifact, target) {
  const appEntry = await readFile(artifact + '/index.html');
const entryPath = /src="([^"]+\/assets\/admin-entry\.js)"/.exec(appEntry.toString())?.[1];
assert.ok(entryPath, 'The supplied package must contain the compiled React entry.');
  const receipt=JSON.parse(await readFile(artifact+'.json','utf8'));
  return {source:receipt.source,index_sha256:digest(appEntry),entry_sha256:digest(await readFile(artifact+new URL(entryPath,target).pathname))};
}
async function testOrigin(origin, target, artifact) {
  const context = await browser.newContext({serviceWorkers:'block'});
  let role = 'guest';
  const apiReads = [], forbidden = [], fixtureProblems = [];
  const session = () => role === 'guest' ? {user:null, csrfToken:null} : {
    user:{id:'10000000-0000-4000-8000-000000000001',sessionId:'10000000-0000-4000-8000-000000000002',
      email:'new-operator@synthetic.invalid',role:'staff',permissions:role==='reader'?['collections.read']:[]},
    expiresAt:new Date(Date.now()+3600000).toISOString(),
  };
  await context.route('**/*', async route => {
    const req=route.request(), url=new URL(req.url());
    try {
      if (url.origin===origin) {
        if (url.pathname==='/seed-local-browser-state') {
          return await route.fulfill({status:200,contentType:'text/html',body:'<!doctype html><title>Synthetic predecessor</title>'});
        }
        const worker=origin===pagesOrigin?pagesWorker:entry;
        const response=worker.fetch(new Request(req.url(),{method:req.method(),headers:await req.allHeaders()}));
        return await route.fulfill({status:response.status,headers:Object.fromEntries(response.headers),body:Buffer.from(await response.arrayBuffer())});
      }
      if (url.origin!==target || req.method()!=='GET') {
        forbidden.push([req.method(),url.origin,url.pathname]);
        return await route.abort();
      }
      if (url.pathname.startsWith('/api/admin/')) {
        const headers=await req.allHeaders();
        assert.ok(!Object.entries(headers).some(([,value])=>value.includes('old-fixture-cookie') || value.includes('original-synthetic-request')));
        apiReads.push(url.pathname);
        let body={};
        if (url.pathname==='/api/admin/auth/session') body=session();
        else if (url.pathname==='/api/admin/auth/email-verification') body={contractVersion:1,sessionId:session().user?.sessionId,emailVerifiedAt:null};
        return await route.fulfill({status:200,json:body});
      }
      const file=resolve(artifact,'.'+(url.pathname==='/'?'/index.html':url.pathname));
      assert.ok(file.startsWith(artifact+sep));
      if (!(await stat(file).catch(()=>null))?.isFile()) return await route.fulfill({status:404,body:''});
      return await route.fulfill({status:200,contentType:types[extname(file)]||'application/octet-stream',body:await readFile(file)});
    } catch (error) {
      fixtureProblems.push(error.message);
      await route.abort();
    }
  });
  const page=await context.newPage();
  page.setDefaultTimeout(10000);
  async function guest(path,expected) {
    await page.goto(origin+path);
    await page.waitForURL(u=>u.origin===target&&u.hash.startsWith('#/admin/login'));
    const login=new URL(page.url());
    assert.equal(new URLSearchParams(login.hash.split('?')[1]).get('returnTo'),expected);
    await page.getByRole('textbox').first().waitFor();
  }
  try {
    await guest('/admin/groups?sort=name','/admin/groups?sort=name');
    await guest('/#/admin/transactions?view=momo','/admin/transactions?view=momo');
    checks.push(origin+' path and hash bookmarks reached the rendered React login with their original return route');
    if (origin===pagesOrigin) {
      await page.goto(origin+'/#/admin/payment-intents/synthetic-original-id');
      const home=page.getByRole('link',{name:'Open Collect Admin in a new tab'});
      assert.equal(await home.getAttribute('href'),production+'/#/admin');
      assert.ok(page.url().endsWith('/#/admin/payment-intents/synthetic-original-id'));
      checks.push(origin+' retained a former payment-intent bookmark because the released React router has no corresponding detail identity');
    }
    role='reader';
    await page.goto(origin+'/#/admin/groups');
    await page.getByRole('heading',{name:'Groups',exact:true}).waitFor();
    checks.push(origin+' permitted reader reached the actual React Groups page');
    role='restricted';
    await page.goto(origin+'/admin/burimunsi');
    await page.getByRole('heading',{name:'Access unavailable',exact:true}).waitFor();
    assert.equal(apiReads.some(path=>path.includes('/burimunsi')),false);
    checks.push(origin+' restricted Staff received the real permission denial without a BuriMunsi data request');
    await page.goto(origin+'/seed-local-browser-state');
    await page.evaluate(async()=>{
      const cache=await caches.open('synthetic-v41-private-cache');
      await cache.put('/api/admin/old-fixture',new Response('old confidential fixture'));
    });
    await page.goto(origin+'/admin/groups');
    await page.getByRole('link',{name:'Open Collect Admin in a new tab'}).waitFor();
    assert.equal(page.url(),origin+'/admin/groups');
    assert.equal(await page.evaluate(async()=>await (await caches.match('/api/admin/old-fixture')).text()),'old confidential fixture');
    checks.push(origin+' kept a cache-only predecessor tab and its original cached response');
    await page.evaluate(({key,value})=>{
      sessionStorage.setItem(key,value);localStorage.setItem('synthetic-draft','draft bytes retained');
      document.cookie='old=old-fixture-cookie; Path=/; SameSite=Strict';
    },{key:draftKey,value:draft});
    const ambiguous='/admin/groups?sort=name#/admin/transactions?view=momo';
    await page.goto(origin+ambiguous);
    const first=page.getByRole('link',{name:'Open the bookmarked route'}),alternate=page.getByRole('link',{name:'Open the address path instead'});
    assert.equal(await first.getAttribute('href'),target+'/#/admin/transactions?view=momo');
    assert.equal(await alternate.getAttribute('href'),target+'/#/admin/groups?sort=name');
    const opened=context.waitForEvent('page');
    await first.click();
    const pop=await opened;
    await pop.waitForURL(u=>u.origin===target);
    assert.equal(await pop.evaluate(async key=>window.opener===null && sessionStorage.getItem(key)===null && localStorage.getItem('synthetic-draft')===null && !document.cookie.includes('old-fixture-cookie') && !(await caches.match('/api/admin/old-fixture')),draftKey),true);
    await pop.close();
    assert.equal(page.url(),origin+ambiguous);
    assert.deepEqual(await page.evaluate(key=>[sessionStorage.getItem(key),localStorage.getItem('synthetic-draft')],draftKey),[draft,'draft bytes retained']);
    checks.push(origin+' retained both ambiguous bookmarks and the unchanged old-origin draft and request, with a separate destination tab and identity');
    await page.goto(origin+'/#/admin/setup?token=synthetic-old-issuer-token-value');
    assert.equal(await page.getByRole('link',{name:'Open Collect Admin in a new tab'}).getAttribute('href'),target+'/#/admin');
    assert.ok(page.url().includes('synthetic-old-issuer'));
    checks.push(origin+' retained the old-issuer setup link without handing its token to React');
    assert.deepEqual(fixtureProblems,[]);
    assert.deepEqual(forbidden,[]);
    assert.ok(apiReads.includes('/api/admin/auth/session'));
  } catch (error) {
    console.error(JSON.stringify({origin,location:page.url(),visible:(await page.locator('body').innerText()).slice(0,1500),apiReads,fixtureProblems,forbidden}));
    throw error;
  } finally { await context.close(); }
}
try {
  for (const origin of [original,preview]) await testOrigin(origin,production,productionPackage);
  await testOrigin(securityStage,qualification,qualificationPackage);
  if (pagesWorker) await testOrigin(pagesOrigin,production,productionPackage);
  console.log(JSON.stringify({format:'collect.admin.legacy-entry-browser.v1',status:'PASS',
    browser:browser.version(),scope:(pagesWorker?'Six':'Five')+' literal HTTPS origins fulfilled inside Chromium. All other network was blocked. The production and qualification React packages read synthetic sessions.',
    checked:checks,react_packages:{production:await packageIdentity(productionPackage,production),qualification:await packageIdentity(qualificationPackage,qualification)},
    ...(pagesBytes?{pages_bundle_sha256:digest(pagesBytes)}:{}),
    handoff_sha256:digest(await readFile(fileURLToPath(new URL('../src/handoff.mjs',import.meta.url)))),
    simulated_writes:0},null,2));
} finally { await browser.close(); }
