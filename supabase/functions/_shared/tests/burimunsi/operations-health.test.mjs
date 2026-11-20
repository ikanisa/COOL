import test from 'node:test';import assert from 'node:assert/strict';
import {evaluateOperationalAlerts,PostgresOperationsHealth} from '../../domain/burimunsi/operations-health.js';
const snapshot={pending:3,oldestPendingMs:60000,expiredLeases:0,deadLetters:0};
const thresholds={maxPending:3,maxOldestPendingMs:60000,maxExpiredLeases:0,maxDeadLetters:0};
test('operational thresholds must be explicitly configured',()=>assert.throws(()=>evaluateOperationalAlerts(snapshot),/alert_thresholds_required/));
test('exact threshold does not generate false alert',()=>assert.deepEqual(evaluateOperationalAlerts(snapshot,thresholds),[]));
for(const [metric,code] of [['pending','processing_backlog'],['oldestPendingMs','processing_age'],['expiredLeases','worker_leases_expired'],['deadLetters','processing_dead_letters']])
 test('redacted alert '+metric,()=>{const alerts=evaluateOperationalAlerts({...snapshot,[metric]:snapshot[metric]+1,rawBody:'must not leak'},thresholds);assert.equal(alerts[0].code,code);assert.deepEqual(Object.keys(alerts[0]),['code','observed','threshold'])});
test('missing, negative and unsafe thresholds fail closed',()=>{for(const maxPending of [undefined,-1,NaN,9007199254740992])assert.throws(()=>evaluateOperationalAlerts(snapshot,{...thresholds,maxPending}),/invalid_alert_threshold/)});
test('SQL health projection is scoped and labels completed jobs, not deposits',async()=>{
 let parameters;
 const s=new PostgresOperationsHealth({authority:{groupId:'g',read:fn=>fn({unsafe:async(sql,p)=>{parameters=p;assert(sql.includes('j.collection_id=$1'));return [{now_ms:'100',pending:'3',oldest_pending_ms:'60',expired_leases:'0',dead_letters:'0',rejected:'1',completed:'5',raw_body:'not returned'}]}})}});
 const r=await s.snapshot();assert.deepEqual(parameters,['g']);assert.equal(r.completedJobs,5);assert.equal(r.raw_body,undefined);assert.match(r.basis,/not_capture_heartbeat/);
});
