/** Actual command/statements over reduced SQLite. Shared PostgreSQL role,
 * fresh-email, fence and managed-session proofs are explicit fixture boundaries;
 * this is not native PostgreSQL, GoTrue or production qualification. */
import test from 'node:test';import assert from 'node:assert/strict';
import {principalFixture,I} from './native-principal-fixture.mjs';
import {installCanonicalHarness} from './posting-authority-fixture.mjs';
import {PostgresCollectMemberCommands} from '../../domain/burimunsi/postgres-collect-members.js';

const memberId='20000000-0000-4000-8000-000000000001';
function fixture(){
 const f=principalFixture(),h=installCanonicalHarness(f);h.sharedRole='admin';h.permissions=new Set(['users.manage','collections.manage']);
 const s=f.sqlite;
 for(const [column,definition]of Object.entries({public_id:'TEXT',full_name:"TEXT DEFAULT ''",phone:'TEXT',email:'TEXT',member_type:"TEXT DEFAULT 'direct'",
  momo_provider:"TEXT DEFAULT ''",momo_number:"TEXT DEFAULT ''",momo_pay_code:"TEXT DEFAULT ''",created_at:'TEXT',updated_at:'TEXT'}))
  s.exec('ALTER TABLE app.users ADD COLUMN '+column+' '+definition);
 f.execute("UPDATE app.users SET public_id='999999',member_type='operator'");
 s.exec(`CREATE UNIQUE INDEX app.users_public_id ON users(public_id);
  CREATE TABLE app.collections(id TEXT PRIMARY KEY,status TEXT NOT NULL);
  CREATE TABLE app.memberships(id TEXT PRIMARY KEY,collection_id TEXT,user_id TEXT,role TEXT,active INTEGER,joined_at TEXT,revision INTEGER DEFAULT 1,UNIQUE(collection_id,user_id));
  CREATE TABLE app.ledger_entries(id TEXT PRIMARY KEY,collection_id TEXT,member_id TEXT,amount_minor INTEGER);
  CREATE TABLE app.audit_log(id INTEGER PRIMARY KEY,actor_user_id TEXT,actor_session_id TEXT,action TEXT,entity_type TEXT,entity_id TEXT,request_id TEXT,details_json TEXT,created_at TEXT);`);
 f.execute('INSERT INTO app.collections VALUES(?,?)',I.group,'active');
 f.execute('UPDATE private.burimunsi_accounts SET capabilities=?',JSON.stringify(['records.read','members.enroll']));
 const oldUnsafe=f.sql.unsafe;
 f.sql.unsafe=async(text,values=[])=>{
  if(!/app\.(?:collections|memberships)\b/.test(text))return oldUnsafe(text,values);
  f.state.queries.push({text,values:[...values]});
  const args=[],query=text.replace(/ FOR UPDATE OF m,u| FOR SHARE/g,'').replace(/\$(\d+)/g,(_,n)=>{args.push(values[Number(n)-1]);return '?';});
  const rows=s.prepare(query).all(...args).map(r=>({...r}));await f.state.afterQuery?.(text,rows);return rows;
 };
 const statements=[],oldStatement=f.db.statement;
 f.db.statement=async(sql,statement)=>{
  statements.push(statement);
  if(statement.sql.startsWith('INSERT INTO app.mutation_guards')&&
   (!['admin','owner'].includes(h.sharedRole)||!h.permissions.has(statement.values[5])))throw Error('synthetic shared permission denied');
  const result=await oldStatement(sql,statement);await f.afterStatement?.(statement,result);return result;
 };
 const commands=new PostgresCollectMemberCommands({authority:f.store});
 const actor={id:I.account,sessionId:I.session,principalUserId:I.principal};
 const enrollment={groupId:I.group,name:'EXAMPLE DIRECT MEMBER',phone:'+250789444111',requestId:I.request,actorId:I.account,sessionId:I.session,actor};
 const membership={groupId:I.group,memberId,active:false,expectedVersion:3,requestId:I.request,actorId:I.account,sessionId:I.session,actor};
 const count=table=>s.prepare('SELECT count(*) AS n FROM app.'+table).get().n;
 const seedMember=({role='member',active=1,type='direct',status='active'}={})=>{
  f.execute('INSERT INTO app.users(id,public_id,full_name,momo_number,member_type,access_status) VALUES(?,?,?,?,?,?)',memberId,'000004','EXAMPLE EXISTING MEMBER','0789444111',type,status);
  f.execute('INSERT INTO app.memberships(id,collection_id,user_id,role,active,revision) VALUES(?,?,?,?,?,?)','membership-1',I.group,memberId,role,active,3);
  f.execute("UPDATE private.burimunsi_accounts SET role='admin'");
 };
 return Object.assign(f,{h,commands,enrollment,membership,statements,count,seedMember,
  create:()=>f.store.write(sql=>commands.createDirectMember(sql,enrollment)),
  change:()=>f.store.write(sql=>commands.setMembershipActive(sql,membership))});
}
test('closed member adapter assembles without database IO',t=>{
 const f=fixture();t.after(f.close);assert.equal(f.state.queries.length,0);assert.equal(f.statements.length,0);
 assert.throws(()=>new PostgresCollectMemberCommands({authority:{}}));
});
test('enrollment reuses canonical Direct person/public ID, membership and shared audit with no credit',async t=>{
 const f=fixture();t.after(f.close);const result=await f.create();
 assert.equal(result.phone,f.enrollment.phone);assert.equal(result.groupId,I.group);assert.equal(result.name,f.enrollment.name);
 assert.equal(result.balanceRwf,0);assert.equal(result.active,true);assert.equal(result.version,1);
 const user=f.sqlite.prepare('SELECT * FROM app.users WHERE id=?').get(result.id);
 assert.equal(user.member_type,'direct');assert.equal(user.momo_number,'0789444111');assert.equal(user.phone,null);assert.equal(user.email,null);assert.equal(user.public_id,'000000');
 assert.equal(f.count('memberships'),1);assert.equal(f.count('ledger_entries'),0);
 const audit=f.sqlite.prepare('SELECT * FROM app.audit_log').get();
 assert.equal(audit.actor_user_id,I.principal);assert.equal(audit.actor_session_id,I.canonical);assert.equal(audit.request_id,I.request);
 assert.equal(JSON.parse(audit.details_json).native_actor_id,I.account);
 assert.deepEqual(f.h.guards.filter(v=>v.sql.startsWith('INSERT')).map(v=>v.values.slice(4)),[
  [null,'users.manage',2,null,300],[null,'collections.manage',2,null,300],
  [null,'users.manage',2,null,300],[null,'collections.manage',2,null,300]]);
 assert(!f.statements.some(v=>/INSERT INTO (?:auth\.|private\.burimunsi_|payments|ledger_entries)/.test(v.sql)));
});
for(const role of ['staff'])test('native enrollment capability cannot override shared read-only '+role+' role',async t=>{
 const f=fixture();t.after(f.close);f.h.sharedRole=role;
 await assert.rejects(f.create(),/access_denied/);assert.equal(f.count('users'),1);assert.equal(f.count('memberships'),0);
});
for(const permission of ['users.manage','collections.manage'])test('missing current shared '+permission+' prevents enrollment',async t=>{
 const f=fixture();t.after(f.close);f.h.permissions.delete(permission);
 await assert.rejects(f.create(),/access_denied/);assert.equal(f.count('users'),1);assert.equal(f.count('audit_log'),0);
});
test('existing complete phone route, including removed membership, cannot create another beneficiary',async t=>{
 const f=fixture();t.after(f.close);f.seedMember({active:0});
 await assert.rejects(f.create(),/duplicate_phone/);assert.equal(f.count('users'),2);assert.equal(f.count('memberships'),1);
});
test('second new request cannot create the same phone after successful enrollment',async t=>{
 const f=fixture();t.after(f.close);await f.create();f.enrollment.requestId=crypto.randomUUID();
 await assert.rejects(f.create(),/duplicate_phone/);assert.equal(f.count('users'),2);assert.equal(f.count('memberships'),1);assert.equal(f.count('audit_log'),1);
});
test('captured request cannot be retargeted by caller mutation during an awaited canonical read',async t=>{
 const f=fixture();t.after(f.close);f.h.afterCanonical=()=>{f.enrollment.phone='+250780000099';f.enrollment.actor.principalUserId='forged';};
 assert.equal((await f.create()).phone,'+250789444111');
});
test('native capability revocation during guards rolls back all new business rows',async t=>{
 const f=fixture();t.after(f.close);f.h.afterGuard=()=>f.execute('UPDATE private.burimunsi_accounts SET capabilities=?','["records.read"]');
 await assert.rejects(f.create());assert.equal(f.count('users'),1);assert.equal(f.count('memberships'),0);assert.equal(f.count('audit_log'),0);
});
test('shared authority denial after writes rolls back rather than returning an accepted member',async t=>{
 const f=fixture();t.after(f.close);f.afterStatement=statement=>{if(statement.sql.startsWith('INSERT INTO audit_log'))f.h.permissions.delete('users.manage');};
 await assert.rejects(f.create(),/access_denied/);assert.equal(f.count('users'),1);assert.equal(f.count('memberships'),0);assert.equal(f.count('audit_log'),0);
});
test('a replaced admitted work cannot publish member creation',async t=>{
 const f=fixture();t.after(f.close);f.afterStatement=statement=>{if(statement.sql.startsWith('INSERT INTO users'))f.db.applicationWork={assert:async()=>{}};};
 await assert.rejects(f.create(),/request_not_admitted/);assert.equal(f.count('users'),1);assert.equal(f.count('memberships'),0);
});
for(const code of ['application_fenced','application_fence_unavailable'])test('real '+code+' during shared guard keeps its infrastructure failure meaning',async t=>{
 const f=fixture();t.after(f.close);const original=f.db.statement,failure=Object.assign(new Error(code),{code});
 f.db.statement=(sql,statement)=>{if(statement.sql.startsWith('INSERT INTO app.mutation_guards'))throw failure;return original(sql,statement);};
 await assert.rejects(f.create(),error=>error===failure);assert.equal(f.count('users'),1);assert.equal(f.count('memberships'),0);
});
test('different collection and malformed canonical phone fail before SQL',async t=>{
 const f=fixture();t.after(f.close);f.enrollment.groupId='another-group';await assert.rejects(f.create(),/access_denied/);
 f.enrollment.groupId=I.group;f.enrollment.phone='0789444111';await assert.rejects(f.create(),/invalid_phone/);
 assert.equal(f.state.queries.filter(v=>!/pg_advisory|set_config/.test(v.text)).length,0);
});
test('membership update preserves selected group role and uses expected revision',async t=>{
 const f=fixture();t.after(f.close);f.seedMember({role:'admin'});const result=await f.change();
 assert.deepEqual(result,{applied:true,groupId:I.group,memberId,active:false,version:4});
 const row=f.sqlite.prepare('SELECT role,active,revision FROM app.memberships').get();assert.deepEqual({...row},{role:'admin',active:0,revision:4});
 assert.equal(f.count('users'),2);assert.equal(f.count('ledger_entries'),0);assert.equal(f.count('audit_log'),1);
});
test('reactivation uses existing member and advances revision without creating a new person',async t=>{
 const f=fixture();t.after(f.close);f.seedMember({active:0});f.membership.active=true;
 assert.equal((await f.change()).version,4);assert.equal(f.count('users'),2);assert.equal(f.count('memberships'),1);
});
for(const [label,seed]of [['owner',{role:'owner'}],['operator',{type:'operator'}],['suspended',{status:'suspended'}]])test('protected '+label+' target cannot change through native membership commands',async t=>{
 const f=fixture();t.after(f.close);f.seedMember(seed);await assert.rejects(f.change(),/membership_changed/);assert.equal(f.count('audit_log'),0);
 assert.equal(f.sqlite.prepare('SELECT revision FROM app.memberships').get().revision,3);
});
test('stale member revision cannot change membership',async t=>{
 const f=fixture();t.after(f.close);f.seedMember();f.membership.expectedVersion=2;await assert.rejects(f.change(),/membership_changed/);assert.equal(f.count('audit_log'),0);
});
test('native Staff cannot change membership even with current shared Admin permissions',async t=>{
 const f=fixture();t.after(f.close);f.seedMember();f.execute("UPDATE private.burimunsi_accounts SET role='staff'");
 await assert.rejects(f.change(),/access_denied/);assert.equal(f.count('audit_log'),0);
});
test('readback inconsistency cannot become a successful membership result',async t=>{
 const f=fixture();t.after(f.close);f.seedMember();f.afterStatement=statement=>{
  if(statement.sql.startsWith('UPDATE memberships'))f.execute("UPDATE app.memberships SET role='member',revision=revision+1");};
 await assert.rejects(f.change(),/member_contract_violation/);assert.equal(f.sqlite.prepare('SELECT revision FROM app.memberships').get().revision,3);
});
