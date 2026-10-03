import test from 'node:test';
import assert from 'node:assert/strict';
import {EventEmitter} from 'node:events';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {runInNewContext} from 'node:vm';
import {classifyCollectDiagnostic, observeCollectDiagnostics, collectDiagnosticFailures,
  sanitizeCollectDiagnosticLog, collectDiagnosticSourceSnapshot} from '../qa/collect_diagnostic_observer.mjs';

const defaults = {collect_diagnostic: 1, code: 'startupReady', severity: 'info',
  surface: 'member', environment: 'production', build_version: '1.2.3+4', attempt: 1, elapsed_ms: 0};
const wire = overrides => JSON.stringify({...defaults, ...overrides});
const codes = {startupStarted:'info',startupWaiting:'info',startupReady:'info',
  startupTimedOut:'warning',diagnosticsSuppressed:'warning',startupFailed:'error',frameworkFailure:'error',platformFailure:'error'};

test('Classifier covers the actual Dart boundary enum, fields and severity contract', async () => {
  const source = await readFile(new URL('../../lib/core/logging/app_logger.dart', import.meta.url), 'utf8');
  const declared = source.match(/enum CollectDiagnosticCode\s*\{([^}]+)\}/)[1].match(/\w+/g);
  assert.deepEqual([...declared].sort(), Object.keys(codes).sort());
  const fields = [...source.match(/final event = jsonEncode\(\{([\s\S]*?)\}\);/)[1].matchAll(/'([^']+)'\s*:/g)].map(m => m[1]);
  assert.deepEqual(fields.sort(), Object.keys(defaults).sort());
  assert.match(source, /startupFailed => 'error'/);
  assert.match(source, /diagnosticsSuppressed => 'warning'/);
  assert.match(source, /_writeSafeEvent\(String event\) => debugPrint\(event\)/);
});
for (const [code,severity] of Object.entries(codes)) test('Declared '+code+' is '+(severity==='info'?'observation only':'a failure'), () => {
  const r = classifyCollectDiagnostic(wire({code,severity}));
  assert.equal(r.failure,severity!=='info'); assert.equal(r.event.code,code);
});

test('Fixed numeric/build boundary endpoints remain supported', () => {
  for (const event of [{attempt:1000,elapsed_ms:86400000},{build_version:'unknown',environment:'unknown',surface:'admin'}]) {
    assert.equal(classifyCollectDiagnostic(wire(event)).failure,false);
  }
});
const bad = [
  {collect_diagnostic:2},{collect_diagnostic:'1'},{code:'unrecognized'},{code:'constructor'},
  {code:['startupReady']},{code:'startupFailed',severity:'info'},{severity:'warning'},
  {surface:'private-user'},{environment:'https://private.invalid'},{build_version:'token-secret'},
  {build_version:'1.2.3\n'},{build_version:'1'.repeat(33)+'.2.3'},
  {attempt:0},{attempt:1001},{attempt:1.5},{attempt:'1'},{elapsed_ms:-1},{elapsed_ms:86400001},{elapsed_ms:1.5},
  {reason:'private-secret'},{session_id:'private-secret'},{url:'https://private.invalid/token-secret'},
];
for (const mutation of bad) test('Invalid declared payload fails safely: '+JSON.stringify(mutation), () => {
  const result = classifyCollectDiagnostic(wire(mutation));
  assert.equal(result.failure,true); assert.equal(result.event,null);
  assert(!JSON.stringify(result).includes('private-secret'));
  assert(!JSON.stringify(result).includes('token-secret'));
});
test('Missing fields, malformed/oversized declarations and duplicate keys fail without raw text', () => {
  const missing = {...defaults}; delete missing.attempt;
  for (const text of [JSON.stringify(missing),'{"collect_diagnostic":1,"secret":"private-secret",',
    '{"collect_diagnostic":1,"secret":"'+ 'private-secret'.repeat(1000)+'"}',
    wire().replace('"code":"startupReady"','"code":"startupFailed","code":"startupReady"'),
    wire().replace('"code":"startupReady"','"code":"startupFailed","\\u0063ode":"startupReady"'),
    '['+wire()+']']) {
    const result=classifyCollectDiagnostic(text); assert.equal(result.failure,true); assert.equal(result.event,null);
    assert(!JSON.stringify(result).includes('private-secret'));
  }
});
test('Ordinary console output and JSON cannot manufacture startup acceptance', () => {
  for(const text of ['Rendered successfully','{"code":"startupReady"}','collect_diagnostic is the contract name',null]) {
    assert.equal(classifyCollectDiagnostic(text),null);
  }
  assert.equal(collectDiagnosticFailures([{level:'log',text:wire()}]).length,0);
  assert.equal(classifyCollectDiagnostic(wire()).reason,'observed_info');
});
test('Real EventEmitter listener catches failures on every console level and detaches', () => {
  const page=new EventEmitter(),failures=[]; const detach=observeCollectDiagnostics(page,v=>failures.push(v));
  for(const level of ['log','info','debug','warning','error','assert']) {
    for(const [code,severity]of Object.entries(codes))page.emit('console',{text:()=>wire({code,severity}),type:()=>level});
  }
  assert.equal(failures.length,30); assert(failures.every(v=>v.failure));
  detach(); page.emit('console',{text:()=>wire({code:'startupFailed',severity:'error'})}); assert.equal(failures.length,30);
});
test('Declared malformed console entries lose raw text and untrusted URL/detail fields', () => {
  const entry={level:'warning',text:'{"collect_diagnostic":1,"secret":"private-secret",',url:'private-secret',detail:'private-secret'};
  const safe=sanitizeCollectDiagnosticLog(entry);assert.equal(safe.diagnostic.failure,true);
  assert(!JSON.stringify(safe).includes('private-secret'));assert.equal(safe.level,'warning');
  const ordinary={level:'error',text:'Uncaught error'};assert.equal(sanitizeCollectDiagnosticLog(ordinary),ordinary);
});

const cdpSource=await readFile(new URL('../admin_pwa_runtime_smoke.mjs',import.meta.url),'utf8');
const CdpClient=runInNewContext(cdpSource.match(/class CdpClient \{[\s\S]*?\n\}/)[0]+'\nCdpClient');
const body=cdpSource.slice(cdpSource.indexOf('// BEGIN runtime console failure collection'),cdpSource.indexOf('// END runtime console failure collection'));
const ignore=runInNewContext(cdpSource.match(/function isIgnorableBrowserRequest\(entry\) \{[\s\S]*?\n\}/)[0]+'\nisIgnorableBrowserRequest');
const errors=runInNewContext(body+'\nruntimeConsoleFailures',{collectDiagnosticFailures,sanitizeCollectDiagnosticLog,isIgnorableBrowserRequest:ignore});
test('Actual maintained CDP event handling observes log-level handled failures and preserves page exceptions', () => {
  const cdp=new CdpClient('not-connected');
  for(const[code,severity]of Object.entries(codes))cdp.handleMessage(JSON.stringify({method:'Runtime.consoleAPICalled',params:{type:'log',args:[{type:'string',value:wire({code,severity})}]}}));
  cdp.handleMessage(JSON.stringify({method:'Runtime.exceptionThrown',params:{exceptionDetails:{text:'Uncaught runtime exception'}}}));
  const result=errors(cdp.logs);assert.equal(result.length,6);assert(result.some(e=>e.text==='Uncaught runtime exception'));
  assert.equal(result.filter(e=>e.diagnostic?.failure).length,5);
});
test('Diagnostic declarations cannot exploit existing favicon ignore; raw malformed payload is not reported', () => {
  const logs=[{level:'error',text:'{"collect_diagnostic":1,"secret":"private-secret favicon.ico",'},
    {level:'error',text:'favicon.ico failed'},{level:'assert',text:'assertion failed'},
    {level:'error',text:wire()}];
  const result=errors(logs);assert.equal(result.length,3);
  assert(!JSON.stringify(result).includes('private-secret'));
  assert(result.some(e=>e.text==='assertion failed'));
  assert(result.some(e=>e.diagnostic?.reason==='observed_info')); // Original error-level rule is retained.
});
test('Observer and actual recorder bytes both enter source provenance', async () => {
  const recorder=new URL('../admin_pwa_runtime_smoke.mjs',import.meta.url);
  const snapshot=await collectDiagnosticSourceSnapshot(recorder);
  assert.deepEqual(Object.keys(snapshot),['scripts/qa/collect_diagnostic_observer.mjs','scripts/admin_pwa_runtime_smoke.mjs']);
  for(const[path,hash]of Object.entries(snapshot))assert.equal(hash,createHash('sha256').update(await readFile(new URL('../../'+path,import.meta.url))).digest('hex'));
  await assert.rejects(collectDiagnosticSourceSnapshot(new URL('../../pubspec.yaml',import.meta.url)),/repository script/);
});

const callers=['qa/public_browser_app_media.mjs','admin_pwa_browser_qa.mjs','admin_pwa_runtime_smoke.mjs',
  'qa/current_browser_lifecycle.mjs','qa/local_browser_lifecycle.mjs','qa/admin_design_flow_browser_qa.mjs','qa/admin_pwa_lifecycle_qa.mjs'];
for(const caller of callers)test('Maintained caller keeps runtime failure checks and observer provenance: '+caller,async()=>{
  const source=await readFile(new URL('../'+caller,import.meta.url),'utf8');
  assert.match(source,/from ['"].*collect_diagnostic_observer\.mjs['"]/);
  if(caller==='admin_pwa_runtime_smoke.mjs'){
    assert.match(source,/Runtime\.exceptionThrown/);assert.match(source,/runtime\.ok && errors\.length === 0/);
  }else assert.match(source,/\.on\('pageerror'/);
  if(['qa/current_browser_lifecycle.mjs','qa/local_browser_lifecycle.mjs','qa/admin_pwa_lifecycle_qa.mjs'].includes(caller)){
    assert(source.includes("'scripts/qa/collect_diagnostic_observer.mjs'"));
    assert.match(source,/context\.on\('page',\s*observe(?:Page)?\)/);
  }else{
    assert.match(source,/diagnostic_observer_sources_before/);assert.match(source,/diagnostic_observer_sources_after/);
  }
});
