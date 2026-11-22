import postgres from 'npm:postgres@3.4.7';
import {FENCE_IO_TIMEOUT_MS} from './application-fence.js';

// Only Edge holds this database credential. SQL strings come from reviewed
// server modules. Pool ownership is local to this Edge isolate.
const pools = new Map();
export function connection(url,env={}) { return configuredConnection(url,false,env); }
export function fenceConnection(url,env={}) { return configuredConnection(url,true,env); }
function configuredConnection(url,control,env) {
  if (!url) throw new Error('COLLECT_DATABASE_URL is required.');
  const target=new URL(url);const local=['127.0.0.1','localhost','::1','[::1]'].includes(target.hostname);if(!['postgres:','postgresql:'].includes(target.protocol))throw new Error('Invalid database URL.');
  const ca=env.COLLECT_DB_CA_PEM;
  if(ca!==undefined&&(typeof ca!=='string'||!ca.startsWith('-----BEGIN CERTIFICATE-----\n')||ca.length>32768))throw new Error('Invalid database CA.');
  const poolKey=(control?'control:':'business:')+url+'\n'+(ca??'');
  if (!pools.has(poolKey)) {const options={max: control ? 1 : 4, prepare: false,
    idle_timeout: 20, connect_timeout: 10, ssl: local ? false : {rejectUnauthorized: true,...(ca?{ca}:{}),servername:target.hostname},
    types: {numeric: {to:1700,from:[1700],serialize:String,parse:value=>{const n=Number(value);if(!/^-?\d+(?:\.0+)?$/.test(value)||!Number.isSafeInteger(n))throw new Error('integer_out_of_range');return n;}},bigint: {to: 20, from: [20], serialize: String, parse: value => {
      const n = Number(value); if (!Number.isSafeInteger(n)) throw new Error('integer_out_of_range'); return n;
    }}}, onnotice: () => {}};
    pools.set(poolKey,control?leaseOwnedControlPool(()=>postgres(url,options)):postgres(url,options));
  }
  return pools.get(poolKey);
}

// Eight local slots include connection setup, WORK, original cleanup and
// quarantined pools. A settled admission does not free this separate bound.
// Control sockets have one lease owner and no retained warm idle lifetime.
export function leaseOwnedControlPool(createPool) {
  const capacity=8,waiting=[],owned=new Set();let occupied=0,ending=false;
  const unavailable=()=>new Error('collect_fence_unavailable');
  function pump(){
    while(!ending&&occupied<capacity&&waiting.length){
      const waiter=waiting.shift();clearTimeout(waiter.timer);
      if(performance.now()>=waiter.deadline){waiter.reject(unavailable());continue;}
      occupied++;
      void acquire().then(waiter.resolve,waiter.reject);
    }
  }
  function retire(entry){
    if(!entry.retirement)entry.retirement=Promise.resolve().then(()=>entry.pool.end()).then(()=>{
      owned.delete(entry);occupied--;pump();
    });
    // Keep the original end promise/options. Lost or rejected ACK quarantines
    // the slot; neither normal release nor shutdown may dispatch another end.
    void entry.retirement.catch(()=>{});return entry.retirement;
  }
  async function acquire(){
    let entry;
    try{
      entry={pool:createPool(),returned:false,retirement:null};owned.add(entry);
      const tx=await entry.pool.reserve();
      return new Proxy(tx,{get(target,key){
        if(key==='release')return()=>{if(entry.returned)return;entry.returned=true;target.release();void retire(entry);};
        return Reflect.get(target,key,target);
      }});
    }catch(error){if(entry)void retire(entry);else{occupied--;pump();}throw error;}
  }
  return Object.freeze({capacity,queueCapacity:capacity,get pendingReservations(){return waiting.length;},
    reserve(){
      if(ending)return Promise.reject(unavailable());
      return new Promise((resolve,reject)=>{
        if(occupied<capacity){occupied++;void acquire().then(resolve,reject);return;}
        if(waiting.length>=capacity){reject(unavailable());return;}
        const waiter={resolve,reject,timer:null,deadline:performance.now()+FENCE_IO_TIMEOUT_MS};
        waiter.timer=setTimeout(()=>{const i=waiting.indexOf(waiter);if(i>=0){waiting.splice(i,1);reject(unavailable());}},FENCE_IO_TIMEOUT_MS);
        waiting.push(waiter);
      });
    },
    async end(options){
      ending=true;for(const waiter of waiting.splice(0)){clearTimeout(waiter.timer);waiter.reject(unavailable());}
      // Shutdown cannot initiate end for setup, WORK or an unacknowledged
      // rollback. Only original release/setup failure may start retirement.
      const entries=[...owned];if(entries.some(entry=>!entry.retirement))throw unavailable();
      const completion=Promise.all(entries.map(entry=>entry.retirement));let timer;
      try{await Promise.race([completion,new Promise((_,reject)=>{timer=setTimeout(()=>reject(unavailable()),FENCE_IO_TIMEOUT_MS);})]);}finally{clearTimeout(timer);}
      if(owned.size)throw unavailable();
    }
  });
}
