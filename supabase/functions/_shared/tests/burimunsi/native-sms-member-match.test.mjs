import test from 'node:test';
import assert from 'node:assert/strict';
import {matchNativeSmsMember,nativeSmsPayerKey} from '../../domain/burimunsi/native-sms-member-match.js';

const member={id:'member-1',groupId:'group-1',name:'Alice Mukamana',momoNumber:'+250 788 123 456',active:true,eligible:true,memberType:'direct'};
const match=(payerName,payerIdentifier,members=[member],groupId='group-1')=>matchNativeSmsMember({groupId,payerName,payerIdentifier,members});

test('matches normalized name and masked final three digits inside the collection',()=>{
 assert.deepEqual(nativeSmsPayerKey('  ALICE,  Mukamana ', '*****456'),{name:'alice mukamana',last3:'456'});
 assert.equal(match('  ALICE,  Mukamana ', '*****456'),'member-1');
 assert.equal(match('Alice Mukamana', '+250788123456'),'member-1');
});
test('does not invent a member for missing, mismatched or ambiguous identity',()=>{
 assert.equal(match('Alice Mukamana','**45'),null);
 assert.equal(match(null,'****456'),null);
 assert.equal(match('Alice Mukamana','****999'),null);
 assert.equal(match('Alice Mukamana','account123'),null);
 assert.equal(match('Alice Mukamana','****456xyz'),null);
 assert.equal(match('Another Person','****456'),null);
 assert.equal(match('Alice Mukamana','****456',[member,{...member,id:'member-2'}]),null);
});
test('matches only currently eligible members of the receipt collection',()=>{
 assert.equal(match('Alice Mukamana','****456',[{...member,groupId:'group-2'}]),null);
 assert.equal(match('Alice Mukamana','****456',[{...member,active:false}]),null);
 assert.equal(match('Alice Mukamana','****456',[{...member,eligible:false}]),null);
 assert.equal(match('Alice Mukamana','****456',[{...member,memberType:'operator'}]),null);
 assert.equal(match('Alice Mukamana','****456',[{...member,momoNumber:'not-a-phone-456'}]),null);
});
