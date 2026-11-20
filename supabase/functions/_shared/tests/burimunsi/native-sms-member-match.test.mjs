import test from 'node:test';
import assert from 'node:assert/strict';
import {matchNativeSmsMember,nativeSmsPayerKey} from '../../domain/burimunsi/native-sms-member-match.js';

const member={id:'member-1',groupId:'group-1',name:'Alice Mukamana',momoNumber:'+250 788 123 456',active:true,eligible:true,memberType:'direct'};
const match=(payerName,payerIdentifier,members=[member],groupId='group-1')=>matchNativeSmsMember({groupId,payerName,payerIdentifier,members});

test('normalizes a complete number and name before matching within the collection',()=>{
 for(const phone of ['0788123456','788123456','250788123456','00250788123456','+250 788 123 456','+250.788.123.456'])
  assert.equal(match('  ALICE,  Mukamana ',phone),'member-1',phone);
});
test('a different complete number with the same name and last three digits cannot match',()=>{
 assert.equal(match('Alice Mukamana','0788999456'),null);
 assert.equal(match('Alice Mukamana','0788999456',[member,{...member,id:'member-2',momoNumber:'0788999456'}]),'member-2');
 assert.equal(match('Alice Mukamana','0788123456',[member,{...member,id:'member-2',momoNumber:'0788999456'}]),'member-1');
});
test('preserves unique normalized-name and masked suffix matching',()=>{
 assert.deepEqual(nativeSmsPayerKey('  ALICE,  Mukamana ','*****456'),{name:'alice mukamana',last3:'456'});
 for(const phone of ['*****456','xxx456','•••456','#456','456'])
  assert.equal(match('Alice Mukamana',phone),'member-1',phone);
 assert.equal(match('Alice Mukamana','*****456',[member,{...member,id:'member-2',momoNumber:'0788999456'}]),null);
});
test('documents masked suffix collision: an absent different payer can look identical',()=>{
 // Both complete numbers render the same masked evidence and the existing
 // product policy selects the sole roster entry. This cannot establish which
 // person actually paid; changing that policy needs separate direction.
 const sameMaskedEvidence='*****456';
 assert.equal(match('Alice Mukamana',sameMaskedEvidence,[member]),'member-1');
 assert.notEqual('0788123456','0788999456');
 assert.equal('0788123456'.slice(-3),'0788999456'.slice(-3));
 assert.equal(match('Alice Mukamana','0788999456',[member]),null);
});
test('does not invent a member for missing, mismatched or ambiguous identity',()=>{
 assert.equal(match('Alice Mukamana','**45'),null);
 assert.equal(match(null,'****456'),null);
 assert.equal(match('Alice Mukamana','****999'),null);
 assert.equal(match('Alice Mukamana','account123'),null);
 assert.equal(match('Alice Mukamana','****456xyz'),null);
 assert.equal(match('Another Person','****456'),null);
 assert.equal(match('Alice Mukamana','****456',[member,{...member,id:'member-2'}]),null);
 assert.equal(match('Alice Mukamana','0788123456',[member,{...member,id:'member-2'}]),null);
 for(const invalidFull of ['0788999456','+250788123456***','0788123456 / 0788999456','0988123456','123456789'])
  assert.equal(match('Alice Mukamana',invalidFull),null,invalidFull);
});
test('matches only currently eligible members of the receipt collection',()=>{
 for(const change of [{groupId:'group-2'},{active:false},{eligible:false},{memberType:'operator'},
  {momoNumber:'not-a-phone-456'},{momoNumber:'****456'}])
  for(const phone of ['0788123456','****456'])
   assert.equal(match('Alice Mukamana',phone,[{...member,...change}]),null,JSON.stringify(change));
 assert.equal(match('Alice Mukamana','0788123456',[member],'group-2'),null);
});
