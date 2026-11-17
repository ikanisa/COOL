import test from 'node:test';
import assert from 'node:assert/strict';
import {nativeSmsLedgerResult} from '../scheduled-native-sms-ledger.js';

test('native ledger results expose only bounded outcomes',()=>{
 for(const state of ['posted','unmatched','already_posted','not_financial'])
  assert.deepEqual(nativeSmsLedgerResult({status:'complete',processed:1,results:[{state,rawBody:'private',memberId:'private'}]}),
   {status:'complete',processed:1,results:[{state}]});
 assert.deepEqual(nativeSmsLedgerResult({status:'complete',processed:0,results:[]}),{status:'complete',processed:0,results:[]});
});
test('malformed or unconfirmed native posting is never reported complete',()=>{
 for(const result of [null,{status:'disabled',processed:0,results:[]},
  {status:'complete',processed:2,results:[]},{status:'complete',processed:1,results:[{state:'failed'}]},
  {status:'complete',processed:1,results:[]},{status:'complete',processed:0.5,results:[]}])
  assert.deepEqual(nativeSmsLedgerResult(result),{status:'unconfirmed',code:'native_sms_ledger_unconfirmed'});
});
