/**
 * Read-only characterization of the CURRENT local candidate parser.
 * This is an audit, not a replacement parser or an end-to-end UAT runner.
 * Node 24 native TypeScript stripping executes the existing TypeScript source.
 * No database, API, Messages, schedule, or customer data is accessed.
 * Exit 2 means the requested hybrid receipt contract is not implemented.
 */
import assert from 'node:assert/strict';
import { parseMomoSms } from '../../supabase/functions/_shared/momo_sms_parser.ts';

const baseline = [];
globalThis.Deno = {
  test(name, run) {
    baseline.push({ name, run });
  },
};
await import('../../supabase/functions/_shared/momo_sms_parser_test.ts');
const baselineResults = [];
for (const test of baseline) {
  try {
    await test.run();
    baselineResults.push({ name: test.name, result: 'PASS' });
  } catch (error) {
    baselineResults.push({ name: test.name, result: 'FAIL', error: error.message });
  }
}
delete globalThis.Deno;

// Entirely synthetic fixtures: not captured member messages.
const masked = parseMomoSms(
  'M-Money',
  'You have received 1,500 RWF from TEST MEMBER A (***456) at 2026-09-02 10:00:00. Your balance: 9,500 RWF.',
);
const balanceFirst = parseMomoSms(
  'M-Money',
  'Your balance: RWF 9,500. You have received RWF 1,500 from 0788000001. Financial Transaction Id: SYNTHETIC001.',
);
const checks = [];
function check(id, description, test, expected, observed) {
  let result = 'PASS';
  try { test(); } catch { result = 'GAP'; }
  checks.push({ id, description, result, expected, observed: observed ?? null });
}
check('PARSER-01', 'Receipt amount is extracted',
  () => assert.equal(masked.amount_rwf, 1500), 1500, masked.amount_rwf);
check('PARSER-02', 'Permitted M-Money sender is recognized as MTN MoMo',
  () => assert.equal(masked.network, 'mtn_momo'), 'mtn_momo', masked.network);
check('PARSER-03', 'Masked payer name is preserved for private matching',
  () => assert.equal(masked.sender_name, 'TEST MEMBER A'), 'TEST MEMBER A', masked.sender_name);
check('PARSER-04', 'Masked payer last three digits are extracted',
  () => assert.equal(masked.payer_last3, '456'), '456', masked.payer_last3);
check('PARSER-05', 'Resulting wallet balance is separately extracted',
  () => assert.equal(masked.wallet_balance_rwf, 9500), 9500, masked.wallet_balance_rwf);
check('PARSER-06', 'Complete masked receipt is not rejected for lacking provider transaction ID',
  () => assert.ok(masked.confidence >= 0.90), '>= 0.90 under current allocator threshold', masked.confidence);
check('PARSER-07', 'Amount is tied to the receipt clause, not first currency occurrence',
  () => assert.equal(balanceFirst.amount_rwf, 1500), 1500, balanceFirst.amount_rwf);
check('PARSER-08', 'A full destination is not invented from the last three digits',
  () => assert.equal(masked.sender_phone, null), null, masked.sender_phone);

const report = {
  audit: 'collect.hybrid_sms.current_state.v1',
  executed_at: new Date().toISOString(),
  scope: 'Local source execution with synthetic fixtures only',
  runtime: process.version,
  legacy_parser_tests: baselineResults,
  requested_hybrid_contract: checks,
  summary: {
    baseline_passed: baselineResults.filter(x => x.result === 'PASS').length,
    baseline_total: baselineResults.length,
    contract_passed: checks.filter(x => x.result === 'PASS').length,
    contract_gaps: checks.filter(x => x.result === 'GAP').length,
    contract_total: checks.length,
    production_ready: false,
    reason: 'This parser-only diagnostic does not establish offline allocation, integrated persistence, authorization or physical SMS delivery',
  },
};
console.log(JSON.stringify(report, null, 2));
process.exitCode = baselineResults.some(x => x.result === 'FAIL') ? 1
  : checks.some(x => x.result === 'GAP') ? 2 : 0;
