import {validateSupervisorResult} from "./handler.ts";

// Actual outputs from the explicitly synthetic SQL fixture. This checks the
// SQL/wire boundary; service stubs never establish a hosted Auth session.
Deno.test("actual SQL proof health and original-request receipt satisfy wire contract",async()=>{
 const report=new URL("./fixtures/",import.meta.url);
 const proof=JSON.parse(await Deno.readTextFile(new URL("observed-proof.json",report)));
 const health=JSON.parse(await Deno.readTextFile(new URL("observed-health.json",report)));
 const lookup=JSON.parse(await Deno.readTextFile(new URL("observed-reconciled.json",report)));
 const principal=health.principal_id;const request=health.request_id;
 if(typeof principal!=="string"||typeof request!=="string")throw Error("Missing actual SQL identifiers");
 if(!validateSupervisorResult(proof,proof.principal_id,proof.request_id,"prove_key",{}) ||
    !validateSupervisorResult(health,principal,request,"shadow_health",{}) ||
    !validateSupervisorResult(lookup,principal,"99800000-0000-4000-8000-000000000004","reconcile",{target_request_id:request})){
  throw Error("Actual synthetic SQL/wire mismatch");
 }
});
