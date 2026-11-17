import test from 'node:test';
import assert from 'node:assert/strict';
import current from './REFERENCE.json' with {type:'json'};
import previous from '../managed-storage-archive/REFERENCE.json' with {type:'json'};
import {compileCountsRequest,validateReference} from './counts.mjs';
import {validateStorageMetadataSnapshot as validateCurrent} from './storage.mjs';
import {validateStorageMetadataSnapshot as validatePrevious} from '../managed-storage-archive/storage.mjs';
import {syntheticSnapshot as currentSnapshot} from './native-definition.mjs';
import {syntheticSnapshot as previousSnapshot} from '../managed-storage-archive/native-definition.mjs';

const requestId='dbb19247-04cb-40b5-9198-7324ad766f08';

test('current catalogue retains every previously pinned relation and adds both lifecycle tables',()=>{
 const names=current.relations.map(r=>r.name);
 assert.equal(names.length,10);
 for(const relation of previous.relations){
  const found=current.relations.find(r=>r.name===relation.name);
  assert.deepEqual(found,relation);
  assert.deepEqual(current.columns.filter(c=>c.relation_oid===relation.oid),
                   previous.columns.filter(c=>c.relation_oid===relation.oid));
 }
 assert.deepEqual(names.filter(n=>!previous.relations.some(r=>r.name===n)),
                  ['bucket_lifecycle_states','lifecycle_abandoned_artifacts']);
 assert.deepEqual(current.types,previous.types);
 assert.equal(current.columns.length,91);
});

test('bounded read-only count request covers all ten exact pinned tables and rejects catalogue changes',()=>{
 const request=compileCountsRequest(current,requestId),sql=request.body.query;
 assert.equal(request.body.read_only,true);
 assert.ok(sql.startsWith('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;'));
 assert.ok(sql.endsWith('\nROLLBACK;'));
 for(const {name} of current.relations){
  assert.equal((sql.match(new RegExp(`FROM ONLY storage\\."${name}" LIMIT 10001`,'g'))??[]).length,1,name);
 }
 assert.ok(sql.includes('(SELECT valid FROM approved) IS TRUE'));
 for(const mutate of [r=>r.relations.pop(),r=>{r.columns[0].name='unreviewed';},r=>{r.types[0].oid='999';}]){
  const r=structuredClone(current);mutate(r);assert.throws(()=>validateReference(r));
 }
});

test('the predecessor and ten-table snapshots have distinct formats and cannot be silently interchanged',()=>{
 const before=previousSnapshot(),after=currentSnapshot();
 assert.notEqual(before.format,after.format);
 assert.equal(validatePrevious(before,{allowFixture:true}),before);
 assert.equal(validateCurrent(after,{allowFixture:true}),after);
 assert.throws(()=>validatePrevious(after,{allowFixture:true}));
 assert.throws(()=>validateCurrent(before,{allowFixture:true}));
});
