import {test} from "node:test";
import assert from "node:assert/strict";
import {authRequest} from "./operator_login.ts";
test("operator OTP flow is pinned to the configured Auth origin and never follows redirects",async()=>{
  let request:RequestInit|undefined;let endpoint="";
  const fake:typeof fetch=async(input,init)=>{endpoint=String(input);request=init;return new Response("{}");};
  await authRequest("/otp",{phone:"+250700000000",create_user:false,channel:"whatsapp"},"public-test",fake);
  assert.equal(endpoint,"https://lhbowpbcpwoiparwnwgt.supabase.co/auth/v1/otp");
  assert.equal(request?.redirect,"error");
  assert.equal(JSON.parse(String(request?.body)).create_user,false);
});
test("auth errors never expose provider body or token and do not retry",async()=>{
  let calls=0;
  const fake:typeof fetch=async()=>{calls++;return new Response("private-token",{status:403});};
  await assert.rejects(authRequest("/verify",{},"public-test",fake),/^Error: AUTH_HTTP_403$/);
  assert.equal(calls,1);
  await assert.rejects(authRequest("/admin/users",{},"public-test",fake),/INVALID_AUTH_ACTION/);
  assert.equal(calls,1);
});
