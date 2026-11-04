import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {validateMomoExtraction} from '../domain/momo_pipeline.js';

// Invented text and profile only; no real message or provider is involved.
const fixture=JSON.parse(await readFile(new URL('../../../../deploy/platform-api/test/fixtures/momo-synthetic.json',import.meta.url),'utf8'));
const account={status:'active',profile_status:'approved',profile_version:'synthetic.v1',profile_json:JSON.stringify(fixture.profile),currency:'RWF',provider:'mtn_momo',timezone:'Africa/Kigali'};
const source=body=>({raw_sender:fixture.sender,raw_body:body,completeness:'complete'});
const extract=()=>structuredClone(fixture.output);
const has=(result,code)=>result.errors.some(error=>error.code===code);

test('complete amounts and sentence punctuation retain valid synthetic evidence',()=>{
 const output=extract();
 assert.equal(validateMomoExtraction(output,source(fixture.body),account).accepted,true);
 output.evidence.wallet_balance_after='Balance: RWF 125,000.';
 assert.equal(validateMomoExtraction(output,source(fixture.body),account).accepted,true);
 output.fee_amount_raw=null;output.evidence.fee=null;
 output.wallet_balance_after_raw=null;output.evidence.wallet_balance_after=null;
 assert.equal(validateMomoExtraction(output,source(fixture.body),account).accepted,true);
});

test('a balance cannot be a prefix or suffix of another source amount',()=>{
 for(const partial of ['125','5,000']){
  const output=extract();output.wallet_balance_after_raw=partial;
  const result=validateMomoExtraction(output,source(fixture.body),account);
  assert.equal(result.accepted,false,partial);
  assert(has(result,'balance_role_unverified'),partial);
 }
});

test('an excerpt cut inside a larger balance does not establish a whole amount',()=>{
 const output=extract();output.wallet_balance_after_raw='125';
 output.evidence.wallet_balance_after='Balance: RWF 125';
 // The same whole number elsewhere must not validate this truncated excerpt.
 const result=validateMomoExtraction(output,source(fixture.body+' Note 125.'),account);
 assert.equal(result.accepted,false);
 assert(has(result,'balance_role_unverified'));
});

test('a later complete amount in the same excerpt remains usable',()=>{
 const body=fixture.body.replace('Balance: RWF 125,000.','Note 9125 and Balance: 125.');
 const output=extract();output.wallet_balance_after_raw='125';
 output.evidence.wallet_balance_after='125 and Balance: 125';
 assert.equal(validateMomoExtraction(output,source(body),account).accepted,true);
});

test('a fee cannot be a trailing digit of a different fee',()=>{
 const body=fixture.body.replace('Fee: RWF 0.','Fee: RWF 10.');
 const output=extract();output.evidence.fee='Fee: RWF 10';
 const result=validateMomoExtraction(output,source(body),account);
 assert.equal(result.accepted,false);
 assert(has(result,'fee_role_unverified'));
});

test('an amount excerpt cannot truncate a decimal amount',()=>{
 const body=fixture.body.replace('Balance: RWF 125,000.','Balance: RWF 125,000.50.');
 const output=extract();output.evidence.wallet_balance_after='Balance: RWF 125,000.50';
 const result=validateMomoExtraction(output,source(body),account);
 assert.equal(result.accepted,false);
 assert(has(result,'balance_role_unverified'));
});

test('a principal evidence excerpt cannot use a suffix of another amount',()=>{
 const body=fixture.body+' Note: RWF 15,000.';
 const output=extract();output.evidence.principal='RWF 15,000';
 const result=validateMomoExtraction(output,source(body),account);
 assert.equal(result.accepted,false);
 assert(has(result,'principal_role_unverified'));
});

test('adjacent non-ASCII digits cannot make a partial fee look complete',()=>{
 const body=fixture.body.replace('Fee: RWF 0.','Fee: RWF ١0.');
 const output=extract();output.evidence.fee='Fee: RWF ١0';
 const result=validateMomoExtraction(output,source(body),account);
 assert.equal(result.accepted,false);
 assert(has(result,'fee_role_unverified'));
});

test('signed balances and fees cannot be stored as positive amounts',()=>{
 for(const sign of ['-','−','+','－','＋']){
  const body=fixture.body.replace('Balance: RWF 125,000.',`Balance: RWF ${sign}125,000.`);
  const output=extract();output.evidence.wallet_balance_after=`Balance: RWF ${sign}125,000`;
  const result=validateMomoExtraction(output,source(body),account);
  assert.equal(result.accepted,false,sign);
  assert(has(result,'balance_role_unverified'),sign);
 }
 const body=fixture.body.replace('Fee: RWF 0.','Fee: RWF - 0.');
 const output=extract();output.evidence.fee='Fee: RWF - 0';
 const result=validateMomoExtraction(output,source(body),account);
 assert.equal(result.accepted,false);
 assert(has(result,'fee_role_unverified'));
 for(const enclosedText of ['RWF (125,000)','(125,000 RWF)','( RWF 125,000 )']){
  const parentheses=fixture.body.replace('Balance: RWF 125,000.',`Balance: ${enclosedText}.`);
  const ambiguous=extract();ambiguous.evidence.wallet_balance_after=`Balance: ${enclosedText}`;
  const enclosed=validateMomoExtraction(ambiguous,source(parentheses),account);
  assert.equal(enclosed.accepted,false,enclosedText);
  assert(has(enclosed,'balance_role_unverified'),enclosedText);
 }
});

test('a space-grouped principal cannot be accepted as its leading digits',()=>{
 for(const separator of [' ','\u00a0','\u202f',' , ',' . ']){
  const body=fixture.body.replace('You have received RWF 5,000',`You have received RWF 125${separator}000`);
  const output=extract();output.principal_amount_raw='125';
  output.evidence.incoming_success='You have received RWF 125';
  output.evidence.principal='RWF 125';
  const result=validateMomoExtraction(output,source(body),account);
  assert.equal(result.accepted,false,JSON.stringify(separator));
  assert(has(result,'principal_role_unverified'),JSON.stringify(separator));
 }
});

test('the incoming principal cannot stop before a Unicode digit, separator or exponent',()=>{
 for(const suffix of ['١','٫000','，000','e3','E+3']){
  const body=fixture.body.replace('You have received RWF 5,000',`You have received RWF 125${suffix}`)+' Note 125.';
  const output=extract();output.principal_amount_raw='125';
  output.evidence.incoming_success='You have received RWF 125';
  output.evidence.principal='Note 125';
  const result=validateMomoExtraction(output,source(body),account);
  assert.equal(result.accepted,false,suffix);
  assert(has(result,'principal_role_unverified'),suffix);
 }
});

test('maximum-size repeated negative excerpts remain bounded',()=>{
 const body=fixture.body.replace('You have received RWF 5,000','You have received RWF 1')+' '+('-1 '.repeat(5000));
 const output=extract();output.principal_amount_raw='1';
 output.evidence.incoming_success='You have received RWF 1';
 output.evidence.principal='-1 '.repeat(680);
 const start=performance.now();
 const result=validateMomoExtraction(output,source(body),account);
 const elapsed=performance.now()-start;
 assert.equal(result.accepted,false);
 assert(has(result,'principal_role_unverified'));
 assert(elapsed<5000,`synthetic validation took ${elapsed.toFixed(0)} ms`);
});
