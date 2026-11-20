import test from 'node:test';import assert from 'node:assert/strict';
import {assertCompleteTap} from './report.mjs';
const expected=['child','parent'];
const good='TAP version 13\n    ok 1 - child\nok 1 - parent\n1..1\n# tests 2\n# pass 2\n# fail 0\n# cancelled 0\n# skipped 0\n# todo 0\n';
test('nested named cases are all required',()=>assert.equal(assertCompleteTap(good,expected),2));
test('a green process cannot hide a skip or a missing nested case',()=>{
 for(const bad of [good.replace('child','child # SKIP'),good.replace('# skipped 0','# skipped 1'),good.replace('child','other'),
  good.replace('# pass 2','# pass 1'),good.replace('# cancelled 0','# cancelled 1'),good.replace('# todo 0','# todo 1'),
  good.replace('# fail 0','# fail 1'),good.replace('# tests 2','# tests 3'),good+'# pass 2\n'])
  assert.throws(()=>assertCompleteTap(bad,expected));
});
