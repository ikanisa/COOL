import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {MOMO_JOB_CHECKPOINT,MOMO_PARSER_VERSION,validateMomoExtraction} from '../domain/momo_pipeline.js';

// Invented SMS, output and provider profile: this is not provider qualification.
const fixture=JSON.parse(await readFile(new URL('../../../../deploy/platform-api/test/fixtures/momo-synthetic.json',import.meta.url),'utf8'));

function check({body=fixture.body,output=fixture.output,prefixes=fixture.profile.transaction_id_prefixes}={}){
 const profile={...fixture.profile,transaction_id_prefixes:prefixes};
 const account={status:'active',profile_status:'approved',profile_version:'synthetic.v1',
  profile_json:JSON.stringify(profile),currency:'RWF',provider:'mtn_momo',timezone:'Africa/Kigali'};
 return validateMomoExtraction(structuredClone(output),{raw_sender:fixture.sender,raw_body:body,completeness:'complete'},account);
}
function withSelectedId(id,label='Transaction ID:'){
 const output=structuredClone(fixture.output);
 output.transaction_id_raw=id;
 output.evidence.transaction_id=`${label} ${id}`;
 return output;
}
function denied(result){
 assert.equal(result.accepted,false);
 assert(result.errors.some(error=>error.code==='provider_identity_unverified'));
}

test('single synthetic reference retains its exact ID and versioned checkpoint contract',()=>{
 const result=check();
 assert.equal(result.accepted,true);
 assert.equal(result.facts.provider_transaction_id,'001234567890');
 assert.equal(MOMO_PARSER_VERSION,'momo-validation.v4');
 assert.equal(MOMO_JOB_CHECKPOINT.dispatch,'momo_v2:provider_dispatch');
 assert.equal(MOMO_JOB_CHECKPOINT.unknown,'momo_v2:provider_outcome_unknown');
});

test('different IDs under the same approved label reject either selected ID',()=>{
 const second='009999999999';
 const body=`${fixture.body} Transaction ID: ${second}.`;
 denied(check({body}));
 denied(check({body,output:withSelectedId(second)}));
});

test('different approved labels and case variants reject either selected ID',()=>{
 const second='009999999999';
 const body=`${fixture.body} tXiD: ${second}.`;
 const prefixes=['Transaction ID:','TXID:'];
 denied(check({body,prefixes}));
 denied(check({body,prefixes,output:withSelectedId(second,'tXiD:')}));
});

test('repeated selected ID remains unverified',()=>{
 denied(check({body:`${fixture.body} Transaction ID: 001234567890.`}));
});

test('overlapping and duplicate approved aliases inside the chosen label count once',()=>{
 for(const prefixes of [
  ['ID:','Transaction ID:','Transaction ID:'],
  ['transaction id:','id:','TRANSACTION ID:'],
 ]){
  assert.equal(check({prefixes}).accepted,true);
 }
});

test('an approved label embedded in another Unicode word does not add a reference',()=>{
 const prefixes=['ID:','Transaction ID:'];
 for(const prior of ['PA','é','A\u0301','𐐀','_']){
  assert.equal(check({body:`${fixture.body} ${prior}ID: 009999.`,prefixes}).accepted,true,prior);
 }
});

test('a separate standalone approved label is conservatively rejected',()=>{
 const prefixes=['ID:','Transaction ID:'];
 denied(check({body:`${fixture.body} note ID: 009999.`,prefixes}));
 denied(check({body:`${fixture.body} 🧪ID: 009999.`,prefixes}));
 denied(check({body:`${fixture.body} Transaction ID:`,prefixes}));
});

test('a selected label embedded in a word is unverified',()=>{
 const body=fixture.body.replace('Transaction ID:','PAID:');
 denied(check({body,prefixes:['ID:'],output:withSelectedId('001234567890','PAID:')}));
});

test('overlapping punctuation-only literal labels cannot hide a second match',()=>{
 const body=fixture.body.replace('Transaction ID: 001234567890',':::123');
 const output=withSelectedId(':123','::');
 output.evidence.transaction_id=':::123';
 denied(check({body,prefixes:['::'],output}));
});

test('regex metacharacters in approved labels remain literal',()=>{
 const label='Transaction (ID):';
 const body=fixture.body.replace('Transaction ID:',label);
 const output=withSelectedId('001234567890',label);
 assert.equal(check({body,output,prefixes:[label]}).accepted,true);
 denied(check({body:`${body} ${label} 009999.`,output,prefixes:[label]}));
});

test('the selected reference cannot be the prefix of a longer token',()=>{
 const body=fixture.body.replaceAll('001234567890','0012345678909');
 denied(check({body}));
});

test('combining marks continue a reference directly and after a dot',()=>{
 const original='001234567890';
 for(const continuation of ['\u0301','.\u0301']){
  const complete=original+continuation;
  const body=fixture.body.replaceAll(original,complete);
  denied(check({body}));
  const result=check({body,output:withSelectedId(complete)});
  assert.equal(result.accepted,true);
  assert.equal(result.facts.provider_transaction_id,complete);
 }
});

test('the labeled ID must exactly match the claimed spelling; label case may differ',()=>{
 const body=fixture.body.replace('Transaction ID: 001234567890','tRaNsAcTiOn iD: ABC123')+' note abc123.';
 denied(check({body,output:withSelectedId('abc123','note')}));
 const exact=check({body,output:withSelectedId('ABC123','tRaNsAcTiOn iD:')});
 assert.equal(exact.accepted,true);
 assert.equal(exact.facts.provider_transaction_id,'ABC123');
});
