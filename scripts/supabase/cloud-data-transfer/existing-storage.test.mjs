import test from 'node:test';
import assert from 'node:assert/strict';
import {validateExistingStorage} from './graph-transaction.mjs';
const tables=['private.storage_put_intents','private.storage_upload_attempts','private.storage_objects'];
function fixture(){
 const put={operation_id:'cloud-op',object_key:'cloud-object',fingerprint:'fp',sha256:'sha',size:10,scope:{purpose:'synthetic'},
  state:'committed',active_attempt:null,upload_unresolved:false,delete_tombstone:false};
 const attempt={id:'cloud-attempt',operation_id:'cloud-op',completed_at:'2026-01-01T00:00:00Z'};
 const object={operation_id:'cloud-op',object_key:'cloud-object',fingerprint:'fp',sha256:'sha',size:10,scope:{purpose:'synthetic'},etag:'cloud-etag'};
 const baseline=Object.fromEntries(tables.map((t,i)=>[t,[[put],[attempt],[object]][i]]));
 const capture={snapshot:{tables:Object.fromEntries(tables.map((t,i)=>[t,[[{operation_id:'source-op',object_key:'source-object'}],
  [{id:'source-attempt',operation_id:'source-op'}],[{operation_id:'source-op',object_key:'source-object'}]][i]]))}};
 const catalog=Object.fromEntries(tables.map((t,i)=>[t,{columns:[['operation_id','object_key'],['id','operation_id'],['operation_id','object_key']][i].map(name=>({name}))}]));
 return {baseline,capture,catalog};
}
test('preserves disjoint committed Cloud storage journals',()=>{let x=fixture();assert.equal(validateExistingStorage(x.baseline,x.capture,x.catalog),true)});
test('rejects overlapping object identities and uncommitted or altered Cloud journals',()=>{
 let x=fixture();x.capture.snapshot.tables[tables[0]][0].operation_id='cloud-op';
 assert.throws(()=>validateExistingStorage(x.baseline,x.capture,x.catalog),/existing_storage_identifier_overlap/);
 x=fixture();x.baseline[tables[0]][0].upload_unresolved=true;
 assert.throws(()=>validateExistingStorage(x.baseline,x.capture,x.catalog),/existing_storage_journal_unqualified/);
 x=fixture();x.baseline[tables[2]][0].sha256='different';
 assert.throws(()=>validateExistingStorage(x.baseline,x.capture,x.catalog),/existing_storage_journal_unqualified/);
 x=fixture();x.baseline[tables[1]][0].completed_at=null;
 assert.throws(()=>validateExistingStorage(x.baseline,x.capture,x.catalog),/existing_storage_journal_unqualified/);
});
