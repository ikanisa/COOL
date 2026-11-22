// Conservative local budget; this does not predict pg_dump's output size.
import {statfsSync} from 'node:fs';
export const MAX_DUMP_BYTES=1024*1024*1024;
export const RESERVE_BYTES=1024*1024*1024;
export const OVERHEAD_BYTES=32*1024*1024;
export class CapacityError extends Error{constructor(code){super(code);this.name='CapacityError';this.code=code;}}
export function requireAvailable(available,remaining){
 if(typeof available!=='bigint'||available<0n||!Number.isSafeInteger(remaining)||remaining<0||remaining>MAX_DUMP_BYTES)throw new CapacityError('capacity_unavailable');
 if(available<BigInt(remaining)+BigInt(RESERVE_BYTES)+BigInt(OVERHEAD_BYTES))throw new CapacityError('capacity_refused');
}
export function requireDiskHeadroom(path,remaining){
 let available;try{const s=statfsSync(path,{bigint:true});if(s.bsize<=0n||s.bavail<0n)throw Error();available=s.bsize*s.bavail;}
 catch{throw new CapacityError('capacity_unavailable');}
 requireAvailable(available,remaining);
}
export function createProgressGuard(path){let next=0;return n=>{
 if(!Number.isSafeInteger(n)||n<0||n>MAX_DUMP_BYTES)throw new CapacityError('capacity_unavailable');
 if(n>=next){requireDiskHeadroom(path,MAX_DUMP_BYTES-n);next=n+4*1024*1024;}
};}
