import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {MOMO_PARSER_VERSION,validateMomoExtraction as validateSupabase} from '../domain/momo_pipeline.js';

// Invented source bytes and provider profile; no live receipt or service.
const fixture=JSON.parse(await readFile(new URL('../../../../deploy/platform-api/test/fixtures/momo-synthetic.json',import.meta.url),'utf8'));
const account={status:'active',profile_status:'approved',profile_version:'synthetic.v1',
 profile_json:JSON.stringify(fixture.profile),currency:'RWF',provider:'mtn_momo',timezone:'Africa/Kigali'};
const source={raw_sender:fixture.sender,raw_body:fixture.body+' Recipient: +250788000099.',completeness:'complete'};

test('every supplied payer field must occur in its evidence snippet',()=>{
  const validate=validateSupabase;
  assert.equal(MOMO_PARSER_VERSION,'momo-validation.v2');
  const complete=structuredClone(fixture.output);
  assert.equal(validate(complete,source,account).accepted,true);
  const nameOnly=structuredClone(complete);nameOnly.payer_identifier_raw=null;
  assert.equal(validate(nameOnly,source,account).accepted,true);
  const numberOnly=structuredClone(complete);numberOnly.payer_name_raw=null;
  assert.equal(validate(numberOnly,source,account).accepted,true);
  const noPayer=structuredClone(complete);noPayer.payer_name_raw=null;noPayer.payer_identifier_raw=null;noPayer.evidence.payer=null;
  assert.equal(validate(noPayer,source,account).accepted,true);
  const receiverAsPayer=structuredClone(complete);receiverAsPayer.payer_identifier_raw='+250788000099';
  const result=validate(receiverAsPayer,source,account);
  assert.equal(result.accepted,false);
  assert(result.errors.some(error=>error.code==='payer_evidence_missing'));
  const recipientAsName=structuredClone(complete);recipientAsName.payer_name_raw='Recipient';recipientAsName.evidence.payer='********007';
  const missingName=validate(recipientAsName,source,account);
  assert.equal(missingName.accepted,false);
  assert(missingName.errors.some(error=>error.code==='payer_evidence_missing'));
  const missingEvidence=structuredClone(complete);missingEvidence.evidence.payer=null;
  assert.equal(validate(missingEvidence,source,account).accepted,false);
  const inventedEvidence=structuredClone(complete);inventedEvidence.evidence.payer='Not in this message';
  assert.equal(validate(inventedEvidence,source,account).accepted,false);
  const oversized=structuredClone(complete);
  oversized.evidence.payer=complete.evidence.payer+'x'.repeat(2049);
  const longerSource={...source,raw_body:source.raw_body+' '+oversized.evidence.payer};
  assert.equal(validate(oversized,longerSource,account).accepted,false);
});
