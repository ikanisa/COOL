import test from 'node:test';import assert from 'node:assert/strict';
import {assertCompleteTap} from './report.mjs';
const good='TAP version 13\nok 1 - first\nok 2 - second\n1..2\n# tests 2\n# pass 2\n# fail 0\n# cancelled 0\n# skipped 0\n# todo 0\n';
test('qualification accepts exactly the named successful tests',()=>assert.equal(assertCompleteTap(good,['first','second']),2));
test('a green process cannot hide skips, missing cases or altered counts',()=>{
 for(const bad of [good.replace('ok 2 - second','ok 2 - second # SKIP'),good.replace('# skipped 0','# skipped 1'),
  good.replace('ok 2 - second','ok 2 - other'),good.replace('# pass 2','# pass 1'),
  good.replace('# cancelled 0','# cancelled 1'),good.replace('# todo 0','# todo 1'),good.replace('# fail 0','# fail 1'),
  good.replace('# tests 2','# tests 3'),good+'# pass 2\n'])assert.throws(()=>assertCompleteTap(bad,['first','second']));
});
