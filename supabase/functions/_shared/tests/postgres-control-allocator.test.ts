// New allocator branches use controlled factories, with native SQL/driver proof
// separately retained in the exact-bound native qualification receipt.
const runtime:any=await import('../postgres.js');
const {reserveDatabaseConnection}=await import('../application-fence.js');
const need=(v:unknown)=>{if(!v)throw Error('ALLOCATOR_FAILURE_INVARIANT');};
const pause=(ms:number)=>new Promise<void>(r=>setTimeout(r,ms));
async function rejected(p:Promise<any>){try{await p;}catch{return;}throw Error('UNEXPECTED_SUCCESS');}
async function refused(p:Promise<any>){try{await p;throw Error('UNEXPECTED_SUCCESS');}catch(e){need((e as any)?.code==='application_fence_unavailable');}}
Deno.test('8 permanent quarantines bound queue8; repeated timed-out waiters dequeue and never create another pool',async()=>{
 let created=0,ended=0,releases=0;
 const pool=runtime.leaseOwnedControlPool(()=>{created++;return {async reserve(){return {release(){releases++;}};},async end(){ended++;throw Error('SYNTHETIC_END_ACK_REJECTION');}};});
 const leased=await Promise.all(Array.from({length:8},()=>pool.reserve()));leased.forEach(tx=>{tx.release();tx.release();});await pause(20);
 for(let round=0;round<2;round++){
  const waiters=Array.from({length:8},()=>refused(reserveDatabaseConnection(pool)));await pause(20);need(pool.pendingReservations===8);
  await Promise.all(Array.from({length:40},()=>refused(reserveDatabaseConnection(pool))));need(pool.pendingReservations===8&&created===8);
  await Promise.all(waiters);await pause(20);need(pool.pendingReservations===0&&created===8&&ended===8&&releases===8);
 }
 await rejected(pool.end({timeout:0}));await rejected(pool.end({timeout:1}));need(ended===8&&pool.pendingReservations===0);
});
Deno.test('original pending pool.end is never repeated or given replacement options; shutdown rejects until original ACK',async()=>{
 let created=0,ended=0;const options:any[]=[],ack=Promise.withResolvers<void>();
 const pool=runtime.leaseOwnedControlPool(()=>{created++;return {async reserve(){return {release(){}};},async end(value:any){ended++;options.push(value);await ack.promise;}};});
 const held=await Promise.all(Array.from({length:8},()=>pool.reserve()));held.forEach(tx=>tx.release());await pause(20);
 await rejected(pool.end({timeout:0}));need(ended===8&&options.every(x=>x===undefined)&&created===8);ack.resolve();need(await pool.end({timeout:1})===undefined);need(ended===8);
});
Deno.test('failed reservation retains slot until original end ACK; expired queued waiter never creates late pool',async()=>{
 let created=0,ended=0;const ack=Promise.withResolvers<void>();
 const pool=runtime.leaseOwnedControlPool(()=>{const n=++created;return {async reserve(){if(n===1)throw Error('SYNTHETIC_RESERVE_REJECTION');return {release(){}};},async end(){ended++;if(n===1)await ack.promise;}};});
 await rejected(pool.reserve());const held=await Promise.all(Array.from({length:7},()=>pool.reserve()));need(created===8&&ended===1);await refused(reserveDatabaseConnection(pool));await pause(20);need(created===8&&ended===1&&pool.pendingReservations===0);
 ack.resolve();await pause(30);need(created===8&&ended===1);const fresh=await pool.reserve();fresh.release();held.forEach(tx=>tx.release());await pause(20);need(created===9&&ended===9);need(await pool.end()===undefined);
});
Deno.test('synchronous factory failure does not spend a slot or construct an extra connection',async()=>{
 let created=0,ended=0;
 const pool=runtime.leaseOwnedControlPool(()=>{if(++created===1)throw Error('SYNTHETIC_FACTORY_REJECTION');return {async reserve(){return {release(){}};},async end(){ended++;}};});
 await rejected(pool.reserve());const held=await Promise.all(Array.from({length:8},()=>pool.reserve()));need(created===9);held.forEach(tx=>tx.release());await pause(20);need(ended===8);need(await pool.end()===undefined);
});

Deno.test('allocation rejects an expired waiter even when its timer callback has not run',async()=>{
 const descriptor=Object.getOwnPropertyDescriptor(performance,'now'),real=performance.now.bind(performance);let offset=0;
 Object.defineProperty(performance,'now',{configurable:true,value:()=>real()+offset});
 try{
  let created=0,ended=0;const ack=Promise.withResolvers<void>();
  const pool=runtime.leaseOwnedControlPool(()=>{created++;return {async reserve(){return {release(){}};},async end(){ended++;await ack.promise;}};});
  const held=await Promise.all(Array.from({length:8},()=>pool.reserve()));const expired=rejected(pool.reserve());need(pool.pendingReservations===1);
  offset=6000;held.forEach(tx=>tx.release());ack.resolve();await expired;need(pool.pendingReservations===0&&created===8&&ended===8);need(await pool.end()===undefined);
 }finally{if(descriptor)Object.defineProperty(performance,'now',descriptor);else Reflect.deleteProperty(performance,'now');}
});

Deno.test('shutdown cannot initiate first end during original reservation setup or leased WORK',async()=>{
 let ends=0;const setup=Promise.withResolvers<any>();
 const pool=runtime.leaseOwnedControlPool(()=>({reserve:()=>setup.promise,async end(){ends++;}}));
 const reserving=rejected(pool.reserve());await rejected(pool.end({timeout:0}));need(ends===0);setup.reject(Error('SYNTHETIC_SETUP_FAILURE'));await reserving;await pause(20);need(ends===1);need(await pool.end()===undefined);need(ends===1);
 let heldEnds=0;const held=runtime.leaseOwnedControlPool(()=>({async reserve(){return {release(){}};},async end(){heldEnds++;}}));
 const tx=await held.reserve();await rejected(held.end({timeout:0}));need(heldEnds===0);tx.release();need(await held.end({timeout:0})===undefined);need(heldEnds===1);
});
