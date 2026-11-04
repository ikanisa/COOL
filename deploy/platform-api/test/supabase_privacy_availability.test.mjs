import test from 'node:test';
import assert from 'node:assert/strict';
import {privacyPortalRoute} from '../../../supabase/functions/_shared/domain/privacy_portal.js';
import {startOtp} from '../../../supabase/functions/_shared/domain/auth.js';

// Actual route and OTP admission, stopped at an explicitly fake database.
// No external service, provider response, or successful OTP delivery is asserted.
const base = {SUPABASE_URL: 'https://supabase.collect.example',
  SUPABASE_PUBLISHABLE_KEY: 'synthetic-public-key', TURNSTILE_SITE_KEY: 'synthetic_site_key'};
const explicit = {COLLECT_DEPLOYMENT_PROFILE: 'synthetic-profile'};
const cases = [
  ['explicit enabled, no legacy flag', {...explicit, AUTH_WHATSAPP_ENABLED: 'true'}, true, true],
  ['explicit enabled wins over legacy false', {...explicit, AUTH_WHATSAPP_ENABLED: 'true', AUTH_PHONE_ENABLED: 'false'}, true, true],
  ['explicit disabled wins over legacy true', {...explicit, AUTH_WHATSAPP_ENABLED: 'false', AUTH_PHONE_ENABLED: 'true'}, false, false],
  ['explicit profile missing flag refuses legacy true', {...explicit, AUTH_PHONE_ENABLED: 'true'}, false, false],
  ['OpenSMS SMS-only mode', {...explicit, AUTH_PHONE_DELIVERY_MODE: 'opensms_hook', AUTH_SMS_ENABLED: 'true', AUTH_WHATSAPP_ENABLED: 'false'}, true, false, 'sms'],
  ['both explicit channels preserve WhatsApp preference', {...explicit, AUTH_SMS_ENABLED:'true', AUTH_WHATSAPP_ENABLED:'true'}, true, true, 'whatsapp'],
  ['SMS flag must be exact', {...explicit, AUTH_SMS_ENABLED:'TRUE', AUTH_WHATSAPP_ENABLED:'false'}, false, false, ''],
  ['SMS without CAPTCHA site key', {...explicit, AUTH_SMS_ENABLED:'true', AUTH_WHATSAPP_ENABLED:'false', TURNSTILE_SITE_KEY:''}, false, false, ''],
  ['SMS with invalid CAPTCHA site key', {...explicit, AUTH_SMS_ENABLED:'true', AUTH_WHATSAPP_ENABLED:'false', TURNSTILE_SITE_KEY:'bad!'}, false, false, ''],
  ['WhatsApp without CAPTCHA site key', {...explicit, AUTH_WHATSAPP_ENABLED:'true', TURNSTILE_SITE_KEY:''}, false, true, ''],
  ['WhatsApp with invalid CAPTCHA site key', {...explicit, AUTH_WHATSAPP_ENABLED:'true', TURNSTILE_SITE_KEY:'bad!'}, false, true, ''],
  ['legacy enabled', {AUTH_PHONE_ENABLED: 'true'}, true, true],
  ['legacy disabled', {AUTH_PHONE_ENABLED: 'false'}, false, false],
  ['legacy absent remains conservative in portal', {}, false, true],
  ['disabled by malformed explicit value', {...explicit, AUTH_WHATSAPP_ENABLED: 'TRUE'}, false, false],
  ['missing publishable key', {...explicit, AUTH_WHATSAPP_ENABLED: 'true', SUPABASE_PUBLISHABLE_KEY: ''}, false, true],
  ['missing Supabase URL', {...explicit, AUTH_WHATSAPP_ENABLED: 'true', SUPABASE_URL: ''}, false, true],
];

test('portal selects an explicitly admitted channel while preserving legacy WhatsApp behavior', async () => {
  for (const [name, flags, expectedPortal, expectedAdmission, expectedChannel = expectedPortal ? 'whatsapp' : ''] of cases) {
    let calls = 0;
    const env = {...base, ...flags, DB: {prepare() {calls++; throw Error('synthetic_fake_database_stop');}}};
    const response = privacyPortalRoute(new Request('https://api.collect.example/privacy/account-deletion'), env);
    const page = await response.text();
    const marker = /data-verification-available="(true|false)"/.exec(page);
    assert.ok(marker, name);
    assert.equal(marker[1] === 'true', expectedPortal, name);
    assert.match(page, new RegExp('data-verification-channel="' + expectedChannel + '"'), name);
    if(!expectedPortal)assert.match(page, /id="step-phone" hidden>/, name);
    if(expectedChannel) assert.match(page, new RegExp('Verification uses ' + (expectedChannel === 'sms' ? 'SMS' : 'WhatsApp')), name);
    let admitted = false;
    try {
      await startOtp(env, {phone: '+250788123456', surface: 'member', channel: 'whatsapp',
        allow_registration: false, should_create_user: false});
      assert.fail('fake database should always stop execution');
    } catch (error) {
      if (error.message === 'synthetic_fake_database_stop') admitted = true;
      else assert.equal(error.code, 'whatsapp_unavailable', name);
    }
    assert.equal(admitted, expectedAdmission, name);
    assert.equal(calls, admitted ? 1 : 0, name);
  }
});

test('explicit SMS admission is unchanged by WhatsApp availability', async () => {
  for (const [flag, expected] of [['true', true], ['false', false], [undefined, false]]) {
    let calls = 0;
    const env = {...base, ...explicit, AUTH_PHONE_ENABLED: 'true', AUTH_SMS_ENABLED: flag,
      DB: {prepare() {calls++; throw Error('synthetic_fake_database_stop');}}};
    try {
      await startOtp(env, {phone: '+250788123456', surface: 'member', channel: 'sms'});
      assert.fail('fake database should always stop execution');
    } catch (error) {
      if (expected) assert.equal(error.message, 'synthetic_fake_database_stop');
      else assert.equal(error.code, 'sms_unavailable');
    }
    assert.equal(calls, expected ? 1 : 0);
  }
});
