# Native SMS parser compatibility evidence

Comparison base: commit `10c0510f9a6949a36e4583f578baa9498b9a9ba6`. All examples below are invented test fixtures; no live messages or database records were inspected. The guarded implementation recognizes only specific, source-anchored forms and must not be represented as supporting every carrier format or proving settlement.

The original, unmodified `native-auto-parser.test.mjs` and `native-auto-format-regression.test.mjs` contain 58 tests. Against the guarded parser, 48 pass unchanged and 10 fail because their previous expectations no longer hold. An instrumented comparison ran those original tests with the baseline return values while also evaluating the new parser: of 57 deduplicated fixture outcomes previously classified as incoming with a positive amount, 13 retained the same classification, amount and currency and 44 did not. Deduplication used test name, synthetic body, baseline amount and resulting guarded outcome. Those 44 include malformed, adversarial and deliberately ambiguous inputs; they are not a count of legitimate carrier formats or actual transactions.

The original fixtures show these practical limits:

- Exact-zero fractions, grouped amounts, day-first dates, numeric transaction IDs and a French receipt are held when the model response omits the payer name or payer evidence. Revised synthetic fixtures with the required complete name and source quotation pass; an actual provider response may still omit them.
- ISO date suffixes, combined fee/balance clauses, prior unrelated failure statements and conditional advice may cause an otherwise plausible receipt to be held.
- Quoted claims, extra unrecognized statements and contradictory wallet or reversal wording are held. Unrecognized formats and unsupported or ambiguous payer-name syntax also remain unassigned.
- Synthetic English `You have received ... from`, Kinyarwanda `Wakiriye ... uhawe na`, French `Votre portefeuille est crédité de ... par`, and Swahili `Umepokea ... kutoka` examples pass parser and mocked-ledger tests with a complete `*****456` masked token and unique matching name. These are four tested examples, not coverage of those languages generally.

The owner-approved masked-name/last-three rule can still collide with another payer; a correct source quotation cannot prove the unobserved digits or actual ownership. The tested `Received ... from ...` cue is an inference about the addressed wallet, not independent settlement verification. No existing payment, financial link or ledger row is modified by these source changes. Database concurrency, real carrier behavior and production latency have not been verified by these synthetic tests.
