import {test} from "node:test";
import assert from "node:assert/strict";
import {productionOrigin,scopedRuntime,runtimeCredentials} from "./runtime_credentials.ts";
const now = 1800000000000;
const jwt = (v:unknown) => `header.${Buffer.from(JSON.stringify(v)).toString("base64url")}.signature`;
const environment = {COLLECT_SUPABASE_URL:productionOrigin};
const session = {origin:productionOrigin,anon_key:jwt({role:"anon"}),access_token:jwt({sub:"test-user",role:"authenticated",iss:`${productionOrigin}/auth/v1`,exp:now/1000+3600})};
test("scoped user session can supply only its project's runtime credentials", () => {
  assert.equal(scopedRuntime(session,environment,now).COLLECT_OPERATOR_ACCESS_TOKEN,session.access_token);
});
test("wrong origin, expired, privileged or persistent refresh credentials fail closed", () => {
  for (const change of [{origin:"https://other.supabase.co"},{refresh_token:"not-allowed"},{anon_key:jwt({role:"service_role"})},{access_token:jwt({role:"service_role"})},{access_token:jwt({sub:"test-user",role:"authenticated",iss:`${productionOrigin}/auth/v1`,exp:now/1000+59})}]) {
    assert.throws(() => scopedRuntime({...session,...change},environment,now), /REAUTHENTICATION_REQUIRED/);
  }
  assert.throws(() => scopedRuntime(session,{COLLECT_SUPABASE_URL:"https://other.supabase.co"},now), /REAUTHENTICATION_REQUIRED/);
});
test("missing opt-in leaves current environment untouched", async () => {
  assert.equal(await runtimeCredentials(environment),environment);
});
test("complete explicit runtime does not access Keychain", async () => {
  const env={...environment,COLLECT_SUPABASE_ANON_KEY:"test",COLLECT_OPERATOR_ACCESS_TOKEN:"test",COLLECT_OPERATOR_KEYCHAIN_HELPER:"/not/used"};
  assert.equal(await runtimeCredentials(env),env);
});
