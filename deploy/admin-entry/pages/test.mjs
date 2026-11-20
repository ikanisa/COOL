import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
import entry from './entry.mjs';
import shared from '../src/index.mjs';

const origin = 'https://cool-admin-212.pages.dev', original = 'https://admin.collect.ikanisa.com';
const destination = 'https://platform-admin.collect.ikanisa.com';
const implementations = [['source', entry]];
if (process.env.PAGES_WORKER_BUNDLE) {
  const bytes = await readFile(process.env.PAGES_WORKER_BUNDLE);
  // Data URLs make accidental external module dependencies fail at load time.
  implementations.push(['standalone bundle', (await import('data:text/javascript;base64,'+bytes.toString('base64'))).default]);
}
for (const [name,handler] of implementations) {
  const call = (path, opts={}) => handler.fetch(new Request(origin+path,{headers:{Accept:'text/html'},...opts}));
  test(name+' admits only the canonical project host and retires all historical versioned workers', async () => {
    for (const other of [original,'http://cool-admin-212.pages.dev','https://cool-admin-212.pages.dev:448','https://f15c33ba.cool-admin-212.pages.dev','https://cool-admin-212.pages.dev.example']) {
      const response=handler.fetch(new Request(other+'/')); assert.equal(response.status,403); assert.equal(response.headers.get('Location'),null);
    }
    const versions=['b96b6c5ca48759bf','ec92f3e24c2dca04','a66b68582b43d5d3','141ff1ab8fa3c903'];
    const expected=await shared.fetch(new Request(original+'/custom-sw.js')).text();
    for (const version of versions) {
      const response=call('/custom-sw.js?v=collect-admin-'+version);
      assert.equal(response.status,200); assert.equal(response.headers.get('Service-Worker-Allowed'),'/');
      assert.match(response.headers.get('Content-Type'),/javascript/); assert.match(response.headers.get('Cache-Control'),/no-store/);
      assert.equal(await response.text(),expected); assert.doesNotMatch(expected,/skipWaiting|clients\.claim|caches\.delete/);
    }
  });
  test(name+' preserves cookie/credential privacy, falls closed on old APIs and reads no write body', async () => {
    const response=call('/admin/groups',{headers:{Accept:'text/html',Cookie:'owner=only-old'}});
    assert.match(await response.text(),/<main data-preserve>/); assert.equal(response.headers.has('Set-Cookie'),false);
    assert.equal(call('/api/admin/auth/session').status,410);assert.equal(call('/main.dart.js').status,410);
    assert.equal(call('/',{headers:{Accept:'text/html',Authorization:'Bearer fixture'}}).status,403);
    const pending=new Request(origin+'/api/admin/requests',{method:'POST',body:'synthetic-pending-original'});
    assert.equal(handler.fetch(pending).status,405);assert.equal(pending.bodyUsed,false);
  });
  test(name+' preserves former Flutter-only bookmarks and sends equivalent Groups routes to React', async () => {
    const code=await call('/admin-entry-handoff.js').text();
    for (const [path,wanted] of [['/#/admin/payment-events/synthetic',null],['/admin/sms?q=1',null],['/admin/groups?sort=name','/admin/groups?sort=name'],['/#/admin/members','/admin/members']]) {
      const urls=[];const loc=new URL(path,origin);loc.replace=url=>urls.push(url);
      const initial=destination+'/#/admin';const elements={primary:{href:initial},alternative:{},guidance:{}};
      const listeners=[];
      await vm.runInNewContext(code,{URL,window:{location:loc,addEventListener:type=>listeners.push(type),history:{state:null},sessionStorage:{length:0},localStorage:{length:0},caches:{keys:async()=>[]},indexedDB:{databases:async()=>[]},navigator:{}},document:{getElementById:id=>elements[id],querySelector:()=>null}});
      assert.deepEqual(listeners,['hashchange']);
      assert.deepEqual(urls,wanted?[destination+'/#'+wanted]:[]);assert.equal(elements.primary.href,wanted?destination+'/#'+wanted:initial);
    }
  });
}
