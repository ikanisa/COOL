import test from 'node:test';
import assert from 'node:assert/strict';
import {workerEnvironment} from '../../deploy/self-hosted/edge-main/environment.mjs';

const features={
 BURIMUNSI_SMS_OBSERVATIONS_ENABLED:'true',
 BURIMUNSI_ADMIN_SMS_OBSERVATIONS_ENABLED:'true',
 BURIMUNSI_OBSERVATION_HINTS_ENABLED:'true',
 BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED:'true',
 BURIMUNSI_NATIVE_AUTO_RECORDS_ENABLED:'true',
 BURIMUNSI_STAFF_PIN_PHONE_PRESERVATION_ENABLED:'true',
 BURIMUNSI_RETENTION_INSPECTION_ENABLED:'true',
 COLLECT_ADMIN_OWNER_IDENTITY_ENABLED:'true',
 COLLECT_ADMIN_DYNAMIC_OWNER_AUTH_ENABLED:'true',
};

test('private feature switches reach the responsible edge workers',()=>{
 const native=Object.fromEntries(workerEnvironment('collect-api',features));
 const admin=Object.fromEntries(workerEnvironment('admin-api',features));
 for(const name of ['BURIMUNSI_SMS_OBSERVATIONS_ENABLED','BURIMUNSI_OBSERVATION_HINTS_ENABLED',
                    'BURIMUNSI_STAFF_PIN_PHONE_PRESERVATION_ENABLED'])assert.equal(native[name],'true',name);
 for(const name of ['BURIMUNSI_ADMIN_SMS_OBSERVATIONS_ENABLED','BURIMUNSI_OBSERVATION_HINTS_ENABLED',
                    'BURIMUNSI_RETENTION_INSPECTION_ENABLED','COLLECT_ADMIN_OWNER_IDENTITY_ENABLED',
                    'COLLECT_ADMIN_DYNAMIC_OWNER_AUTH_ENABLED'])assert.equal(admin[name],'true',name);
 for(const worker of ['collect-api','collect-jobs']){
  const scoped=Object.fromEntries(workerEnvironment(worker,features));
  assert.equal(scoped.BURIMUNSI_RETENTION_INSPECTION_ENABLED,'true',worker);
  assert.equal(scoped.BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED,'true',worker);
 }
 for(const worker of ['collect-sms','send-sms-hook']){
  const scoped=Object.fromEntries(workerEnvironment(worker,features));
  for(const name of Object.keys(features))assert.equal(scoped[name],undefined,worker+': '+name);
 }
});

test('absent switches are not silently enabled by worker projection',()=>{
 for(const worker of ['collect-api','admin-api']){
  const scoped=Object.fromEntries(workerEnvironment(worker,{}));
  for(const name of Object.keys(features))assert.equal(scoped[name],undefined,worker+': '+name);
 }
});

test('canonical scheduler controls and managed session reach only the jobs worker',()=>{
 const scheduler={BURIMUNSI_CANONICAL_SCHEDULER_ENABLED:'true',
  BURIMUNSI_CANONICAL_SCHEDULER_MANAGED_ACCESS_TOKEN:'synthetic.private.token',
  BURIMUNSI_CANONICAL_SCHEDULER_COLLECTION_ID:'group-1'};
 const jobs=Object.fromEntries(workerEnvironment('collect-jobs',scheduler));
 assert.deepEqual(Object.fromEntries(Object.keys(scheduler).map(key=>[key,jobs[key]])),scheduler);
 for(const worker of ['collect-api','admin-api','collect-sms','send-sms-hook','collect-email-jobs']){
  const values=Object.fromEntries(workerEnvironment(worker,scheduler));
  for(const key of Object.keys(scheduler))assert.equal(values[key],undefined,worker+': '+key);
 }
});
