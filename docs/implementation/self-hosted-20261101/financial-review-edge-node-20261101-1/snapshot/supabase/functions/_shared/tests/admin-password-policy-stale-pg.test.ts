import assert from 'node:assert/strict';
import {fencedTest} from './helpers/fenced-unit.js';
import {openAdminPasswordFixture} from './helpers/admin-password-policy-fixture.js';

// Separate mandatory-when-selected cohort. Root provides an exclusive >=360s
// finite PG lease. Never run concurrently with FAST on the same fixture DB.
// Uses genuine elapsed DB time, with no old-proof INSERT or replacement clock.
const database=Deno.env.get('COLLECT_ADMIN_PASSWORD_POLICY_STALE_TEST_DATABASE_URL');
fencedTest({name:'Admin password policy STALE_300S_ONLY: original proof expires after genuine database time',
 sanitizeResources:false,sanitizeOps:false,fn:async()=>{
 const fixture=await openAdminPasswordFixture(database);
 try{
  const a=await fixture.actor(),before=await fixture.status(a),verifiedAt=before.email_verified_at;
  assert(Number.isSafeInteger(verifiedAt)&&verifiedAt>0);await fixture.check(a);
  const deadline=performance.now()+302000;
  for(;;){
   const now=Number((await fixture.sql`SELECT app.unixepoch() AS at`)[0].at);
   if(now>verifiedAt+300)break;
   assert(performance.now()<deadline,'The bounded real-clock cohort did not observe proof expiry within302s');
   await new Promise(resolve=>setTimeout(resolve,Math.min(1000,Math.max(1,deadline-performance.now()))));
  }
  await assert.rejects(()=>fixture.check(a),(error:any)=>error.code==='42501'&&error.message==='recent_email_sign_in_required');
  const after=await fixture.status(a);assert.equal(after.email_verified_at,verifiedAt);assert.equal(after.proof_id,before.proof_id,
   'Status retains the completed stale event; polling never renews or erases it');
  a.rawDb.setClaims({...a.claims,iat:Math.floor(Date.now()/1000),exp:Math.floor(Date.now()/1000)+900});
  await assert.rejects(()=>fixture.check(a),(error:any)=>error.code==='42501'&&error.message==='recent_email_sign_in_required');
 }finally{await fixture.close();}
}});
