import test from 'node:test';import assert from 'node:assert/strict';
import {normalizePhone,requirePin,wholeRwf,providerTime,canonicalJson} from '../../domain/burimunsi/values.js';
import {parseReceipt,classifyCapture,receiptFingerprint,transactionKey} from '../../domain/burimunsi/receipt.js';
import {profile,body,source,fullSource,binding} from './fixtures.mjs';
for(const p of ['0780000816','780000816','250780000816','+250780000816','00250780000816','+250 780 000 816','(0780) 000-816'])test('normalize phone '+p,()=>assert.equal(normalizePhone(p),'+250780000816'));
for(const p of ['staff@example.com','abc0780000816','+250780000816x','+250+780000816','078000081','07800008166','+254780000816','+250710000816',780000816,'*********816'])test('reject non-phone '+String(p),()=>assert.throws(()=>normalizePhone(p),/invalid_phone/));
test('every four-digit PIN including leading zeroes is preserved',()=>{for(let i=0;i<10000;i++){const p=String(i).padStart(4,'0');assert.equal(requirePin(p),p);}});
for(const p of ['123','12345',' 1234','12a4','١٢٣٤',1234,null])test('PIN rejection '+String(p),()=>assert.throws(()=>requirePin(p),/invalid_passcode/));
for(const p of ['0','-1','+1','1.0','1e3','01','1,00','9007199254740992'])test('reject amount '+p,()=>assert.throws(()=>wholeRwf(p),/invalid_amount/));
test('whole RWF boundaries and grouping',()=>{assert.equal(wholeRwf('9,007,199,254,740,991'),Number.MAX_SAFE_INTEGER);assert.equal(wholeRwf('0',{positive:false}),0);assert.equal(wholeRwf('10,000'),10000);});
test('source calendar and timezone conversion',()=>{assert.equal(providerTime('2026-10-08 15:15:20',120),'2026-10-08T13:15:20.000Z');assert.equal(providerTime('2024-02-29 00:00:00',120),'2024-02-28T22:00:00.000Z');});
for(const s of ['2026-02-29 00:00:00','2026-04-31 00:00:00','2026-10-08 24:00:00','2026-10-08 15:61:00','2026-10-08T15:15:20Z'])test('reject timestamp '+s,()=>assert.throws(()=>providerTime(s,120)));
test('masked source retains exact evidence and does not invent fee or identity',()=>{const r=parseReceipt(source,profile);assert.equal(r.amountRwf,10000);assert.equal(r.walletBalanceRwf,10450);assert.equal(r.feeRwf,null);assert.equal(r.fullPayerPhone,null);assert.equal(r.payerNameRaw,'EXAMPLE PERSON');assert.equal(r.payerPhoneRaw,'*********816');assert.equal(r.atRaw,'2026-10-08 15:15:20');assert.equal(r.ftId,'90000000001');assert.equal(r.rawBody,body);});
test('full phone normalized separately from original evidence',()=>{const r=parseReceipt(fullSource,profile);assert.equal(r.fullPayerPhone,'+250780000816');assert.equal(r.payerPhoneRaw,'+250780000816');});
for(const [name,change] of [
 ['wrong sender',s=>({...s,sender:'Promo'})],['multipart incomplete',s=>({...s,complete:false})],
 ['outgoing',s=>({...s,body:s.body.replace('received','sent')})],['non-RWF',s=>({...s,body:s.body.replaceAll('RWF','USD')})],
 ['zero',s=>({...s,body:s.body.replace('received 10000','received 0')})],['decimal',s=>({...s,body:s.body.replace('received 10000','received 100.50')})],
 ['negative',s=>({...s,body:s.body.replace('received 10000','received -1')})],['extra reference',s=>({...s,body:s.body+' FT Id: 999.'})],
 ['extra OTP',s=>({...s,body:s.body+' OTP 1234'})],['newline',s=>({...s,body:s.body+'\n'})],['bidi',s=>({...s,body:s.body.replace('PERSON','PERSON\u202e')})],
 ['invalid date',s=>({...s,body:s.body.replace('2026-10-08','2026-02-30')})],['missing balance',s=>({...s,body:s.body.replace('Balance: 10450 RWF. ','')})],
 ['future unsupported fee variant',s=>({...s,body:s.body.replace('Balance:','Fee: 0 RWF. Balance:')})]
])test('receipt fails closed: '+name,()=>assert.throws(()=>parseReceipt(change(source),profile)));
test('profile mandatory; no invented default timezone',()=>assert.throws(()=>parseReceipt(source,{senders:['M-Money'],version:'v'}),/profile/));
const intakeProfile={...profile,incomingPrefixes:['You have received'],currencyAliases:['RWF'],transactionIdPrefixes:['FT Id:']};
test('privacy filter rejects OTP without returning message contents',()=>{const r=classifyCapture({...source,body:'Your OTP is 9999'},intakeProfile,binding);assert.equal(r.retain,false);assert(!JSON.stringify(r).includes('9999'));});
test('privacy filter requires exact SIM route and approved financial markers',()=>{assert.equal(classifyCapture(source,intakeProfile,binding).retain,true);for(const sub of [null,undefined,-1,5])assert.equal(classifyCapture({...source,subscriptionId:sub},intakeProfile,binding).retain,false);});
test('different approved message formats enter extraction without becoming ledger evidence',()=>{
 const other={...intakeProfile,senders:['ALT-SENDER'],incomingPrefixes:['Payment received'],transactionIdPrefixes:['Reference:']};
 const candidate={...source,sender:'ALT-SENDER',body:'Payment received: RWF 1500 from EXAMPLE. Reference: 123456.'};
 assert.equal(classifyCapture(candidate,other,binding).retain,true);
 assert.throws(()=>parseReceipt(candidate,other));
 assert.equal(classifyCapture({...candidate,body:candidate.body+' OTP 1234'},other,binding).retain,false);
 assert.equal(classifyCapture({...candidate,sender:'unapproved'},other,binding).retain,false);
});
test('approved sender folding does not equate dotted-I and ordinary i',()=>{
 const allowed={...intakeProfile,senders:['i']};
 assert.equal(classifyCapture({...source,sender:'I'},allowed,binding).retain,true);
 assert.equal(classifyCapture({...source,sender:'İ'},allowed,binding).retain,false);
});
test('canonical event key includes wallet and event kind',()=>{const r=parseReceipt(source,profile);assert.notEqual(transactionKey('a',r),transactionKey('b',r));assert.notEqual(transactionKey('a',r),transactionKey('a',{...r,eventKind:'reversal'}));});
test('fingerprint flags differing payer and amount under same reference',async()=>{const r=parseReceipt(source,profile);assert.notEqual(await receiptFingerprint(r),await receiptFingerprint({...r,amountRwf:10001}));assert.notEqual(await receiptFingerprint(r),await receiptFingerprint({...r,payerNameRaw:'OTHER'}));});
test('stable JSON independent of object insertion order',()=>assert.equal(canonicalJson({b:2,a:1}),canonicalJson({a:1,b:2})));
