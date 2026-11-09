import {requireThat} from './errors.js';
import {requireId,requireRequestId} from './values.js';

/** Snapshot server-created work before any await. A mutable caller object must
 * never change the lease, selected member or policy during a financial command.
 * This is validation, NOT authorization; the SQL job store proves ownership. */
export function automaticWork(input) {
  requireThat(input && typeof input==='object' && !Array.isArray(input), 'automatic_work_required',503);
  const fields=['kind','jobId','owner','leaseVersion'];
  const kind=Object.getOwnPropertyDescriptor(input,'kind');
  requireThat(kind && Object.hasOwn(kind,'value') && ['receipt','rematch'].includes(kind.value),'automatic_work_required',503);
  if(kind.value==='rematch')fields.push('memberId','policyVersion');
  const keys=Reflect.ownKeys(input);
  requireThat(keys.length===fields.length&&fields.every(k=>keys.includes(k)), 'automatic_work_required',503);
  const work={};
  for(const key of fields) {
    const descriptor=Object.getOwnPropertyDescriptor(input,key);
    requireThat(descriptor?.enumerable===true&&Object.hasOwn(descriptor,'value'),'automatic_work_required',503);
    work[key]=descriptor.value;
  }
  requireRequestId(work.jobId);requireId(work.owner);
  requireThat(Number.isSafeInteger(work.leaseVersion)&&work.leaseVersion>0,'automatic_work_required',503);
  if(work.kind==='rematch') {
    requireId(work.memberId);
    requireThat(typeof work.policyVersion==='string'&&work.policyVersion.length>=1&&work.policyVersion.length<=128&&
      !/[\u0000-\u001f\u007f]/.test(work.policyVersion),'automatic_work_required',503);
  }
  return Object.freeze(work);
}
