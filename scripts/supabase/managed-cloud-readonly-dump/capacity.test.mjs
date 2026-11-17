import test from 'node:test';
import assert from 'node:assert/strict';
import {MAX_DUMP_BYTES,OVERHEAD_BYTES,RESERVE_BYTES,requireAvailable,CapacityError} from './capacity.mjs';
const code=x=>e=>e instanceof CapacityError&&e.code===x;
test('capacity budget refuses insufficient space before dispatch and during output',()=>{
 const initial=BigInt(MAX_DUMP_BYTES+RESERVE_BYTES+OVERHEAD_BYTES);
 assert.doesNotThrow(()=>requireAvailable(initial,MAX_DUMP_BYTES));
 assert.throws(()=>requireAvailable(initial-1n,MAX_DUMP_BYTES),code('capacity_refused'));
 const remaining=MAX_DUMP_BYTES-256*1024*1024;
 assert.doesNotThrow(()=>requireAvailable(BigInt(remaining+RESERVE_BYTES+OVERHEAD_BYTES),remaining));
 assert.throws(()=>requireAvailable(BigInt(remaining+RESERVE_BYTES+OVERHEAD_BYTES-1),remaining),code('capacity_refused'));
 assert.throws(()=>requireAvailable(-1n,remaining),code('capacity_unavailable'));
});
