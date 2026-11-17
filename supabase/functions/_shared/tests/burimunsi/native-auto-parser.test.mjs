import test from 'node:test';
import assert from 'node:assert/strict';
import {NATIVE_AUTO_EXTRACTION_SCHEMA,NATIVE_AUTO_SCHEMA_VERSION,prepareNativeAutoExtraction,validateNativeAutoExtraction} from '../../domain/burimunsi/native-auto-parser.js';
import {MOMO_SCHEMA_VERSION} from '../../domain/momo_pipeline.js';

const account={provider:'mtn_momo',status:'active',profile_status:'approved',profile_version:'synthetic-1',currency:'RWF',timezone:'Africa/Kigali',
 profile_json:JSON.stringify({sender_allowlist:['Example Money'],currency_aliases:['RWF'],incoming_prefixes:['You have received'],
  transaction_id_prefixes:['Reference:'],outgoing_markers:['You have sent'],date_format:'YMD_HMS',utc_offset_minutes:120})};
const source=raw_body=>({raw_sender:'Example Money',raw_body,source_mode:'catch_up'});
const extraction=(values={})=>({schema_version:MOMO_SCHEMA_VERSION,event_kind:'unknown',payment_outcome:'unknown',
 transaction_id_raw:null,original_transaction_id_raw:null,transaction_datetime_raw:null,principal_amount_raw:null,currency_raw:null,
 payer_name_raw:null,payer_identifier_raw:null,payment_reference_raw:null,fee_amount_raw:null,wallet_balance_after_raw:null,
 evidence:{incoming_success:null,principal:null,transaction_id:null,transaction_datetime:null,payer:null,fee:null,wallet_balance_after:null},
 issues:[],...values});
const incoming='You have received 1,250 RWF from Example Person. Reference: ABC123. Fee 10 RWF. Balance 9,000 RWF.';
const incomingOutput=extraction({event_kind:'incoming_receipt',payment_outcome:'successful',transaction_id_raw:'ABC123',
 principal_amount_raw:'1,250',currency_raw:'RWF',payer_name_raw:'Example Person',fee_amount_raw:'10',wallet_balance_after_raw:'9,000',
 evidence:{incoming_success:'You have received',principal:'You have received 1,250 RWF',transaction_id:'Reference: ABC123',
  transaction_datetime:null,payer:'from Example Person',fee:'Fee 10 RWF',wallet_balance_after:'Balance 9,000 RWF'}});

test('incoming transaction preserves supported source values without creating financial effects',()=>{
 const result=validateNativeAutoExtraction(source(incoming),account,incomingOutput);
 assert.equal(result.kind,'parsed');assert.equal(result.direction,'incoming');
 assert.deepEqual(result.facts,{source_mode:'catch_up',event_kind:'incoming_receipt',payment_outcome:'successful',provider_transaction_id:'ABC123',
  original_transaction_id:null,amount_minor:1250,currency:'RWF',counterparty_name:'Example Person',counterparty_identifier:null,
  transaction_at:null,transaction_datetime_raw:null,fee_minor:10,wallet_balance_after_minor:9000});
});
test('balance and fee accept a single exact currency-qualified quote',()=>{
 for(const [raw,evidence,body] of [
  ['9,000 RWF','Balance 9,000 RWF',incoming],
  ['RWF 9,000','Balance RWF 9,000',incoming.replace('Balance 9,000 RWF','Balance RWF 9,000')],
 ]){
  const output={...incomingOutput,wallet_balance_after_raw:raw,evidence:{...incomingOutput.evidence,wallet_balance_after:evidence}};
  assert.equal(validateNativeAutoExtraction(source(body),account,output).facts.wallet_balance_after_minor,9000);
 }
 const fee={...incomingOutput,fee_amount_raw:'10 RWF'};
 assert.equal(validateNativeAutoExtraction(source(incoming),account,fee).facts.fee_minor,10);
 const body='You have received 1,250 RWF from Example Person. Balance 9000 RWF, Fee 10 RWF.';
 const punctuation={...incomingOutput,transaction_id_raw:null,wallet_balance_after_raw:'9000 RWF',
  evidence:{...incomingOutput.evidence,transaction_id:null,wallet_balance_after:'Balance 9000 RWF, Fee 10 RWF'}};
 assert.equal(validateNativeAutoExtraction(source(body),account,punctuation).facts.wallet_balance_after_minor,9000);
});
test('currency-qualified balance cannot combine or truncate financial amounts',()=>{
 for(const raw of ['9,000 RWF. Fee 10 RWF','9,000 RWF 10','RWF 9,000.50','RWF 9,000 RWF']){
  const body=`You have received 1,250 RWF from Example Person. Balance ${raw}.`;
  const output={...incomingOutput,transaction_id_raw:null,fee_amount_raw:null,wallet_balance_after_raw:raw,
   evidence:{...incomingOutput.evidence,transaction_id:null,fee:null,wallet_balance_after:`Balance ${raw}`}};
  const parsed=validateNativeAutoExtraction(source(body),account,output);
  assert.equal(parsed.kind,'parsed');assert.equal(parsed.facts.wallet_balance_after_minor,null);
 }
});
test('currency-qualified balance rejects a quote embedded in a longer token',()=>{
 for(const [bodyTail,raw] of [['Balance 9000 RWFx','9000 RWF'],['Balance XRWF9000','RWF9000']]){
  const body=`You have received 1,250 RWF from Example Person. ${bodyTail}.`;
  const output={...incomingOutput,transaction_id_raw:null,fee_amount_raw:null,wallet_balance_after_raw:raw,
   evidence:{...incomingOutput.evidence,transaction_id:null,fee:null,wallet_balance_after:bodyTail}};
  const parsed=validateNativeAutoExtraction(source(body),account,output);
  assert.equal(parsed.kind,'parsed');assert.equal(parsed.facts.wallet_balance_after_minor,null);
 }
 const body='You have received 1,250 RWF from Example Person. Balance 9000 RWFx.';
 const truncated={...incomingOutput,transaction_id_raw:null,fee_amount_raw:null,wallet_balance_after_raw:'9000 RWF',
  evidence:{...incomingOutput.evidence,transaction_id:null,fee:null,wallet_balance_after:'Balance 9000 RWF'}};
 assert.equal(validateNativeAutoExtraction(source(body),account,truncated).facts.wallet_balance_after_minor,null);
});
test('a payment-reference field becomes an ID only under a configured ID prefix',()=>{
 const output={...incomingOutput,transaction_id_raw:null,payment_reference_raw:'ABC123',
  evidence:{...incomingOutput.evidence,transaction_id:null}};
 assert.equal(validateNativeAutoExtraction(source(incoming),account,output).facts.provider_transaction_id,'ABC123');
 const noPrefix={...account,profile_json:JSON.stringify({...JSON.parse(account.profile_json),transaction_id_prefixes:['FT ID:']})};
 assert.equal(validateNativeAutoExtraction(source(incoming),noPrefix,output).facts.provider_transaction_id,null);
});
test('outgoing transaction is classified separately and keeps amount, reference and counterparty',()=>{
 const body='You have sent 250 RWF to Example Shop. Reference: XYZ77. Fee 5 RWF.';
 const output=extraction({event_kind:'outgoing',payment_outcome:'successful',transaction_id_raw:'XYZ77',principal_amount_raw:'250',
  currency_raw:'RWF',payer_name_raw:'Example Shop',fee_amount_raw:'5',evidence:{incoming_success:'You have sent',
   principal:'You have sent 250 RWF',transaction_id:'Reference: XYZ77',transaction_datetime:null,payer:'to Example Shop',
   fee:'Fee 5 RWF',wallet_balance_after:null}});
 const result=validateNativeAutoExtraction(source(body),account,output);
 assert.equal(result.direction,'outgoing');assert.equal(result.facts.event_kind,'outgoing');assert.equal(result.facts.amount_minor,250);
 assert.equal(result.facts.counterparty_name,'Example Shop');assert.equal(result.facts.provider_transaction_id,'XYZ77');
});
test('completed outgoing source quotes work when the direction quote was omitted',()=>{
 const body='Your payment of 250 RWF to Example Shop has been completed.';
 const output=extraction({event_kind:'outgoing',payment_outcome:'successful',principal_amount_raw:'250',currency_raw:'RWF',
  evidence:{incoming_success:null,principal:body,transaction_id:null,transaction_datetime:null,payer:null,fee:null,wallet_balance_after:null}});
 const got=validateNativeAutoExtraction(source(body),account,output);
 assert.equal(got.facts.event_kind,'outgoing');assert.equal(got.facts.amount_minor,250);
 const short={...output,evidence:{...output.evidence,principal:'Your payment of 250 RWF',incoming_success:body}};
 assert.equal(validateNativeAutoExtraction(source(body),account,short).facts.event_kind,'outgoing');
 const transfer='250 RWF transferred to Example Shop (***123) from ***456 at 12:30.';
 const transferOutput={...output,evidence:{...output.evidence,principal:transfer}};
 assert.equal(validateNativeAutoExtraction(source(transfer),account,transferOutput).facts.event_kind,'outgoing');
});
test('completed transfers accept one exact currency-qualified principal',()=>{
 for(const raw of ['1,250 RWF','RWF 1,250','1250RWF','RWF1250']){
  const body=`*123*Example*${raw} transferred to Example Shop (***123) from ***456 at 2026-11-13 12:30.`;
  const output=extraction({event_kind:'outgoing',payment_outcome:'successful',principal_amount_raw:raw,currency_raw:'RWF',
   evidence:{incoming_success:null,principal:body,transaction_id:null,transaction_datetime:null,payer:null,fee:null,wallet_balance_after:null}});
  const result=validateNativeAutoExtraction(source(body),account,output);
  assert.equal(result.kind,'parsed');assert.equal(result.facts.event_kind,'outgoing');
  assert.equal(result.facts.amount_minor,1250);assert.equal(result.facts.currency,'RWF');
 }
});
test('currency-qualified principal rejects invalid, ambiguous and truncated amounts',()=>{
 const cases=[
  ['250 USD','250 USD','USD'],
  ['250.50 RWF','250.50 RWF','RWF'],
  ['250.50 RWF','250','RWF'],
  ['9007199254740992 RWF','9007199254740992 RWF','RWF'],
  ['250 RWF and 10 RWF','250 RWF','RWF'],
  ['250 RWF and 250 RWF','250 RWF','RWF'],
  ['1250 RWF','250 RWF','RWF'],
  ['250 RWFx','250 RWF','RWF'],
  ['XRWF250','RWF250','RWF'],
 ];
 for(const [amount,raw,currency] of cases){
  const body=`${amount} transferred to Example Shop from Example Wallet at 12:30.`;
  const output=extraction({event_kind:'outgoing',payment_outcome:'successful',principal_amount_raw:raw,currency_raw:currency,
   evidence:{incoming_success:null,principal:body,transaction_id:null,transaction_datetime:null,payer:null,fee:null,wallet_balance_after:null}});
  const result=validateNativeAutoExtraction(source(body),account,output);
  assert.equal(result.kind,'parsed');assert.equal(result.facts.amount_minor,null,`${amount} / ${raw}`);
 }
});
test('a currency-qualified pending payment is not a completed outgoing transaction',()=>{
 for(const body of ['Your payment of 250 RWF is pending.',
  '250 RWF transferred to Example Shop from Example Wallet at 12:30, pending.',
  '250 RWF transferred to Example Shop from Example Wallet at 12:30, failed.']){
  const output=extraction({event_kind:'outgoing',payment_outcome:'successful',principal_amount_raw:'250 RWF',currency_raw:'RWF',
   evidence:{incoming_success:null,principal:body,transaction_id:null,transaction_datetime:null,payer:null,fee:null,wallet_balance_after:null}});
  const result=validateNativeAutoExtraction(source(body),account,output);
  assert.equal(result.facts.event_kind,'unknown');assert.equal(result.facts.amount_minor,null);
 }
});
test('an unfinished payment quote does not establish a successful outgoing event',()=>{
 const body='Your payment of 250 RWF to Example Shop is pending.';
 const output=extraction({event_kind:'outgoing',payment_outcome:'successful',principal_amount_raw:'250',currency_raw:'RWF',
  evidence:{incoming_success:null,principal:body,transaction_id:null,transaction_datetime:null,payer:null,fee:null,wallet_balance_after:null}});
 assert.equal(validateNativeAutoExtraction(source(body),account,output).facts.event_kind,'unknown');
 for(const suffix of ['is pending','failed','has not been completed']){
  const text=`Your payment of 250 RWF ${suffix}.`,quote='Your payment of 250 RWF';
  const incomplete={...output,evidence:{...output.evidence,incoming_success:quote,principal:quote}};
  assert.equal(validateNativeAutoExtraction(source(text),account,incomplete).facts.event_kind,'unknown');
 }
 const unrelated='Your payment of 250 RWF is pending. Your payment of 999 RWF has been completed.';
 const incomplete={...output,evidence:{...output.evidence,incoming_success:'Your payment of 250 RWF',principal:'Your payment of 250 RWF'}};
 assert.equal(validateNativeAutoExtraction(source(unrelated),account,incomplete).facts.event_kind,'unknown');
});
test('missing, truncated or unsupported facts cannot become invented transaction values',()=>{
 const partial=structuredClone(incomingOutput);partial.principal_amount_raw='250';
 assert.equal(validateNativeAutoExtraction(source(incoming),account,partial).facts.amount_minor,null);
 const madeUp=structuredClone(incomingOutput);madeUp.payer_name_raw='Nobody';
 assert.deepEqual(validateNativeAutoExtraction(source(incoming),account,madeUp),{kind:'invalid_output'});
 const badReference=structuredClone(incomingOutput);badReference.evidence.transaction_id='ABC123';
 assert.equal(validateNativeAutoExtraction(source(incoming),account,badReference).facts.provider_transaction_id,null);
 const partialReference=structuredClone(incomingOutput);partialReference.transaction_id_raw='ABC';
 assert.equal(validateNativeAutoExtraction(source(incoming),account,partialReference).facts.provider_transaction_id,null);
 const ambiguousAmount=structuredClone(incomingOutput);ambiguousAmount.evidence.principal='You have received 1,250 RWF from Example Person. Reference: ABC123. Fee 10 RWF';
 assert.equal(validateNativeAutoExtraction(source(incoming),account,ambiguousAmount).facts.amount_minor,null);
 const unsupportedDirection=structuredClone(incomingOutput);unsupportedDirection.event_kind='outgoing';
 const got=validateNativeAutoExtraction(source(incoming),account,unsupportedDirection);
 assert.equal(got.direction,'other');assert.equal(got.facts.event_kind,'unknown');assert.equal(got.facts.amount_minor,null);
});
test('provider timestamps use only the configured profile and verified source text',()=>{
 const body='You have received 250 RWF at 2026-11-11 12:30:00. Reference: XYZ77.';
 const output=extraction({event_kind:'incoming_receipt',payment_outcome:'successful',transaction_id_raw:'XYZ77',principal_amount_raw:'250',
  currency_raw:'RWF',transaction_datetime_raw:'2026-11-11 12:30:00',evidence:{incoming_success:'You have received',
   principal:'You have received 250 RWF',transaction_id:'Reference: XYZ77',transaction_datetime:'2026-11-11 12:30:00',
   payer:null,fee:null,wallet_balance_after:null}});
 const result=validateNativeAutoExtraction(source(body),account,output);
 assert.equal(result.facts.transaction_at,'2026-11-11T10:30:00.000Z');
 const shifted={...account,profile_json:JSON.stringify({...JSON.parse(account.profile_json),utc_offset_minutes:0})};
 assert.equal(validateNativeAutoExtraction(source(body),shifted,output).facts.transaction_at,null);
});
test('provider notices retain unknown financial fields rather than fabricated defaults',()=>{
 const result=validateNativeAutoExtraction(source('Your service is available.'),account,extraction({event_kind:'other'}));
 assert.equal(result.kind,'parsed');assert.equal(result.facts.event_kind,'other');assert.equal(result.facts.amount_minor,null);
 assert.equal(result.facts.provider_transaction_id,null);assert.equal(result.facts.currency,null);
});
test('non-financial notices discard unsupported model claims and do not retry forever',()=>{
 const body='Your service is available until tomorrow.';
 const output=extraction({event_kind:'other',issues:['No transaction in this notice'],
  payer_name_raw:'Invented name',evidence:{incoming_success:'A paraphrase',principal:null,transaction_id:null,
   transaction_datetime:null,payer:'Invented name',fee:null,wallet_balance_after:null}});
 const result=validateNativeAutoExtraction(source(body),account,output);
 assert.equal(result.kind,'parsed');assert.equal(result.facts.event_kind,'other');
 assert.equal(result.facts.amount_minor,null);assert.equal(result.facts.counterparty_name,null);
 assert.deepEqual(result.normalizedOutput.issues,[]);assert.equal(result.normalizedOutput.evidence.incoming_success,null);
 assert.equal(result.normalizedOutput.payer_name_raw,null);
 const unsupportedEvidence=extraction({event_kind:'other',issues:['No transaction'],payer_name_raw:'service',
  evidence:{incoming_success:null,principal:null,transaction_id:null,transaction_datetime:null,payer:'paraphrase',fee:null,wallet_balance_after:null}});
 assert.equal(validateNativeAutoExtraction(source(body),account,unsupportedEvidence).facts.counterparty_name,null);
 const unsupportedSuccess=extraction({event_kind:'other',payment_outcome:'successful',issues:['No transaction']});
 assert.equal(validateNativeAutoExtraction(source(body),account,unsupportedSuccess).facts.payment_outcome,'unknown');
});
test('notice fallback never hides a financial cue or a returned financial field',()=>{
 const base=extraction({event_kind:'other',issues:['Incomplete']});
 for(const body of ['You have received a payment.','A payment of 250 RWF is available.'])
  assert.deepEqual(validateNativeAutoExtraction(source(body),account,base),{kind:'invalid_output'});
 const withAmount=extraction({event_kind:'other',issues:['Incomplete'],principal_amount_raw:'250'});
 assert.deepEqual(validateNativeAutoExtraction(source('Notice 250'),account,withAmount),{kind:'invalid_output'});
});
test('one-time codes and credentials are never sent to the external parser',()=>{
 for(const text of ['Your OTP is 123456.','Your verification code is 123456.','Use PIN 1234 to continue.',
  'Your password is 1234.','Your code 123456. Never share your PIN.']){
  assert.deepEqual(prepareNativeAutoExtraction(source(text),account),{kind:'security_message'});
  assert.deepEqual(validateNativeAutoExtraction(source(text),account,incomingOutput),{kind:'security_message'});
 }
});
test('a number-free PIN warning is omitted from a financial-message prompt',()=>{
 const text=incoming+' Never share your PIN.';
 const plan=prepareNativeAutoExtraction(source(text),account);
 assert.equal(plan.kind,'provider');assert.equal(JSON.stringify(plan.request).includes('PIN'),false);
 assert.equal(validateNativeAutoExtraction(source(text),account,incomingOutput).facts.amount_minor,1250);
});
test('sender and configured provider profile remain required',()=>{
 assert.deepEqual(prepareNativeAutoExtraction({...source(incoming),raw_sender:'Other Sender'},account),{kind:'invalid_source'});
 assert.deepEqual(prepareNativeAutoExtraction(source(incoming),{...account,profile_status:'unverified'}),{kind:'invalid_source'});
});

test('a contradictory outcome for this incoming transfer cannot become a credit',()=>{
 for(const tail of ['This transfer failed.','This transfer is pending.','This transfer has been reversed.',
  'This transfer failed for a different reason.','This payment was declined.','This transfer was canceled.','This transfer was unsuccessful.']){
  const got=validateNativeAutoExtraction(source(incoming+' '+tail),account,incomingOutput);
  assert.equal(got.facts.event_kind,'unknown',tail);assert.equal(got.facts.amount_minor,null,tail);
 }
 const pending=incoming.replace('from Example Person.','from Example Person, pending.');
 assert.equal(validateNativeAutoExtraction(source(pending),account,incomingOutput).facts.amount_minor,null);
 assert.equal(validateNativeAutoExtraction(source('Pending. '+incoming),account,incomingOutput).facts.amount_minor,null);
});
test('unrelated earlier failures, negated failure and conditional advice do not revoke a real receipt',()=>{
 for(const tail of ['A different, earlier transfer failed.','Your previous transfer failed.',
  'If this transfer failed, contact support.','This transfer has not failed.','This transaction is no longer pending.',
  'A different, earlier transfer was unsuccessful.']){
  const got=validateNativeAutoExtraction(source(incoming+' '+tail),account,incomingOutput);
  assert.equal(got.facts.event_kind,'incoming_receipt',tail);assert.equal(got.facts.amount_minor,1250,tail);
 }
});
test('configured negative outcome markers apply to this event without rejecting unrelated history',()=>{
 const configured={...account,profile_json:JSON.stringify({...JSON.parse(account.profile_json),
  failure_markers:['could not be completed'],reversal_markers:['has been undone']})};
 for(const tail of ['This transfer could not be completed.','This transfer has been undone.'])
  assert.equal(validateNativeAutoExtraction(source(incoming+' '+tail),configured,incomingOutput).facts.amount_minor,null,tail);
 for(const tail of ['A different, earlier transfer could not be completed.','If this transfer could not be completed, contact support.'])
  assert.equal(validateNativeAutoExtraction(source(incoming+' '+tail),configured,incomingOutput).facts.amount_minor,1250,tail);
});
test('a completed outgoing is not rejected by an unrelated failure or conditional notice',()=>{
 const main='Your payment of 250 RWF to Example Shop has been completed.';
 const value=extraction({event_kind:'outgoing',payment_outcome:'successful',principal_amount_raw:'250 RWF',currency_raw:'RWF',
  evidence:{incoming_success:main,principal:main,transaction_id:null,transaction_datetime:null,payer:null,fee:null,wallet_balance_after:null}});
 for(const tail of ['A different transaction failed earlier.','If another payment is pending, contact support.'])
  assert.equal(validateNativeAutoExtraction(source(main+' '+tail),account,value).facts.amount_minor,250);
});
test('wallet balance alone cannot supply a missing principal',()=>{
 const body='You have received a transfer from Example Person. Balance 9,000 RWF.';
 const value={...incomingOutput,transaction_id_raw:null,principal_amount_raw:'9,000',fee_amount_raw:null,
  evidence:{...incomingOutput.evidence,transaction_id:null,principal:body,fee:null}};
 assert.equal(validateNativeAutoExtraction(source(body),account,value).facts.amount_minor,null);
 const conditional='If you have received 1,250 RWF, contact support. Balance 9,000 RWF.';
 const hypothetical={...value,principal_amount_raw:'1,250',evidence:{...value.evidence,incoming_success:'you have received',principal:'If you have received 1,250 RWF',payer:null},payer_name_raw:null};
 assert.equal(validateNativeAutoExtraction(source(conditional),account,hypothetical).facts.amount_minor,null);
});
test('fee and balance values remain bound to their source roles across a combined quote',()=>{
 const both='Fee 10 RWF. Balance 9,000 RWF';
 const fee={...incomingOutput,fee_amount_raw:'9,000',evidence:{...incomingOutput.evidence,fee:both}};
 const balance={...incomingOutput,wallet_balance_after_raw:'10',evidence:{...incomingOutput.evidence,wallet_balance_after:both}};
 assert.equal(validateNativeAutoExtraction(source(incoming),account,fee).facts.fee_minor,null);
 assert.equal(validateNativeAutoExtraction(source(incoming),account,balance).facts.wallet_balance_after_minor,null);
 const sameClause=incoming.replace('Fee 10 RWF. Balance','Fee 10 RWF, Balance');
 const cross='Fee 10 RWF, Balance 9,000 RWF';
 assert.equal(validateNativeAutoExtraction(source(sameClause),account,{...balance,evidence:{...balance.evidence,wallet_balance_after:cross}}).facts.wallet_balance_after_minor,null);
 assert.equal(validateNativeAutoExtraction(source(sameClause),account,{...incomingOutput,evidence:{...incomingOutput.evidence,fee:cross,wallet_balance_after:cross}}).facts.wallet_balance_after_minor,9000);
 const descriptive=incoming.replace('Fee 10 RWF','Fee for this transfer is 10 RWF').replace('Balance 9,000 RWF','Balance after this transaction is 9,000 RWF');
 const descriptions={...incomingOutput,evidence:{...incomingOutput.evidence,fee:'Fee for this transfer is 10 RWF',wallet_balance_after:'Balance after this transaction is 9,000 RWF'}};
 assert.equal(validateNativeAutoExtraction(source(descriptive),account,descriptions).facts.fee_minor,10);
 assert.equal(validateNativeAutoExtraction(source(descriptive),account,descriptions).facts.wallet_balance_after_minor,9000);
});
test('explicit ISO offsets identify instants independently of the receiving-account timezone',()=>{
 const iso={...account,profile_json:JSON.stringify({...JSON.parse(account.profile_json),date_format:'ISO'})};
 for(const [raw,expected] of [['2026-11-13T10:00:00Z','2026-11-13T10:00:00.000Z'],
  ['2026-11-13T12:00:00+02:00','2026-11-13T10:00:00.000Z'],
  ['2026-11-13T10:00:00.1Z','2026-11-13T10:00:00.100Z'],
  ['2026-02-30T10:00:00Z',null],['2026-11-13T10:00:00+24:00',null]]){
  const body=incoming+' At '+raw+'.';
  const value={...incomingOutput,transaction_datetime_raw:raw,evidence:{...incomingOutput.evidence,transaction_datetime:'At '+raw}};
  assert.equal(validateNativeAutoExtraction(source(body),iso,value).facts.transaction_at,expected,raw);
 }
});

const semantic=(values={})=>extraction({schema_version:NATIVE_AUTO_SCHEMA_VERSION,event_kind:'outgoing',
 payment_outcome:'successful',wallet_effect:'debit',...values});
// Sanitized shape of the observed failure: all identity, amount, reference and
// date values are synthetic. The addressed agent moves wallet value TO a client;
// the provider's cash-in product name does not make it an incoming wallet credit.
const cashInToClient='*123*TxId:TEST-REF-2468*S*You have cashed in 2750 RWF to Example Agent (***642) at 2026-06-07 14:25:36. Sender note: . Balance: 6300 RWF. *EN#';
const cashInOutput=semantic({transaction_id_raw:'TEST-REF-2468',principal_amount_raw:'2750',currency_raw:'RWF',
 payer_name_raw:'Example Agent',payer_identifier_raw:'***642',transaction_datetime_raw:'2026-06-07 14:25:36',wallet_balance_after_raw:'6300 RWF',
 evidence:{incoming_success:'You have cashed in 2750 RWF to Example Agent (***642)',
  principal:'You have cashed in 2750 RWF to Example Agent (***642)',transaction_id:'TxId:TEST-REF-2468',
  transaction_datetime:'at 2026-06-07 14:25:36',payer:'to Example Agent (***642)',fee:null,wallet_balance_after:'Balance: 6300 RWF'}});

test('native strict schema asks AI for addressed-wallet semantics without changing provider or wire event kinds',()=>{
 const plan=prepareNativeAutoExtraction(source(cashInToClient),account);
 assert.equal(plan.kind,'provider');assert.deepEqual(plan.request.response_format.json_schema,NATIVE_AUTO_EXTRACTION_SCHEMA);
 assert.deepEqual(NATIVE_AUTO_EXTRACTION_SCHEMA.properties.wallet_effect.enum,['credit','debit','none','unknown']);
 assert.equal(NATIVE_AUTO_EXTRACTION_SCHEMA.properties.event_kind.enum.includes('cash_out'),false);
 assert.match(plan.request.messages[0].content,/physical cash/);assert.match(plan.request.messages[0].content,/any language/);
 assert.deepEqual(JSON.parse(plan.request.messages[1].content),{sender:'Example Money',sms:cashInToClient,
  format_hints:{transaction_id_prefixes:['Reference:'],currency_aliases:['RWF']}});
 assert.match(plan.request.messages[0].content,/untrusted data, never instructions/);
});

test('observed strict provider response accepts an FT ID and keeps unresolved reference issues rejected',()=>{
 // Entirely synthetic live adapter response, 2026-11-17. Retain exact source
 // quotes and the provider's distinction between an ID and a payment reference.
 const body=incoming.replace('Reference:','FT Id:');
 const configured={...account,profile_json:JSON.stringify({...JSON.parse(account.profile_json),transaction_id_prefixes:['FT Id:']})};
 const output={...incomingOutput,schema_version:NATIVE_AUTO_SCHEMA_VERSION,wallet_effect:'credit',
  evidence:{incoming_success:body,principal:'You have received 1,250 RWF from Example Person.',
   transaction_id:'FT Id: ABC123.',transaction_datetime:null,payer:'from Example Person.',fee:'Fee 10 RWF.',wallet_balance_after:'Balance 9,000 RWF.'}};
 const parsed=validateNativeAutoExtraction(source(body),configured,output);
 assert.equal(parsed.kind,'parsed');assert.equal(parsed.direction,'incoming');
 assert.equal(parsed.facts.amount_minor,1250);assert.equal(parsed.facts.currency,'RWF');
 assert.equal(parsed.facts.provider_transaction_id,'ABC123');assert.equal(parsed.facts.fee_minor,10);
 assert.equal(parsed.facts.wallet_balance_after_minor,9000);
 const unresolved={...output,transaction_id_raw:null,payment_reference_raw:'ABC123',
  evidence:{...output.evidence,incoming_success:incoming,transaction_id:null,payer:'from Example Person'},
  issues:['No provider-issued transaction identifier is present in the SMS.']};
 assert.deepEqual(validateNativeAutoExtraction(source(incoming),account,unresolved),{kind:'invalid_output'});
});

test('source-backed semantic cash-in to a client is outgoing with complete amount and an unfamiliar ID label',()=>{
 const result=validateNativeAutoExtraction(source(cashInToClient),account,cashInOutput);
 assert.equal(result.kind,'parsed');assert.equal(result.direction,'outgoing');
 assert.equal(result.facts.event_kind,'outgoing');assert.equal(result.facts.payment_outcome,'successful');
 assert.equal(result.facts.amount_minor,2750);assert.equal(result.facts.currency,'RWF');
 assert.equal(result.facts.provider_transaction_id,'TEST-REF-2468');assert.equal(result.facts.wallet_balance_after_minor,6300);
 assert.equal(result.facts.transaction_at,'2026-06-07T12:25:36.000Z');
});

test('the saved legacy cash-in misclassification cannot become an incoming credit under the new parser',()=>{
 const legacy={...cashInOutput,schema_version:MOMO_SCHEMA_VERSION,event_kind:'incoming_receipt'};delete legacy.wallet_effect;
 const result=validateNativeAutoExtraction(source(cashInToClient),account,legacy);
 assert.equal(result.facts.event_kind,'unknown');assert.equal(result.facts.amount_minor,null);assert.equal(result.facts.currency,null);
 assert.deepEqual(validateNativeAutoExtraction(source(cashInToClient),account,{...cashInOutput,event_kind:'incoming_receipt'}),{kind:'invalid_output'});
});

test('semantic outgoing and incoming facts accept source-language context and literal currency case',()=>{
 for(const [body,output,amount,direction]of[
  ['Opération réf. FR-713. Vous avez remis 2,750 Rwf au client Exemple. Frais 25 Rwf. Solde restant 6,300 Rwf.',
   semantic({transaction_id_raw:'FR-713',principal_amount_raw:'2,750',currency_raw:'Rwf',fee_amount_raw:'25',wallet_balance_after_raw:'6,300',
    evidence:{incoming_success:'Vous avez remis 2,750 Rwf au client Exemple',principal:'Vous avez remis 2,750 Rwf au client Exemple',
     transaction_id:'Opération réf. FR-713',transaction_datetime:null,payer:null,fee:'Frais 25 Rwf',wallet_balance_after:'Solde restant 6,300 Rwf'}}),2750,'outgoing'],
  ['Nambari SW-824. Umetoa 450 FRW kwa wakala Mfano. Ada 5 FRW. Salio 800 FRW.',
   semantic({transaction_id_raw:'SW-824',principal_amount_raw:'450',currency_raw:'FRW',fee_amount_raw:'5',wallet_balance_after_raw:'800',
    evidence:{incoming_success:'Umetoa 450 FRW kwa wakala Mfano',principal:'Umetoa 450 FRW kwa wakala Mfano',
     transaction_id:'Nambari SW-824',transaction_datetime:null,payer:null,fee:'Ada 5 FRW',wallet_balance_after:'Salio 800 FRW'}}),450,'outgoing'],
  ['Réf. IN-935. Votre portefeuille est crédité de 3,100 Rwf par Exemple. Solde restant 7,200 Rwf.',
   semantic({event_kind:'incoming_receipt',wallet_effect:'credit',transaction_id_raw:'IN-935',principal_amount_raw:'3,100',currency_raw:'Rwf',wallet_balance_after_raw:'7,200',
    evidence:{incoming_success:'Votre portefeuille est crédité de 3,100 Rwf par Exemple',principal:'Votre portefeuille est crédité de 3,100 Rwf par Exemple',
     transaction_id:'Réf. IN-935',transaction_datetime:null,payer:null,fee:null,wallet_balance_after:'Solde restant 7,200 Rwf'}}),3100,'incoming'],
 ]){
  const localized={...account,profile_json:JSON.stringify({...JSON.parse(account.profile_json),currency_aliases:['RWF','FRW']})};
  const result=validateNativeAutoExtraction(source(body),localized,output);
  assert.equal(result.kind,'parsed');assert.equal(result.direction,direction);assert.equal(result.facts.amount_minor,amount);
  assert.equal(result.facts.provider_transaction_id,output.transaction_id_raw);assert.equal(result.facts.currency,'RWF');
  assert.equal(typeof result.facts.wallet_balance_after_minor,'number');
 }
});

test('semantic source-role validation refuses balance/fee substitution, truncated values and missing direction proof',()=>{
 const cases=[
  {...cashInOutput,principal_amount_raw:'6300 RWF',evidence:{...cashInOutput.evidence,principal:'Balance: 6300 RWF'}},
  {...cashInOutput,principal_amount_raw:'750'},
  {...cashInOutput,transaction_id_raw:'TEST-REF-246'},
  {...cashInOutput,evidence:{...cashInOutput.evidence,transaction_id:'TEST-REF-2468'}},
  {...cashInOutput,evidence:{...cashInOutput.evidence,incoming_success:null}},
  {...cashInOutput,wallet_effect:'credit'},
  {...cashInOutput,wallet_effect:'unknown'},
  {...cashInOutput,transaction_id_raw:'***642',evidence:{...cashInOutput.evidence,transaction_id:'to Example Agent (***642)'}},
 ];
 for(const output of cases)assert.deepEqual(validateNativeAutoExtraction(source(cashInToClient),account,output),{kind:'invalid_output'});
 const invented={...cashInOutput,transaction_id_raw:'NOT-IN-SOURCE'};
 assert.deepEqual(validateNativeAutoExtraction(source(cashInToClient),account,invented),{kind:'invalid_output'});
 const overlapping={...cashInOutput,fee_amount_raw:'2750',evidence:{...cashInOutput.evidence,fee:cashInOutput.evidence.principal}};
 assert.deepEqual(validateNativeAutoExtraction(source(cashInToClient),account,overlapping),{kind:'invalid_output'});
});

test('new semantic replies with ambiguous financial fields take the existing automatic retry result',()=>{
 for(const output of[
  {...cashInOutput,principal_amount_raw:null},
  {...cashInOutput,currency_raw:null},
  {...cashInOutput,event_kind:'unknown',wallet_effect:'unknown',payment_outcome:'unknown'},
  {...cashInOutput,payment_outcome:'pending'},
 ])assert.deepEqual(validateNativeAutoExtraction(source(cashInToClient),account,output),{kind:'invalid_output'});
});

test('semantic amounts cannot discard a source sign, accounting bracket or whitespace grouping',()=>{
 for(const [amount,raw]of[['-2750 RWF','2750'],['RWF −2750','2750'],['-RWF 2750','RWF 2750'],
  ['(2750 RWF)','2750'],['1 275 RWF','275'],['RWF 2\u202f750','2']]){
  const quote=`Votre débit est ${amount}`,body=quote+'.';
  const output=semantic({principal_amount_raw:raw,currency_raw:'RWF',
   evidence:{incoming_success:quote,principal:quote,transaction_id:null,transaction_datetime:null,payer:null,fee:null,wallet_balance_after:null}});
  assert.deepEqual(validateNativeAutoExtraction(source(body),account,output),{kind:'invalid_output'},amount);
 }
});

test('semantic transaction identifiers retain the entire token rather than a numeric or delimited suffix',()=>{
 for(const full of['TEST-REF-2468','TEST/REF/2468','TEST.REF.2468','TEST_REF_2468','ABC2468','2468XYZ','98765432017']){
  const label=`TxId:${full}`,body=`${label}. You have cashed in 2750 RWF to Example Agent. Balance: 6300 RWF.`;
  const base={...cashInOutput,transaction_id_raw:full,payer_name_raw:'Example Agent',payer_identifier_raw:null,transaction_datetime_raw:null,
   evidence:{...cashInOutput.evidence,incoming_success:'You have cashed in 2750 RWF to Example Agent',
    principal:'You have cashed in 2750 RWF to Example Agent',transaction_id:label,transaction_datetime:null,payer:'to Example Agent'}};
  assert.equal(validateNativeAutoExtraction(source(body),account,base).facts.provider_transaction_id,full);
  const fragments=[...new Set([full.slice(1),full.slice(0,-1),'2468','REF-2468','REF/2468','REF.2468','REF_2468'])].filter(value=>value!==full&&full.includes(value));
  for(const fragment of fragments){
   assert.deepEqual(validateNativeAutoExtraction(source(body),account,{...base,transaction_id_raw:fragment}),{kind:'invalid_output'},`${full} -> ${fragment}`);
   // Shortening the evidence itself must not hide the rest of the source ID.
   assert.deepEqual(validateNativeAutoExtraction(source(body),account,{...base,transaction_id_raw:fragment,
    evidence:{...base.evidence,transaction_id:label.slice(0,label.indexOf(full))+fragment}}),{kind:'invalid_output'},`${full} -> shortened ${fragment}`);
  }
 }
});

test('failed and pending semantic notices preserve genuine null amount and currency fields',()=>{
 for(const [kind,quote]of[['failed','Votre opération a échoué'],['pending','Votre opération est en attente']]){
  const body=quote+'.',output=semantic({event_kind:kind,payment_outcome:kind,wallet_effect:'none',
   evidence:{incoming_success:quote,principal:null,transaction_id:null,transaction_datetime:null,payer:null,fee:null,wallet_balance_after:null}});
  const result=validateNativeAutoExtraction(source(body),account,output);
  assert.equal(result.kind,'parsed');assert.equal(result.facts.event_kind,kind);assert.equal(result.facts.payment_outcome,kind);
  assert.equal(result.facts.amount_minor,null);assert.equal(result.facts.currency,null);
  const currencyQuote=quote+' (Rwf)';
  const withCurrency=validateNativeAutoExtraction(source(currencyQuote+'.'),account,{...output,currency_raw:'Rwf',
   evidence:{...output.evidence,incoming_success:currencyQuote}});
  assert.equal(withCurrency.kind,'parsed');assert.equal(withCurrency.facts.amount_minor,null);assert.equal(withCurrency.facts.currency,'RWF');
 }
});

test('failed or pending semantic notices still reject nonnull truncated or invented financial fields',()=>{
 for(const kind of['failed','pending']){
  const quote='Opération de 2750 RWF',outcome=`État ${kind}`,body=quote+'. '+outcome+'.';
  const output=semantic({event_kind:kind,payment_outcome:kind,wallet_effect:'none',principal_amount_raw:'2750',currency_raw:'RWF',
   evidence:{incoming_success:outcome,principal:quote,transaction_id:null,transaction_datetime:null,payer:null,fee:null,wallet_balance_after:null}});
  assert.equal(validateNativeAutoExtraction(source(body),account,output).facts.amount_minor,2750);
  for(const invalid of[{...output,principal_amount_raw:'750'},{...output,principal_amount_raw:'999'},
   {...output,currency_raw:'USD'},{...output,transaction_id_raw:'MADE-UP'}])
   assert.deepEqual(validateNativeAutoExtraction(source(body),account,invalid),{kind:'invalid_output'});
 }
 for(const [kind,effect]of[['incoming_receipt','credit'],['outgoing','debit'],['reversal','credit']]){
  const quote='Opération confirmée',output=semantic({event_kind:kind,wallet_effect:effect,
   evidence:{incoming_success:quote,principal:null,transaction_id:null,transaction_datetime:null,payer:null,fee:null,wallet_balance_after:null}});
  assert.deepEqual(validateNativeAutoExtraction(source(quote+'.'),account,output),{kind:'invalid_output'});
 }
});

test('semantic principal currency binds to its full monetary token with or without intervening space',()=>{
 const configured={...account,profile_json:JSON.stringify({...JSON.parse(account.profile_json),currency_aliases:['RWF','FRW']})};
 for(const [currency,monetary]of[['RWF','RWF2750'],['RWF','2750RWF'],['FRW','FRW2750'],['FRW','2750FRW'],
  ['Rwf','Rwf2750'],['Rwf','2750Rwf']]){
  for(const [kind,effect]of[['outgoing','debit'],['incoming_receipt','credit']]){
   const quote=`Opération confirmée de ${monetary}`,body=quote+'.';
   const output=semantic({event_kind:kind,wallet_effect:effect,principal_amount_raw:'2750',currency_raw:currency,
    evidence:{incoming_success:quote,principal:quote,transaction_id:null,transaction_datetime:null,payer:null,fee:null,wallet_balance_after:null}});
   const result=validateNativeAutoExtraction(source(body),configured,output);
   assert.equal(result.kind,'parsed',monetary);assert.equal(result.facts.amount_minor,2750);assert.equal(result.facts.currency,'RWF');
  }
 }
});

test('adjacent principal currency never accepts partial aliases or aliases embedded in unrelated words',()=>{
 for(const [monetary,currency]of[['RWF2750','RW'],['2750RWF','RW'],['RWF2750','FRW'],
  ['XRWF2750','RWF'],['2750RWFx','RWF'],['RWF2750x','RWF'],['X2750RWF','RWF']]){
  const quote=`Opération confirmée de ${monetary}`,body=quote+'.';
  const output=semantic({principal_amount_raw:'2750',currency_raw:currency,
   evidence:{incoming_success:quote,principal:quote,transaction_id:null,transaction_datetime:null,payer:null,fee:null,wallet_balance_after:null}});
  assert.deepEqual(validateNativeAutoExtraction(source(body),account,output),{kind:'invalid_output'},`${monetary} / ${currency}`);
 }
});
