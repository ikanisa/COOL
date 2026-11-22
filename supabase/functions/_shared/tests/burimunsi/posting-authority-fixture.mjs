/** TEST ONLY: production authority orchestration, real native SQL when using
 * principalFixture, and transient mutation-guard SQL. Managed-session helpers,
 * canonical permission/assurance trigger and all PostgreSQL locking are simulated.
 */
import {principalFixture,I} from './native-principal-fixture.mjs';
import {PostgresPostingAuthority} from '../../domain/burimunsi/postgres-posting-authority.js';
import {MANAGED_SESSION_SQL,MANAGED_CONTEXT_SQL} from '../../domain/burimunsi/postgres-managed-sessions.js';
export {I};
export function installCanonicalHarness(f,{principal=I.principal,canonicalSession=I.canonical,now=I.now}={}){
 const s=f.sqlite;
 s.exec(`CREATE TABLE app.auth_sessions(id TEXT PRIMARY KEY,user_id TEXT,surface TEXT,expires_at INTEGER,revoked_at INTEGER,mfa_at INTEGER);
 CREATE TABLE app.mutation_guards(id TEXT PRIMARY KEY,user_id TEXT,session_id TEXT,now_seconds INTEGER,collection_id TEXT,
  permission TEXT,minimum_assurance INTEGER,expected_mfa_at INTEGER,fresh_seconds INTEGER,recipient_user_id TEXT,recipient_collection_id TEXT);`);
 s.prepare('INSERT INTO app.auth_sessions VALUES(?,?,?,?,?,?)').run(canonicalSession,principal,'admin',Math.floor(now/1000)+3600,null,null);
 const h={allowed:true,managed:true,operatorApproved:true,parentContextAllowed:true,sharedRole:'staff',contextBindings:0,
  sessionId:canonicalSession,now:Math.floor(now/1000),millis:0,reads:0,guards:[],afterCanonical:null,afterGuard:null};
 s.function('test_only_guard_allowed',()=>h.allowed?1:0);
 s.exec(`CREATE TRIGGER app.synthetic_financial_guard BEFORE INSERT ON mutation_guards
   WHEN test_only_guard_allowed()<>1 BEGIN SELECT RAISE(ABORT,'test-only permission denial'); END;`);
 const unsafe=f.sql.unsafe;
 f.sql.unsafe=async(text,values=[])=>{
  if(text===MANAGED_CONTEXT_SQL){
   h.contextBindings++;if(!h.parentContextAllowed)throw Error('Fixture BFF tuple changed');
   return [{result:{contract_version:1,public_session_id:I.request}}];
  }
  if(text.startsWith('SELECT private.burimunsi_operator_is_current('))return [{allowed:h.operatorApproved}];
  if(text!==MANAGED_SESSION_SQL&&!text.startsWith('WITH canonical AS MATERIALIZED'))return unsafe(text,values);
  h.reads++;if(!h.managed)throw Error('SENSITIVE mocked JWT error');
  const row=s.prepare('SELECT user_id AS principal_user_id,id AS principal_session_id,user_id AS session_user_id,surface,expires_at,revoked_at,mfa_at FROM app.auth_sessions WHERE id=?').get(h.sessionId);
  const result=row?[{...row,now_ms:String(h.now*1000+h.millis),
   ...(text===MANAGED_SESSION_SQL?{transaction_read_only:f.state.readOnly?'on':'off',shared_role:h.sharedRole,
    admin_id:I.account,cookie_hash:'a'.repeat(64),origin:'https://fixture.example.invalid',public_session_id:I.request}:{})}]:[];
  await h.afterCanonical?.(h.reads,result);return result;
 };
 f.db.prepare??=text=>({bind:(...values)=>({sql:text,values})});
 const statement=f.db.statement??(async(_sql,st)=>{const result=s.prepare(st.sql).run(...st.values);return {success:true,meta:{changes:Number(result.changes)}};});
 f.db.statement=async(sql,st)=>{
  const out=await statement(sql,st);
  if(st.sql.includes('app.mutation_guards')){h.guards.push(st);await h.afterGuard?.(st,out);}
  return out;
 };
 return h;
}
export function authorityFixture(){
 const f=principalFixture(),h=installCanonicalHarness(f);
 const runtime=new PostgresPostingAuthority({authority:f.store});
 const command={groupId:I.group,receiptId:'transaction-1',memberId:'member-1',requestId:I.request,mode:'exception',
   actorId:I.account,sessionId:I.session,actor:{principalUserId:I.principal}};
 return {...f,h,runtime,command,run:(phase='before_allocation')=>f.store.write(sql=>runtime.assertInTransaction(sql,{command,phase}))};
}
