"use strict";
const fs = require("fs"), path = require("path"), http = require("http"), crypto = require("crypto");
const root = process.cwd(), packet = path.join(root, "docs/release/asset-build-hygiene-2026-09-30/public-browser-local-network-attempt144");
const { requireLoopbackOrigin, installLocalNetworkFence } = require(path.join(root,"scripts/qa/public_browser_local_network.cjs"));
const playwright = require("/Users/jeanbosco/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright-core/index.js");
const assert = require("assert");
const sha = p => crypto.createHash("sha256").update(fs.readFileSync(p)).digest("hex");
(async()=>{
  const denied=[]; let localCount=0,trapCount=0; const checks=[];
  const local=http.createServer((req,res)=>{ localCount++;res.end(req.url==="/"?"<!doctype html><title>Local probe</title><h1>Local network</h1>":"local resource"); });
  const trap=http.createServer((req,res)=>{ trapCount++;res.end("unexpected arrival"); });
  await new Promise(r=>local.listen(0,"127.0.0.1",r));await new Promise(r=>trap.listen(0,"127.0.0.1",r));
  const base=`http://127.0.0.1:${local.address().port}/`, forbidden=`http://127.0.0.1:${trap.address().port}`;
  const browser=await playwright.chromium.launch({executablePath:"/Volumes/PRO-G40/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",headless:true,args:["--disable-background-networking","--disable-component-update","--no-first-run"]});
  try {
    const page=await browser.newPage({serviceWorkers:"block"});await installLocalNetworkFence(page,base,denied);
    assert.equal((await page.goto(base)).status(),200);checks.push("allowed loopback document");
    assert.equal(await page.evaluate(()=>fetch("/asset").then(r=>r.text())),"local resource");checks.push("allowed exact-origin resource");
    await page.route("**/c/**",async route=>{if(new URL(route.request().url()).origin!==new URL(base).origin) await route.fallback();else await route.fulfill({body:"share document"});});
    assert.equal(await page.evaluate(()=>fetch("/c/good").then(r=>r.text())),"share document");checks.push("local share interception retained");
    for(const tail of ["/ordinary?private=do-not-record","/c/bypass?private=do-not-record"]){assert.equal(await page.evaluate(url=>fetch(url).then(()=>"unexpected",()=>"blocked"),forbidden+tail),"blocked");}
    assert.equal(denied.length,2);assert.equal(trapCount,0);assert(!JSON.stringify(denied).includes("do-not-record"));checks.push("different-origin traffic blocked before server arrival");checks.push("share page fallback honors context fence");checks.push("denial receipt excludes paths queries fragments and bodies");
    for(const url of ["https://127.0.0.1/","http://localhost/","http://127.0.0.1@evil.example/","http://user:pass@127.0.0.1/","http://192.0.2.1/"]){assert.throws(()=>requireLoopbackOrigin(url));}checks.push("nonloopback HTTPS and credentialed base rejected");
    await page.close();
    fs.writeFileSync(path.join(packet,"actual-browser-probe.json"),JSON.stringify({status:"pass",completed_at:new Date().toISOString(),checks,allowed_http_arrivals:localCount,denied_page_requests:denied,forbidden_server_arrivals:trapCount,helper_sha256:sha(path.join(root,"scripts/qa/public_browser_local_network.cjs")),route_tool_sha256:sha(path.join(root,"scripts/public_website_route_rendered_qa.js")),scope:"Actual local Chrome HTTP origin/adversarial share-override probe; no external address contacted, no OS background-network or provider acceptance claim"},null,2)+"\n");
    console.log("ACTUAL LOCAL NETWORK FENCE PASS",checks.length);
  } finally {await browser.close();await Promise.all([new Promise(r=>local.close(r)),new Promise(r=>trap.close(r))]);}
})().catch(e=>{console.error(e);process.exit(1);});
