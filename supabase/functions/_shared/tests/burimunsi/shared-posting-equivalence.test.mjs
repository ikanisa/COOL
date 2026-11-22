import test from 'node:test';import assert from 'node:assert/strict';
import {setup,upstream,refactored,blob,expectedBlob,ids} from './shared-posting-fixture.mjs';
const cases=[
 ['approval',()=>({})],['legacy snapshot absent',()=>({snapshot:false})],['rejection',()=>({}),'reject_payment_reconciliation_v2'],
 ['permission refusal',()=>({permission:false})],
 ['retained success',()=>({retained:[{found:true,value:{id:'previous',status:'approved'}}]})],
 ['missing reconciliation',()=>({reconciliation:null})],
 ['missing reconciliation recovered receipt',()=>({reconciliation:null,retained:[{found:false},{found:true,value:{id:'previous'}}]})],
 ['already reviewed',()=>({reconciliation:{...setup().state.reconciliation,status:'approved'}})],
 ['same reviewer',()=>({reconciliation:{...setup().state.reconciliation,proposed_by:ids.actor}})],
 ['stale payment',()=>({payment:{...setup().state.payment,revision:8}})],
 ['stale payment recovered receipt',()=>({payment:{...setup().state.payment,revision:8},retained:[{found:false},{found:true,value:{status:'approved'}}]})],
 ['assigned member',()=>({payment:{...setup().state.payment,member_id:ids.member}})],
 ['reversed payment',()=>({payment:{...setup().state.payment,status:'reversed'}})],
 ['missing evidence',()=>({evidence:null})],
 ['empty reference',()=>({evidence:{...setup().state.evidence,external_reference:' '}})],
 ['wrong provider',()=>({evidence:{...setup().state.evidence,receiver_network:'other'}})],
 ['wrong evidence currency',()=>({evidence:{...setup().state.evidence,currency:'USD'}})],
 ['wrong payment currency',()=>({payment:{...setup().state.payment,currency:'USD'}})],
 ['wrong rail',()=>({payment:{...setup().state.payment,rail:'cash'}})],
 ['missing receiver',()=>({evidence:{...setup().state.evidence,receiver_momo_number:''}})],
 ['short reason',()=>({body:{...setup().state.body,p_reason:'short'}})],
 ['explicit internal permission',()=>({}),undefined,{permission:'reconciliations.review',freshSeconds:300}],
 ['invalid internal permission',()=>({}),undefined,{permission:'payments.write'}],
 ['rejection still refuses same reviewer',()=>({reconciliation:{...setup().state.reconciliation,proposed_by:ids.actor}}),'reject_payment_reconciliation_v2'],
 ['rejection does not test receipt evidence',()=>({evidence:null}),'reject_payment_reconciliation_v2']
];
test('original payments.js is the exact inspected Git blob',()=>assert.equal(blob(upstream),expectedBlob));
for(const [label,make,operation,internal]of cases)test('shared extraction preserves full RPC statement/read/ID/clock sequence: '+label,async()=>{
 const left=await setup(make()).run(upstream,operation,internal),right=await setup(make()).run(refactored,operation,internal);
 assert.deepEqual(right,left);
});
test('approval retains one ledger insert, collision and destination guards, snapshot, intent, notification and audit',async()=>{
 const {state,error}=await setup().run();assert.equal(error,undefined);
 const sql=state.writes.map(w=>w.sql);
 assert.equal(sql.filter(q=>q.startsWith('INSERT INTO ledger_entries')).length,1);
 for(const table of ['contribution_posting_snapshots','notification_events','audit_log'])assert.ok(sql.some(q=>q.startsWith('INSERT INTO '+table)));
 assert.ok(sql.some(q=>q.startsWith('UPDATE payment_intents')));
 assert.ok(sql[0].includes('momo_financial_links'));assert.ok(sql[1].includes('other_evidence'));
 assert.equal(state.mutations.length,1);assert.equal(state.mutations[0].options.minimumAssurance,2);
});
test('rejection prepares no financial/notification statements',async()=>{
 const {state,error}=await setup().run(refactored,'reject_payment_reconciliation_v2');assert.equal(error,undefined);
 assert.equal(state.writes.length,3);assert.ok(state.writes.every(w=>!/ledger_entries|notification_events|contribution_posting_snapshots/.test(w.sql)));
});
