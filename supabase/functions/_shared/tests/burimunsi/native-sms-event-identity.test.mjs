import test from 'node:test';
import assert from 'node:assert/strict';
import {nativeSmsEventIdentity,nativeSmsEventAliases} from '../../domain/burimunsi/native-sms-event-identity.js';
import {sha256} from '../../domain/burimunsi/values.js';

const body='You have received 1,250 RWF from Example Person *********456. Balance 9,000 RWF.';
const source={provenance:'native_observation_unverified',raw_body:body,raw_sender:'Example Money',source_mode:'catch_up',
 inbox_received_at:'2026-01-01T10:00:05Z',service_centre_at:'2026-01-01T10:00:00Z',captured_at:'2026-02-01T10:00:00Z'};
const key=async v=>nativeSmsEventIdentity(v,await sha256(v.raw_body));

test('one original SMS retains identity across transport, request, device and inbox-row changes',async()=>{
 const first=await key(source);
 assert.equal(await key({...source,request_id:'different',source_key:'new-key',installation_id:'other',inbox_row_id:99,
  raw_sender:'example money',source_mode:'live',captured_at:'2027-01-01T00:00:00Z',inbox_received_at:'2026-01-01T10:01:00Z'}),first);
 assert.equal(await key({...source,service_centre_at:'2026-01-01T10:00:00.000Z'}),first);
 assert.equal(await key({...source,raw_sender:'OTHER CONFIGURED PROVIDER ALIAS'}),first);
});
test('missing SMSC keeps an inbox alias, while two distinct known SMSC events stay distinct',async()=>{
 const a=await nativeSmsEventAliases(source,await sha256(body));
 const b=await nativeSmsEventAliases({...source,service_centre_at:null},await sha256(body));
 assert.notEqual(a.identity,b.identity);assert.equal(a.inboxIdentity,b.inboxIdentity);
 assert.equal(a.serviceTimePresent,true);assert.equal(b.serviceTimePresent,false);
 const c=await nativeSmsEventAliases({...source,service_centre_at:'2026-01-01T11:00:00Z'},await sha256(body));
 assert.notEqual(a.identity,c.identity);assert.equal(c.serviceTimePresent,true);
});
test('identical no-reference bodies in distinct original SMS events remain distinct',async()=>{
 assert.notEqual(await key(source),await key({...source,service_centre_at:'2026-01-01T10:00:01Z'}));
 const inboxOnly={...source,service_centre_at:null};
 assert.notEqual(await key(inboxOnly),await key({...inboxOnly,inbox_received_at:'2026-01-01T11:00:05Z'}));
});
test('inbox-only sources ignore their upload time and body-only ambiguity is conservative',async()=>{
 const inboxOnly={...source,service_centre_at:null};
 assert.equal(await key(inboxOnly),await key({...inboxOnly,captured_at:'2028-01-01T00:00:00Z',source_key:'another'}));
 const noOriginal={...source,service_centre_at:null,inbox_received_at:null};
 assert.equal(await key(noOriginal),await key({...noOriginal,captured_at:'2029-01-01T00:00:00Z'}));
 assert.notEqual(await key(noOriginal),await key({...noOriginal,raw_body:body+' Reference: NEW.'}));
});
test('source custody mismatches, malformed original times and unknown provenance fail closed',async()=>{
 await assert.rejects(nativeSmsEventIdentity(source,'a'.repeat(64)),/native_auto_source_changed/);
 for(const patch of [{service_centre_at:'2026-02-30T10:00:00Z'},{service_centre_at:'2026-01-01'},
  {service_centre_at:123},{provenance:'model_output'}])await assert.rejects(key({...source,...patch}),/native_auto_source_changed/);
});
