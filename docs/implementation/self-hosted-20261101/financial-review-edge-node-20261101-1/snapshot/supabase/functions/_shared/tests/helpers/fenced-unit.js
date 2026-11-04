// Test-only synthetic control I/O. The production admission implementation is
// still used; no runtime flag, test environment escape or forged work object.
import {deferredApplicationWork} from '../../application-fence.js';
export const SYNTHETIC_FENCE_SOURCE='a'.repeat(64);
const owned=new Set(),closed=new WeakSet();
export function ownFixtureWork(work){owned.add(work);return work;}
export function syntheticFenceBackend(){
 const rows=new Map();return {rows,async register(id,source,kind){const row={contractVersion:1,admissionId:id,epoch:1,sourceSha256:source,state:'active',mode:'open',kind};rows.set(id,row);return {...row};},async lease(id){return{row:{...rows.get(id)},async assert(){return {...rows.get(id)};},async release(){}};},async close(id,epoch,source,state,reason,externalDispatches,uncertainDispatches){const row={...rows.get(id),state,reason,externalDispatches,uncertainDispatches};rows.set(id,row);return {...row};},async status(id){return{...rows.get(id),found:rows.has(id)};}};
}
export function syntheticFixtureWork(){return ownFixtureWork(deferredApplicationWork({backend:syntheticFenceBackend(),sourceSha256:SYNTHETIC_FENCE_SOURCE,kind:'http_collect'}));}
export function fixtureEnvironment(env){
 if(env&&typeof env==='object'&&(!env.COLLECT_FENCE_WORK||closed.has(env.COLLECT_FENCE_WORK)))env.COLLECT_FENCE_WORK=env.DB?.applicationWork??syntheticFixtureWork();
 return env;
}
export function fencedCall(fn,index,args){if(args[index]&&typeof args[index]==='object')fixtureEnvironment(args[index]);return fn(...args);}
export async function finishFixtureWork(){const current=[...owned];owned.clear();for(const work of current){try{await work.finish();}finally{closed.add(work);}}}
/** @type {typeof Deno.test} */
export const fencedTest=(...args)=>{
 const wrap=fn=>async(...values)=>{try{return await fn(...values);}finally{await finishFixtureWork();}};
 if(typeof args[0]==='object')return Deno.test({...args[0],fn:wrap(args[0].fn)});
 const index=args.findLastIndex(value=>typeof value==='function');if(index>=0)args[index]=wrap(args[index]);return Deno.test(...args);
};
