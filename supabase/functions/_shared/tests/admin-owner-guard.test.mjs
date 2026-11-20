import {test} from './helpers/fenced-node-test.js';
import assert from 'node:assert/strict';
import {isAbsolute,join} from 'node:path';
import {pathToFileURL} from 'node:url';

const root=process.env.COLLECT_AUTH_SOURCE_ROOT;
assert.ok(typeof root==='string'&&isAbsolute(root));
const {accountGuard}=await import(pathToFileURL(join(root,'domain/admin_accounts_legacy.js')).href);
const account={id:'synthetic-admin',token_hash:'a'.repeat(64),origin:'https://admin.example.invalid',public_id:'synthetic-session',
 auth_version:2,role:'owner',principal_id:'synthetic-principal',auth_session_id:'synthetic-auth-session',
 issued_assurance_level:1,issued_mfa_at:null,issued_mfa_factor_id:null};
const env=flags=>({...flags,DB:{prepare(sql){return{sql,values:[],bind(...values){this.values=values;return this;}};}}});

test('default and non-true owner authority flags retain the exact legacy predicate',()=>{
 for(const flag of [undefined,'false','TRUE','1']){
  const value=accountGuard(env({COLLECT_ADMIN_DYNAMIC_OWNER_AUTH_ENABLED:flag}),account,'admin_users.manage',{owner:true});
  assert.match(value.statement.sql,/\(a\.role='owner' AND a\.email=\?\)/);
  assert.doesNotMatch(value.statement.sql,/private\.collect_owner_is/);
  assert.equal(value.statement.values.at(-3),1);assert.equal(value.statement.values.at(-2),'info@ikanisa.com');
 }
});
test('dynamic owner guard checks the protected singleton inside the same mutation gate',()=>{
 const value=accountGuard(env({COLLECT_ADMIN_DYNAMIC_OWNER_AUTH_ENABLED:'true'}),account,'admin_users.manage',{owner:true});
 assert.match(value.statement.sql,/\(a\.role='owner' AND private\.collect_owner_is\(a\.id,l\.user_id,a\.email\)\)/);
 assert.doesNotMatch(value.statement.sql,/a\.email=\?/);
 assert.equal(value.statement.values.at(-2),1);assert.equal(value.statement.values.at(-1),0);
 assert(!value.statement.values.includes('info@ikanisa.com'));
 assert.match(value.statement.sql,/s\.token_hash=\?/);assert.match(value.statement.sql,/c\.role=a\.role/);
});
test('DTO flag alone never changes mutation authority',()=>{
 const value=accountGuard(env({COLLECT_ADMIN_OWNER_IDENTITY_ENABLED:'true'}),account,'admin_users.manage',{owner:true});
 assert.match(value.statement.sql,/a\.email=\?/);assert.doesNotMatch(value.statement.sql,/collect_owner_is/);
});
test('dynamic authority does not bypass existing sensitive-email requirement',()=>{
 assert.throws(()=>accountGuard(env({COLLECT_ADMIN_DYNAMIC_OWNER_AUTH_ENABLED:'true'}),account,'admin_users.manage',{owner:true,fresh:true}),
  error=>error.code==='recent_email_sign_in_required');
});
