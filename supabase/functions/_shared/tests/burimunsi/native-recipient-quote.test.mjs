import {test} from 'node:test';
import assert from 'node:assert/strict';
import {parseNativeRecipientQuote} from '../../domain/burimunsi/unresolved-evidence.js';

const rule={role:'recipient',kind:'public_code',prefix:'Receiver code: ',suffix:'.',digit_count:5,format:'digits'};
const profile={sender_allowlist:['EXAMPLE-MOMO'],currency_aliases:['RWF'],incoming_prefixes:['Received'],
 transaction_id_prefixes:['Reference:'],date_format:'YMD_HMS',utc_offset_minutes:120,recipient_rules:[rule]};
const tuple=patch=>({provider:'mtn_momo',status:'active',profile_status:'approved',profile_version:'fixture.v1',
 profile_json:JSON.stringify({...profile,...patch}),currency:'RWF',timezone:'Africa/Kigali'});
const body='Received RWF 450. Reference: ABC120. Receiver code: 57264.';
const source=patch=>({raw_sender:'EXAMPLE-MOMO',raw_body:body,source_mode:'catch_up',complete:false,
 provenance:'native_observation_unverified',...patch});
const run=(patch,profilePatch)=>parseNativeRecipientQuote({source:source(patch),providerProfile:tuple(profilePatch)});

test('the dynamic recipient quote keeps the catch-up source incomplete',()=>{
 const value=run();assert.equal(value.kind,'native_recipient_quote');assert.equal(value.state,'quoted');
 assert.equal(value.source_mode,'catch_up');assert.equal(value.source_complete,false);
 assert.equal(value.recipient.kind,'public_code');assert.equal(body.slice(value.recipient.identifier.start,value.recipient.identifier.end),'57264');
});
test('a live source remains live and does not become a carrier confirmation',()=>{
 const value=run({source_mode:'live',complete:true});assert.equal(value.state,'quoted');
 assert.equal(value.source_mode,'live');assert.equal(value.source_complete,true);
 assert.equal(Object.hasOwn(value,'provider_confirmation'),false);assert.equal(Object.hasOwn(value,'posting_allowed'),false);
});
test('a dynamic account profile can change the recognized code without app constants',()=>{
 const r={...rule,prefix:'Wallet number: ',digit_count:6};
 const value=run({raw_body:body.replace('Receiver code: 57264.','Wallet number: 813579.')},{recipient_rules:[r]});
 assert.equal(value.state,'quoted');assert.equal(value.recipient.raw,'813579');
});
for(const [name,patch,profilePatch] of [
 ['no configured grammar',{}, {recipient_rules:undefined}],
 ['source sender is different',{raw_sender:'UNTRUSTED'},{}],
 ['duplicate recipient role',{raw_body:body+' Receiver code: 57264.'},{}],
 ['masked recipient',{raw_body:body.replace('57264','****4')},{}],
 ['truncated recipient',{raw_body:body.slice(0,-1)},{}],
 ['extra recipient token',{raw_body:body.replace('57264','572640')},{}],
 ['fake provenance',{provenance:'gateway_capture'},{}],
 ['changed catch-up completeness',{complete:true},{}],
 ['changed live completeness',{source_mode:'live',complete:false},{}],
 ['unapproved dynamic account',{},null],
]) test('recipient quote refuses '+name,()=>{
 const providerProfile=profilePatch===null?{...tuple(),profile_status:'unverified'}:tuple(profilePatch);
 const value=parseNativeRecipientQuote({source:source(patch),providerProfile});assert.equal(value.state,'unavailable');
});
test('accessor-bearing input is rejected without executing the accessor',()=>{
 let read=false;const value={source:source(),providerProfile:tuple()};Object.defineProperty(value,'source',{get(){read=true;throw Error('must not read');},enumerable:true});
 assert.equal(parseNativeRecipientQuote(value).state,'unavailable');assert.equal(read,false);
});
