import test from 'node:test';
import assert from 'node:assert/strict';
import {preliminaryCurrentOwner} from '../domain/admin_owner_precheck.js';

const original={id:'admin-one',principal_id:'principal-one',email:'info@ikanisa.com',role:'owner'};
const alternate={...original,email:'owner@example.invalid'};
function fixture(result=true){
 const calls=[];
 return {calls,env:{COLLECT_ADMIN_DYNAMIC_OWNER_AUTH_ENABLED:'true',DB:{prepare(sql){
  calls.push({sql});return {bind(...args){calls.at(-1).args=args;return {async first(){if(result instanceof Error)throw result;return {result};}};}};
 }}}};
}
test('legacy preliminary check is unchanged and does not query the dynamic binding',async()=>{
 const f=fixture();delete f.env.COLLECT_ADMIN_DYNAMIC_OWNER_AUTH_ENABLED;
 assert.equal(await preliminaryCurrentOwner(f.env,original),true);
 assert.equal(await preliminaryCurrentOwner(f.env,alternate),false);
 assert.equal(await preliminaryCurrentOwner(f.env,{...original,role:'admin'}),false);
 assert.deepEqual(f.calls,[]);
});
test('dynamic preliminary check uses exact database-resolved identities and fails closed',async()=>{
 for(const [result,allowed] of [[true,true],[false,false],[null,false],['true',false]]){
  const f=fixture(result);assert.equal(await preliminaryCurrentOwner(f.env,alternate),allowed);
  assert.deepEqual(f.calls,[{sql:'SELECT private.collect_owner_is(?,?,?) AS result',args:[alternate.id,alternate.principal_id,alternate.email]}]);
 }
 const f=fixture();assert.equal(await preliminaryCurrentOwner(f.env,{...alternate,principal_id:null}),false);assert.deepEqual(f.calls,[]);
});
test('fence failures remain service failures and other database errors are safely unavailable',async()=>{
 for(const code of ['application_fenced','application_fence_unavailable']){
  const original=Object.assign(new Error('synthetic fence'),{code});
  const f=fixture(original);await assert.rejects(preliminaryCurrentOwner(f.env,alternate),e=>e===original);
 }
 const f=fixture(new Error('synthetic private database detail'));
 await assert.rejects(preliminaryCurrentOwner(f.env,alternate),e=>e.status===503&&e.code==='owner_identity_unavailable'&&!e.message.includes('private'));
});
