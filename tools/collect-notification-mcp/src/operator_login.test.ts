import {test} from "node:test";
import assert from "node:assert/strict";
import {authRequest,operatorEmail,requestOperatorEmailOtp,verifyOperatorEmailOtp} from "./operator_login.ts";
const userId="99740000-0000-4000-8000-000000000001";
const syntheticSession=()=>({user:{id:userId,email:operatorEmail},access_token:`e30.${Buffer.from(JSON.stringify({sub:userId})).toString("base64url")}.synthetic`});
test("operator OTP flow is pinned to the configured Auth origin and never follows redirects",async()=>{
  let request:RequestInit|undefined;let endpoint="";
  const fake:typeof fetch=async(input,init)=>{endpoint=String(input);request=init;return new Response("{}");};
  await requestOperatorEmailOtp("public-test",fake);
  assert.equal(endpoint,"https://lhbowpbcpwoiparwnwgt.supabase.co/auth/v1/otp");
  assert.equal(request?.redirect,"error");
  assert.equal(JSON.parse(String(request?.body)).create_user,false);
  assert.deepEqual(JSON.parse(String(request?.body)),{email:"info@ikanisa.com",create_user:false});
  assert.equal(request?.cache,"no-store");
  assert.ok(request?.signal instanceof AbortSignal);
});
test("operator verification uses only the fixed email OTP type without signup or phone",async()=>{
  let request:RequestInit|undefined;let endpoint="";
  const fake:typeof fetch=async(input,init)=>{endpoint=String(input);request=init;return new Response(JSON.stringify(syntheticSession()));};
  const receipt=await verifyOperatorEmailOtp("123456","synthetic-public",fake);
  assert.equal((receipt.user as {id:string}).id,userId);
  assert.equal(operatorEmail,"info@ikanisa.com");
  assert.equal(endpoint,"https://lhbowpbcpwoiparwnwgt.supabase.co/auth/v1/verify");
  assert.deepEqual(JSON.parse(String(request?.body)),{email:operatorEmail,token:"123456",type:"email"});
  assert.equal(request?.redirect,"error");
});
test("successful Auth JSON must bind the fixed email, UUID user and token subject",async()=>{
  const good=syntheticSession();
  for(const value of [
    {},null,[],{...good,user:null},
    {...good,user:{...good.user,email:"PRIVATE_CANARY@example.com"}},
    {...good,user:{...good.user,id:"PRIVATE_CANARY"}},
    {...good,user:{...good.user,id:"99740000-0000-4000-8000-000000000002"}},
    {...good,access_token:"PRIVATE_TOKEN_CANARY"},
  ]){
    let calls=0;
    const fake:typeof fetch=async()=>{calls++;return new Response(JSON.stringify(value));};
    await assert.rejects(verifyOperatorEmailOtp("123456","synthetic-public",fake),/^Error: OPERATOR_EMAIL_IDENTITY_UNCONFIRMED$/);
    assert.equal(calls,1);
  }
});
test("invalid email OTP tokens never invoke Auth and are never echoed",async()=>{
  let calls=0;const fake:typeof fetch=async()=>{calls++;return new Response("{}");};
  for(const token of ["","12345","1234567","PRIVATE_CANARY","123 45"]){
    await assert.rejects(verifyOperatorEmailOtp(token,"synthetic-public",fake),/^Error: INVALID_OTP_FORMAT$/);
  }
  assert.equal(calls,0);
});
test("auth errors never expose provider body or token and do not retry",async()=>{
  let calls=0;
  const fake:typeof fetch=async()=>{calls++;return new Response("private-token",{status:403});};
  await assert.rejects(authRequest("/verify",{},"public-test",fake),/^Error: AUTH_HTTP_403$/);
  assert.equal(calls,1);
  await assert.rejects(authRequest("/admin/users",{},"public-test",fake),/INVALID_AUTH_ACTION/);
  assert.equal(calls,1);
});
