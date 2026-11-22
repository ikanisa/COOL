import test from 'node:test';import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';import {readFileSync} from 'node:fs';
import {setup,ids,refactored} from './shared-posting-fixture.mjs';
const ddl=readFileSync(new URL('./sqlite/posting-fixture.sql',import.meta.url),'utf8');
function database(){
 const db=new DatabaseSync(':memory:');db.exec(ddl);
 db.prepare('INSERT INTO collections VALUES(?,?)').run(ids.group,'EXAMPLE GROUP');
 db.prepare('INSERT INTO payment_evidence VALUES(?,?,?,?,?)').run(ids.evidence,'wallet-1:FT100','mtn_momo','+250780000001','RWF');
 db.prepare('INSERT INTO payments VALUES(?,?,?,?,?,?,?,?,?,?)').run(ids.payment,ids.group,null,12500,'RWF','rwanda_momo',7,'recorded',ids.evidence,ids.intent);
 db.prepare('INSERT INTO reconciliations(id,payment_id,status,proposed_by,proposed_member_id) VALUES(?,?,?,?,?)').run(ids.reconciliation,ids.payment,'proposed',ids.otherActor,ids.member);
 db.prepare('INSERT INTO momo_receiving_accounts VALUES(?,?,?)').run('wallet-1','mtn_momo','0780000001');
 db.prepare('INSERT INTO momo_transactions VALUES(?,?,?,?,?,?,?,?,?)').run('transaction-1','wallet-1','incoming_receipt','mtn_momo','RWF','FT100',0,'linked','live');
 db.prepare('INSERT INTO momo_financial_links VALUES(?,?,?)').run('transaction-1',ids.payment,ids.member);
 db.prepare('INSERT INTO payment_intents VALUES(?,?,?)').run(ids.intent,ids.member,'pending');
 return db;
}
async function plan(){const {state,error}=await setup().run(refactored);assert.equal(error,undefined);return state.writes;}
function execute(db,writes,{failAt=-1}={}){
 db.exec('BEGIN');try{for(let i=0;i<writes.length;i++){if(i===failAt)throw Error('injected failure');const w=writes[i];db.prepare(w.sql).run(...w.values);}db.exec('COMMIT');}
 catch(error){db.exec('ROLLBACK');throw error;}
}
function snapshot(db){return Object.fromEntries(db.prepare("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name").all().map(({name})=>[name,db.prepare(`SELECT * FROM ${name} ORDER BY rowid`).all()]));}
function overlap(db,{reference='FT100',receiver='250780000001',network='mtn_momo',inverse=null}={}){
 db.prepare('INSERT INTO payment_evidence VALUES(?,?,?,?,?)').run('prior-evidence',reference,network,receiver,'RWF');
 db.prepare('INSERT INTO payments VALUES(?,?,?,?,?,?,?,?,?,?)').run('prior-payment',ids.group,ids.member,12500,'RWF','rwanda_momo',1,'reconciled','prior-evidence',null);
 db.prepare('INSERT INTO ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind,evidence_id) VALUES(?,?,?,?,?,?,?)').run('prior-entry','prior-payment',ids.group,ids.member,12500,'contribution','prior-evidence');
 if(inverse)db.prepare('INSERT INTO ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind,evidence_id,reverses_entry_id,currency) VALUES(?,?,?,?,?,?,?,?,?)').run('inverse',inverse.payment??'prior-payment',inverse.group??ids.group,inverse.member??ids.member,inverse.amount??-12500,inverse.kind??'reversal',inverse.evidence??'prior-evidence','prior-entry',inverse.currency??'RWF');
}
test('SQLite executes shared posting: ledger, balances, intent, audit and notification in one transaction',async()=>{
 const db=database();try{execute(db,await plan());
  assert.equal(db.prepare('SELECT count(*) AS n FROM ledger_entries').get().n,1);
  const p=db.prepare('SELECT * FROM payments').get();assert.equal(p.status,'reconciled');assert.equal(p.member_id,ids.member);assert.equal(p.revision,8);
  const s=db.prepare('SELECT * FROM contribution_posting_snapshots').get();assert.equal(s.member_balance_after_minor,12500);assert.equal(s.group_balance_after_minor,12500);
  assert.equal(db.prepare('SELECT status FROM payment_intents').get().status,'matched');
  const n=db.prepare('SELECT * FROM notification_events').get();assert.equal(n.status,'pending');assert.equal(JSON.parse(n.data_json).balance_basis,'after_this_contribution');
  assert.equal(db.prepare('SELECT count(*) AS n FROM audit_log').get().n,1);assert.equal(db.prepare('SELECT count(*) AS n FROM admin_bridge_guards').get().n,0);
 }finally{db.close();}
});
for(const [label,sql]of [
 ['disabled preferences',`INSERT INTO notification_preferences VALUES('${ids.member}',0)`],
 ['historical transaction',"UPDATE momo_transactions SET mode='historical'"]])test('SQLite preserves notification suppression: '+label,async()=>{
 const db=database();try{db.exec(sql);execute(db,await plan());assert.equal(db.prepare('SELECT count(*) AS n FROM notification_events').get().n,0);assert.equal(db.prepare('SELECT count(*) AS n FROM audit_log').get().n,1);}finally{db.close();}
});
for(const [label,sql]of [
 ['wrong linked member',"UPDATE momo_financial_links SET beneficiary_member_id='other-member'"],
 ['conflicting transaction',"UPDATE momo_transactions SET has_conflict=1"],
 ['unlinked transaction',"UPDATE momo_transactions SET allocation_state='unallocated'"],
 ['stale revision',"UPDATE payments SET revision=8"],
 ['blank evidence reference',"UPDATE payment_evidence SET external_reference=' '"],
 ['wrong evidence currency',"UPDATE payment_evidence SET currency='USD'"],
 ['wrong rail',"UPDATE payments SET rail='cash'"],
 ['changed reviewer',`UPDATE reconciliations SET proposed_by='${ids.actor}'`],
 ['closed proposal',"UPDATE reconciliations SET status='rejected'"]])test('SQLite guard rollback: '+label,async()=>{
 const db=database();try{db.exec(sql);const before=snapshot(db);assert.throws(()=>execute(db,awaitedPlan));assert.deepEqual(snapshot(db),before);}finally{db.close();}
});
const awaitedPlan=await plan();
for(const reference of ['FT100','wallet-1:FT100'])for(const receiver of ['0780000001','250780000001','+250780000001'])test('SQLite blocks duplicate economic reference '+reference+' '+receiver,()=>{
 const db=database();try{overlap(db,{reference,receiver});const before=snapshot(db);assert.throws(()=>execute(db,awaitedPlan));assert.deepEqual(snapshot(db),before);}finally{db.close();}
});
for(const patch of [{receiver:'0780000002'},{network:'airtel_money'}])test('SQLite reference collision remains wallet/provider scoped '+JSON.stringify(patch),()=>{
 const db=database();try{overlap(db,patch);execute(db,awaitedPlan);assert.equal(db.prepare('SELECT count(*) AS n FROM ledger_entries').get().n,2);}finally{db.close();}
});
for(const inverse of [{}, {kind:'correction'}])test('SQLite preserves exact compensating-entry collision semantics '+JSON.stringify(inverse),()=>{
 const db=database();try{overlap(db,{inverse});execute(db,awaitedPlan);assert.equal(db.prepare('SELECT count(*) AS n FROM ledger_entries').get().n,3);}finally{db.close();}
});
for(const inverse of [{amount:-12499},{evidence:'other-evidence'},{member:'other-member'},{group:'other-group'},{currency:'USD'},{kind:'other'},{payment:'other-payment'}])test('SQLite incomplete compensation still blocks duplicate '+JSON.stringify(inverse),()=>{
 const db=database();try{overlap(db,{inverse});const before=snapshot(db);assert.throws(()=>execute(db,awaitedPlan));assert.deepEqual(snapshot(db),before);}finally{db.close();}
});
for(let failAt=0;failAt<awaitedPlan.length;failAt++)test('SQLite full rollback when statement '+failAt+' fails',()=>{
 const db=database();try{const before=snapshot(db);assert.throws(()=>execute(db,awaitedPlan,{failAt}),/injected failure/);assert.deepEqual(snapshot(db),before);}finally{db.close();}
});
test('SQLite snapshots aggregate existing group/member entries rather than a mobile increment',()=>{
 const db=database();try{
  db.prepare('INSERT INTO ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind) VALUES(?,?,?,?,?,?)').run('old-own','old-own-payment',ids.group,ids.member,5000,'contribution');
  db.prepare('INSERT INTO ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind) VALUES(?,?,?,?,?,?)').run('old-other','old-other-payment',ids.group,'other-member',7000,'contribution');
  execute(db,awaitedPlan);const s=db.prepare('SELECT * FROM contribution_posting_snapshots').get();assert.equal(s.member_balance_after_minor,17500);assert.equal(s.group_balance_after_minor,24500);
 }finally{db.close();}
});
