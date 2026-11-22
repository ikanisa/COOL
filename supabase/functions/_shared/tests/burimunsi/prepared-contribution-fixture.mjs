/** TEST ONLY: actual service, preparation, allocation, custody, canonical store
 * and shared posting run over synthetic SQLite. Locks are stripped. Principal,
 * identity, job-admission and storage bindings are synthetic; not deployment.
 */
import {preparationFixture,connectAllocationFlow,ids} from './posting-preparation-service-fixture.mjs';
import {ContributionService} from '../../domain/burimunsi/contribution-service.js';
import {composeNativeContributions} from '../../domain/burimunsi/compose.js';
export {ids};
export const count=(f,table)=>f.sqlite.prepare(`SELECT count(*) AS n FROM ${table}`).get().n;
export async function preparedFlow(mode='automatic') {
  const f=connectAllocationFlow(await preparationFixture(mode));
  // Use the actual admitted transaction runner for all stages. The live native
  // session projection is intentionally synthetic in this SQL boundary fixture.
  f.authority.session=async()=>f.actor;
  f.store.authority=f.authority;
  const transaction=f.db.transaction;let tail=Promise.resolve();
  f.db.transaction=async fn=>{
    let release;const previous=tail;tail=new Promise(r=>{release=r;});await previous;
    try{return await transaction(fn);}finally{release();}
  };
  const post=f.store.commands.postContribution;
  f.store.commands.postContribution=async(...args)=>{await f.state.beforeFinancial?.(...args);return post(...args);};
  const prepare=f.preparation.prepare.bind(f.preparation);
  f.state.plans=[];
  f.preparation.prepare=async c=>{f.state.plans.push(structuredClone(c));await f.state.beforePreparation?.(c);
    const value=await prepare(c);await f.state.afterPreparation?.(c,value);return value;};
  f.service=composeNativeContributions({config:{enabled:true,groupId:ids.group,postingPreparationEnabled:true},
    ports:{canonical:f.store,preparation:f.preparation}});
  f.withoutPreparation=new ContributionService({store:f.store,groupId:ids.group});
  f.outcomes=[];
  f.store.jobs.retainAutomaticOutcome=async(_sql,c)=>{f.outcomes.push(structuredClone(c));};
  return f;
}
