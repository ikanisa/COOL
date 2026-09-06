#!/usr/bin/env node
// Isolated Admin fixture dialogs: open through semantics, inspect, then cancel.
import {mkdir,writeFile} from 'node:fs/promises';
import {resolve,join} from 'node:path';
const base=process.env.ADMIN_DESIGN_QA_URL || 'http://127.0.0.1:4189';
if(!['localhost','127.0.0.1','[::1]'].includes(new URL(base).hostname)) throw Error('Local fixture build required');
const out=resolve(process.env.ADMIN_DESIGN_QA_OUT || '.cache/revolut-design-20260905/exhaustive-admin-flows');
const loaded=await import(process.env.PLAYWRIGHT_CORE_PATH || '/Users/jeanbosco/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright-core/index.js');
const {chromium}=loaded.default || loaded;
const viewports=[{name:'compact_320x740',width:320,height:740},{name:'compact_390x844',width:390,height:844},{name:'tablet_834x1194',width:834,height:1194},{name:'desktop_1440x900',width:1440,height:900}];
const flows=[
 {name:'country-menu',route:'/admin/groups',steps:['Country: All countries'],marker:'Malta',menu:true},
 {name:'rwanda-scope',route:'/admin/groups',steps:['Country: All countries','Rwanda'],marker:'Country scope: Rwanda',state:true},
 {name:'malta-scope',route:'/admin/groups',steps:['Country: All countries','Malta'],marker:'Country scope: Malta',state:true},
 {name:'other-country-scope',route:'/admin/groups',steps:['Country: All countries','Other countries'],marker:'Country scope: Other countries',state:true},
 {name:'operator-menu',route:'/admin/groups',steps:['Operator menu'],marker:'Sign out',menu:true},
 {name:'create-group-menu',route:'/admin/groups',steps:['Create group'],marker:'Create assisted group',menu:true},
 {name:'create-assisted-group',route:'/admin/groups',steps:['Create group','Create assisted group'],marker:'Create assisted group'},
 {name:'create-public-group',route:'/admin/groups',steps:['Create group','Create public group'],marker:'Create public group'},
 {name:'create-payee',route:'/admin/payees',steps:['Create payee'],marker:'Create official payee'},
 {name:'edit-payee',route:'/admin/payees',steps:['Edit IKANISA LTD'],marker:'Edit official payee'},
 {name:'deactivate-payee',route:'/admin/payees',steps:['Deactivate IKANISA LTD'],marker:'Deactivate official payee'},
 {name:'allocate-rwanda-payment',route:'/admin/reconciliations',steps:['Allocate Unallocated transaction 681601'],marker:'Allocate transaction'},
 {name:'propose-bank-allocation',route:'/admin/reconciliations',steps:['Allocate Unallocated transaction 681602'],marker:'Propose allocation'},
 {name:'feature-flag-reason',route:'/admin/feature-flags',steps:['Disable feature flag Diaspora bank transfers'],marker:'Disable feature flag'},
 {name:'notification-retry-reason',route:'/admin/notifications/notification-1',steps:['Retry failed delivery'],marker:'Retry notification'},
 {name:'revoke-admin-approval',route:'/admin/admin-users/admin-user-1',steps:['Revoke approval'],marker:'Revoke approval'},
 {name:'deactivate-admin',route:'/admin/admin-users/admin-user-1',steps:['Deactivate Admin'],marker:'Deactivate Admin'},
 {name:'status-filter',route:'/admin/groups',steps:['Filter: All'],marker:'All',menu:true},
 {name:'sort-order',route:'/admin/groups',steps:['Sort: Newest'],marker:'Newest',menu:true},
 {name:'user-detail',route:'/admin/users/user-1',steps:[],marker:'User detail'},
 {name:'unknown-route',route:'/admin/unavailable-design-fixture',steps:[],marker:'Admin route not found'},
];
async function labels(page){return page.locator('flt-semantics[aria-label],flt-semantics[role]').evaluateAll(es=>es.map(e=>(e.getAttribute('aria-label')||e.textContent||'').replace(/\s+/g,' ').trim()).filter(Boolean))}
async function activate(page,name){
 for(let i=0;i<9;i++){
  const starts=new RegExp('^'+name.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')+'(?:\\s|$)');
  const exact=page.getByRole('button',{name,exact:true});
  const target=(await exact.count())?exact:page.getByRole('button',{name:starts}).or(page.getByRole('menuitem',{name:starts}));
  if(await target.count()){await target.last().focus();await page.keyboard.press('Enter');await page.waitForTimeout(250);return;}
  // Native Flutter lists expose semantics for visible content only.
  await page.mouse.move(page.viewportSize().width*.8,page.viewportSize().height*.7);await page.mouse.wheel(0,240);await page.waitForTimeout(150);
 }
 throw Error('Unavailable control: '+name);
}
await mkdir(join(out,'screenshots'),{recursive:true});
const browser=await chromium.launch({headless:true,executablePath:process.env.ADMIN_PWA_CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});const results=[];
try{for(const viewport of viewports)for(const flow of flows.filter(f=>!process.env.ADMIN_DESIGN_QA_FLOW || f.name===process.env.ADMIN_DESIGN_QA_FLOW)){
 const context=await browser.newContext({viewport}),page=await context.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));let screenshot;let checks={};
 try{
  await page.goto(base+'/#'+flow.route,{waitUntil:'domcontentloaded'});
  await page.waitForFunction(()=>document.querySelector('flt-semantics-placeholder')||document.querySelectorAll('flt-semantics').length>5);
  await page.evaluate(()=>document.querySelector('flt-semantics-placeholder')?.click());await page.waitForFunction(()=>document.querySelectorAll('flt-semantics').length>5);await page.waitForTimeout(450);
  checks.fixture=(await labels(page)).some(x=>x.includes('Collect admin evidence mode marker'));
  if(flow.name==='unknown-route'){await page.goto(base+'/#/admin');await page.waitForTimeout(650);checks.fixture=(await labels(page)).some(x=>x.includes('Collect admin evidence mode marker'));await page.goto(base+'/#'+flow.route);await page.waitForTimeout(650);}
  if(!checks.fixture)throw Error('Fixture marker missing');
  for(const step of flow.steps) await activate(page,step);
  await page.waitForFunction(marker=>[...document.querySelectorAll('flt-semantics')].some(e=>(e.getAttribute('aria-label')||e.textContent||'').includes(marker)),flow.marker,{timeout:5000});
  const shown=await labels(page);checks.expectedState=shown.some(x=>x.includes(flow.marker));
  checks.noHorizontalOverflow=await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1);
  screenshot=join(out,'screenshots',flow.name+'_'+viewport.name+'.png');await page.screenshot({path:screenshot});
  if(flow.steps.length && !flow.state){
   if(flow.menu){const first=page.getByRole('menuitem').first();if(await first.count())await first.focus();await page.keyboard.press('Escape');}
   else {await activate(page,'Cancel');}
   await page.waitForTimeout(600);
   checks.dismissed=await page.locator('[role=dialog],[role=alertdialog],[role=menu]').count()===0;
  }
  checks.noBrowserErrors=errors.length===0;
  results.push({...flow,viewport:viewport.name,screenshot,status:Object.values(checks).every(Boolean)?'pass':'fail',checks,observedMarkers:shown.filter(x=>x.includes(flow.marker)).slice(0,3)});
 }catch(error){results.push({...flow,viewport:viewport.name,screenshot,status:'fail',checks,error:String(error)});}finally{await context.close();}
}}
finally{await browser.close();}
const report={status:results.every(r=>r.status==='pass')?'pass':'fail',generatedAt:new Date().toISOString(),scope:process.env.ADMIN_DESIGN_QA_FLOW?'Partial diagnostic run':'Local fixture UI only; dialogs cancelled before mutations',results};await writeFile(join(out,'summary.json'),JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({status:report.status,count:results.length,failures:results.filter(r=>r.status!=='pass').map(r=>({name:r.name,viewport:r.viewport,checks:r.checks,error:r.error}))},null,2));process.exitCode=report.status==='pass'?0:1;
