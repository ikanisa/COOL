import test from 'node:test';
import assert from 'node:assert/strict';
import {nativeAutoProcessingResult} from '../scheduled-native-auto.js';

test('scheduled native results report only bounded processing metadata',()=>{
 assert.deepEqual(nativeAutoProcessingResult({status:'complete',processed:1,results:[
  {state:'completed',relation:'accepted',rawBody:'synthetic private content'}]}),
  {status:'complete',processed:1,results:[{state:'completed',relation:'accepted'}]});
 assert.equal(nativeAutoProcessingResult({status:'complete',processed:0,results:[]}).status,'complete');
 assert.equal(nativeAutoProcessingResult({status:'complete',processed:1,results:[{state:'security_message'}]}).status,'complete');
 assert.equal(nativeAutoProcessingResult({status:'complete',processed:1,results:[{state:'retry'}]}).status,'complete');
});
test('scheduled native results never report unknown, invalid or malformed work as complete',()=>{
 for(const result of [
  {status:'complete',processed:1,results:[{state:'failed'}]},
  {status:'complete',processed:1,results:[{state:'failed',reason:'provider_unavailable'}]},
  {status:'complete',processed:1,results:[{state:'completed',relation:'invalid'}]},
  {status:'complete',processed:2,results:[]},
  {status:'disabled',processed:0,results:[]},
 ]) assert.equal(nativeAutoProcessingResult(result).status,'unconfirmed');
});
