// Node 24 native TypeScript stripping. Synthetic fixtures, no network or sends.
const tests = [];
globalThis.Deno = { test: (name, run) => tests.push({ name, run }) };
await import('../../supabase/functions/_shared/momo_sms_parser_test.ts');
await import('../../supabase/functions/_shared/momo_sms_hybrid_test.ts');
let failures = 0;
for (const { name, run } of tests) {
  try { await run(); console.log(`PASS ${name}`); }
  catch (error) { failures++; console.error(`FAIL ${name}: ${error.message}`); }
}
delete globalThis.Deno;
console.log(`${tests.length - failures}/${tests.length} passed (synthetic local unit tests)`);
process.exitCode = failures ? 1 : 0;
