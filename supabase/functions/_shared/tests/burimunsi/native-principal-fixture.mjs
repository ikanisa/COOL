/** TEST ONLY: runs production native auth SELECT/INSERT over a reduced SQLite
 * schema. PostgreSQL role/fence/RLS/row locks are not implemented by this fixture.
 * No real accounts, credentials, tokens, managed sessions or external services.
 */
import {DatabaseSync} from 'node:sqlite';
import {PostgresNativeAuthStore} from '../../domain/burimunsi/postgres-auth-store.js';
export const I=Object.freeze({account:'10000000-0000-4000-8000-000000000001',session:'10000000-0000-4000-8000-000000000002',
  grant:'10000000-0000-4000-8000-000000000003',installation:'10000000-0000-4000-8000-000000000004',
  issued:'10000000-0000-4000-8000-000000000005',canonical:'10000000-0000-4000-8000-000000000006',
  request:'10000000-0000-4000-8000-000000000007',principal:'collect-user-1',group:'group-1',now:1794045600000});
export function principalFixture(){
 const sqlite=new DatabaseSync(':memory:');sqlite.exec("ATTACH ':memory:' AS app; ATTACH ':memory:' AS private;");
 sqlite.exec(`CREATE TABLE app.users(id TEXT PRIMARY KEY,access_status TEXT);
 CREATE TABLE private.burimunsi_accounts(id TEXT PRIMARY KEY,collection_id TEXT,principal_user_id TEXT,phone TEXT,name TEXT,
  role TEXT,capabilities TEXT,active BOOLEAN,removed BOOLEAN,pin_hash TEXT,credential_version INTEGER,version INTEGER);
 CREATE TABLE private.burimunsi_device_grants(id TEXT PRIMARY KEY,collection_id TEXT,installation_id TEXT,token_hash TEXT,profile TEXT,active BOOLEAN,version INTEGER);
 CREATE TABLE private.burimunsi_device_accounts(grant_id TEXT,account_id TEXT,collection_id TEXT);
 CREATE TABLE private.burimunsi_scopes(collection_id TEXT PRIMARY KEY,enabled BOOLEAN);
 CREATE TABLE private.burimunsi_sessions(id TEXT PRIMARY KEY,collection_id TEXT,account_id TEXT,grant_id TEXT,installation_id TEXT,
  credential_version INTEGER,grant_version INTEGER,token_hash TEXT,created_at INTEGER,expires_at INTEGER,revoked BOOLEAN DEFAULT false,principal_user_id TEXT);
 CREATE TABLE private.burimunsi_audit(id TEXT PRIMARY KEY,collection_id TEXT,actor_id TEXT,action TEXT,entity_id TEXT,request_id TEXT,at_ms INTEGER);`);
 sqlite.prepare('INSERT INTO app.users VALUES(?,?)').run(I.principal,'active');
 sqlite.prepare('INSERT INTO private.burimunsi_accounts VALUES(?,?,?,?,?,?,?,?,?,?,?,?)').run(I.account,I.group,I.principal,
  '+250780000001','EXAMPLE STAFF','staff',JSON.stringify(['records.read','payments.allocate']),1,0,JSON.stringify({testOnly:true}),1,1);
 sqlite.prepare('INSERT INTO private.burimunsi_device_grants VALUES(?,?,?,?,?,?,?)').run(I.grant,I.group,I.installation,'d'.repeat(64),'staff',1,1);
 sqlite.prepare('INSERT INTO private.burimunsi_device_accounts VALUES(?,?,?)').run(I.grant,I.account,I.group);
 sqlite.prepare('INSERT INTO private.burimunsi_scopes VALUES(?,?)').run(I.group,1);
 sqlite.prepare('INSERT INTO private.burimunsi_sessions VALUES(?,?,?,?,?,?,?,?,?,?,?,?)').run(I.session,I.group,I.account,I.grant,I.installation,1,1,'b'.repeat(64),I.now-1000,I.now+60000,0,I.principal);
 const state={queries:[],workRevoked:false,afterQuery:null,transactions:0};
 const sql={unsafe:async(text,values=[])=>{
   state.queries.push({text,values:[...values]});
   if(text.startsWith('SELECT pg_advisory')||text.startsWith('SELECT set_config')||text.startsWith('SET TRANSACTION'))return [];
   const args=[];const query=text.replace(/\$(\d+)(?:::uuid|::text|::jsonb)?/g,(_,n)=>{const value=values[Number(n)-1];args.push(value&&typeof value==='object'?JSON.stringify(value):value);return '?';});
   const result=sqlite.prepare(query).all(...args).map(row=>{
     const r={...row};for(const k of ['active','removed','revoked'])if(k in r)r[k]=Boolean(r[k]);
     for(const k of ['capabilities','pin_hash'])if(k in r)r[k]=JSON.parse(r[k]);return r;
   });
   await state.afterQuery?.(text,result);return result;
 }};
 const db={applicationWork:{assert:async()=>{if(state.workRevoked)throw Error('work_revoked');}},
   context:async()=>{state.readOnly=false;},readContext:async()=>{state.readOnly=true;},transaction:async fn=>{
     state.transactions++;sqlite.exec('BEGIN');try{const out=await fn(sql);sqlite.exec('COMMIT');return out;}catch(e){sqlite.exec('ROLLBACK');throw e;}
   }};
 const store=new PostgresNativeAuthStore({db,groupId:I.group,clock:()=>I.now,createOperatorPrincipal:async()=>{throw Error('not used');}});
 const issuance={id:I.issued,groupId:I.group,accountId:I.account,installationId:I.installation,principalUserId:I.principal,
   deviceGrantId:I.grant,deviceTokenHash:'d'.repeat(64),deviceGrantVersion:1,credentialVersion:1,tokenHash:'c'.repeat(64),createdAt:I.now,expiresAt:I.now+60000};
 return {sqlite,sql,state,db,store,issuance,session:()=>store.loadSession('b'.repeat(64),I.installation,I.now),
   execute:(q,...args)=>sqlite.prepare(q).run(...args),close:()=>sqlite.close()};
}
