#!/usr/bin/env node
// Check every rendered text node against its computed flat background.
// Photos, gradients and inherited opacity require visual review, not a pass.
import {readFile,writeFile} from 'node:fs/promises';
const load=await import(process.env.PLAYWRIGHT_CORE_PATH || '/Users/jeanbosco/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright-core/index.js');
const {chromium}=load.default||load;
const evidence=process.env.REVOLUT_DESIGN_EVIDENCE || '.cache/revolut-design-20260905';
const qa=JSON.parse(await readFile(process.env.PUBLIC_ROUTE_QA_REPORT || evidence+'/exhaustive-website/route_rendered_qa.json','utf8'));
const base=process.env.PUBLIC_CONTRAST_URL || 'http://127.0.0.1:4188';
const browser=await chromium.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true});const results=[];
try {
 for(const width of [320,1440]) for(const route of [...new Set(qa.results.map(r=>r.route))]) {
  const page=await browser.newPage({viewport:{width,height:1000}});await page.goto(base+route,{waitUntil:'networkidle'});
  const data=await page.evaluate(()=>{
   const rgb=s=>{const n=s.match(/[\d.]+/g)?.map(Number);return n?.length>=3?[n[0],n[1],n[2],n[3]??1]:null};
   const blend=(fg,bg)=>[0,1,2].map(i=>fg[i]*fg[3]+bg[i]*(1-fg[3]));
   const luminance=c=>c.slice(0,3).map(x=>x/255).map(x=>x<=.04045?x/12.92:((x+.055)/1.055)**2.4).reduce((s,x,i)=>s+x*[.2126,.7152,.0722][i],0);
   const failures=[],unverified=[];let checked=0;
   for(const el of document.querySelectorAll('body *')) {
    const text=[...el.childNodes].filter(n=>n.nodeType===3).map(n=>n.textContent.trim()).join(' ').trim();if(!text)continue;
    const cs=getComputedStyle(el),r=el.getBoundingClientRect();if(!r.width||!r.height||cs.visibility==='hidden'||cs.display==='none'||['SCRIPT','STYLE','NOSCRIPT'].includes(el.tagName))continue;
    const item={tag:el.tagName.toLowerCase(),classes:el.className,text:text.slice(0,140)};let stack=[],reason=null;
    for(let p=el;p;p=p.parentElement){const s=getComputedStyle(p);if(Number(s.opacity)<1){reason='opacity';break}if(s.backgroundImage!=='none'){reason='image or gradient';break}const c=rgb(s.backgroundColor);if(c){stack.push(c);if(c[3]===1)break}}
    if(reason){unverified.push({...item,reason});continue}
    let bg=[255,255,255];for(const c of stack.reverse())bg=blend(c,bg);
    const foreground=rgb(cs.color);if(!foreground){unverified.push({...item,reason:'unsupported color'});continue}
    const fg=blend(foreground,bg),l1=luminance(fg),l2=luminance(bg),ratio=(Math.max(l1,l2)+.05)/(Math.min(l1,l2)+.05);const size=parseFloat(cs.fontSize),minimum=size>=24||(size>=18.66&&Number(cs.fontWeight)>=700)?3:4.5;checked++;
    if(ratio+.03<minimum)failures.push({...item,color:cs.color,background:bg,ratio:Number(ratio.toFixed(2)),minimum});
   }
   return {checked,failures,unverified};
  });results.push({route,width,...data});await page.close();
 }
}finally{await browser.close()}
const failures=results.reduce((s,r)=>s+r.failures.length,0);const report={status:failures?'fail':'pass',scope:'Computed flat-background contrast; images, gradients and opacity remain visually unverified',checkedAt:new Date().toISOString(),failures,results};await writeFile(process.env.PUBLIC_CONTRAST_REPORT || evidence+'/website-text-contrast.json',JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({status:report.status,failures,checked:results.reduce((s,r)=>s+r.checked,0),unverified:results.reduce((s,r)=>s+r.unverified.length,0)}));process.exitCode=failures?1:0;
