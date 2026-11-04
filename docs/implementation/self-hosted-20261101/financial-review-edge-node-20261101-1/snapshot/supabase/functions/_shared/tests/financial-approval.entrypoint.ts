import {assert} from 'jsr:@std/assert@1.0.14';
import {fencedTest} from './helpers/fenced-unit.js';
import {financialApprovalCollisionCases} from './financial-approval-collision.cases.ts';
import {baselineFinancialDoubleCredit} from './financial-approval-baseline.cases.ts';

// Root binds a sealed extraction of the accepted actual financial fixture.
// Register exactly one selected cohort; no original all-Auth test import.
export function registerFinancialApprovalCohort(openFixture:any,mode:'baseline_red'|'candidate_green11'){
 assert(typeof openFixture==='function');
 assert(mode==='baseline_red'||mode==='candidate_green11');
 const databaseConfigured=Boolean(Deno.env.get('COLLECT_FINANCIAL_TEST_DATABASE_URL')||Deno.env.get('COLLECT_TEST_DATABASE_URL'));
 fencedTest({name:'BE02 actual PostgreSQL '+mode,ignore:!databaseConfigured,sanitizeResources:false,sanitizeOps:false,fn:async(t:any)=>{
  const fixture=await openFixture();
  assert(fixture&&typeof fixture.close==='function');
  try{
   const h={...fixture,step:(name:string,fn:()=>Promise<void>)=>t.step(name,fn)};
   if(mode==='baseline_red')await baselineFinancialDoubleCredit(h);
   else {
    assert(typeof fixture.runExistingFinancialRegressions==='function');
    await fixture.runExistingFinancialRegressions();
    await financialApprovalCollisionCases(h);
   }
  }finally{await fixture.close();}
 }});
}
