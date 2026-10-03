# L23 rollback, forward upgrade and client compatibility evidence

Captured: 2026-10-01T14:28:33.994314+00:00

Read-only supplement. No SQL, tests or builds were run. The original ledger JSON/Markdown and canonical registers remain unchanged.

## Existing rollback and forward compatibility proofs

These are genuine transaction rollback preservation, trace-bound recovery, legacy forward upgrade/reapplication, incompatible caller rejection and current185 populated upgrade proofs. They do not claim a full185 database downgrade and redeployment, or hosted/provider/device rollback.

### OTP rollback56

- [docs/release/otp-uncertain-recovery-2026-09-30/rollback145-root-attempt2/result.json](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/docs/release/otp-uncertain-recovery-2026-09-30/rollback145-root-attempt2/result.json) — PASS, SQL exit0, failures empty; SHA-256 `daeb8fcfb8c71b3bc6a19aca9d10d1df94f281394c56dab2e3f1c6d0a2a26e73`.
- Exact actual marker: `SIGNED_OTP_RECOVERY_UAT_PASS: 56 checks`.
- Reviewed executed SQL [docs/release/otp-uncertain-recovery-2026-09-30/rollback145-root-attempt2/reviewed-source.sql](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/docs/release/otp-uncertain-recovery-2026-09-30/rollback145-root-attempt2/reviewed-source.sql) SHA `de82530e9d6ada239f0634ba65323145394db95ef890a5eff634b96f1f5d18d4`.
- Actual stdout SHA `afcc92f6b69213e646312e08fbaad9ebd4741998a1c3ac1d2ff6532d1110489d`; exact before/after snapshot SHA `af64fbb50e479c7958f3288e5da502dc16995352ae712fb96355073c679c3f53`.
- Current harness [scripts/tests/signed_otp_recovery_uat.sql](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/scripts/tests/signed_otp_recovery_uat.sql) SHA `de82530e9d6ada239f0634ba65323145394db95ef890a5eff634b96f1f5d18d4`.

### Legacy OTP forward upgrade/reapplication9

- [docs/release/otp-uncertain-recovery-2026-09-30/upgrade145-root-attempt1/result.json](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/docs/release/otp-uncertain-recovery-2026-09-30/upgrade145-root-attempt1/result.json) — PASS, SQL exit0, failures empty; SHA-256 `f331d0c1d05abcb597456d6ab847efa0fc04df5ce94c9e3ee85d3b400d69e677`.
- Exact actual marker: `SIGNED_OTP_UPGRADE_UAT_PASS: 9 checks`.
- Reviewed executed SQL [docs/release/otp-uncertain-recovery-2026-09-30/upgrade145-root-attempt1/reviewed-source.sql](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/docs/release/otp-uncertain-recovery-2026-09-30/upgrade145-root-attempt1/reviewed-source.sql) SHA `b11ceabb0c7f20c2ddf0b167765e973bc4a82d7987d2c994bbce90710c259bd7`.
- Actual stdout SHA `a9d9f88a4684d4f06ebdc2da9589966e859ade6ee024b3c1df5e88d7970b9716`; exact before/after snapshot SHA `af64fbb50e479c7958f3288e5da502dc16995352ae712fb96355073c679c3f53`.
- Current harness [scripts/tests/signed_otp_recovery_upgrade_uat.py](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/scripts/tests/signed_otp_recovery_upgrade_uat.py) SHA `1e7b8fb9e78afac78e9bba1150f1ce352344fc9426651baddcf67b44fd9beb3c`.

Executed exact assertion names:

- `legacy accepted hook acknowledgement preserved`
- `legacy completion cannot fabricate success`
- `legacy policy preserved`
- `legacy quota charges retained`
- `legacy reserved remains unknown without resend`
- `legacy sent becomes acceptance only`
- `legacy unresolved cannot authorize send`
- `reapply invents no historical provider evidence`
- `reapply preserves every attempt and stored outcome`

The reviewed SQL reconstructs exact historical v2 OTP definitions and two retained outcomes, applies145, reapplies145, invokes v2 callers, and rolls back the fixture. This is actual forward/reapplication behavior with preserved outcomes; it does not commit a hosted migration.

### Resource rollback29

- [docs/release/upload-integrity-2026-09-30/rollback146-root-attempt1/result.json](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/docs/release/upload-integrity-2026-09-30/rollback146-root-attempt1/result.json) — PASS, SQL exit0, failures empty; SHA-256 `1365afc11b7009abfa5f7eebbfbcf2de261f5844741969227f026158b4e15edf`.
- Exact actual marker: `ROSTER_RESOURCE_UAT_CHECKS:29`.
- Reviewed executed SQL [docs/release/upload-integrity-2026-09-30/rollback146-root-attempt1/reviewed-source.sql](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/docs/release/upload-integrity-2026-09-30/rollback146-root-attempt1/reviewed-source.sql) SHA `badb9cdf37e14e090a4bb9ea4ec2d6a06dc3621b15b721cd8cd6f2e28cdfc6f6`.
- Actual stdout SHA `f8e398b8045c6af9b739311d0bb918c499ca4c4b31a783f251da45b82683cd77`; exact before/after snapshot SHA `30586e67b7c2a5a37f5ce24a9123922ff398687e1ec31dabcad0607274967c64`.
- Current harness [scripts/tests/roster_resource_integrity_uat.sql](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/scripts/tests/roster_resource_integrity_uat.sql) SHA `badb9cdf37e14e090a4bb9ea4ec2d6a06dc3621b15b721cd8cd6f2e28cdfc6f6`.

### Resource146 with prior142/144 callers

- [docs/release/upload-integrity-2026-09-30/compatibility146-root-attempt1/result.json](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/docs/release/upload-integrity-2026-09-30/compatibility146-root-attempt1/result.json) — PASS, SQL exit0, failures empty; SHA-256 `8d91d9fd21752dc1446823a6cb9d09a15e4577bd058a533daf0681b52283e4b7`.
- Exact actual marker: `FINAL146_COMPATIBILITY_PASS`.
- Reviewed executed SQL [docs/release/upload-integrity-2026-09-30/compatibility146-root-attempt1/reviewed-source.sql](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/docs/release/upload-integrity-2026-09-30/compatibility146-root-attempt1/reviewed-source.sql) SHA `cf01acb18db68afd85d26cf11a241f796fa4649d2dbc4140237756bbe99cd777`.
- Actual stdout SHA `49d6fa87bfd900620ee426f75f75c9f78c741068adfeaa738d991de81a4275dc`; exact before/after snapshot SHA `30586e67b7c2a5a37f5ce24a9123922ff398687e1ec31dabcad0607274967c64`.
- Current harness [scripts/tests/roster_resource_final_compatibility_uat.sql](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/scripts/tests/roster_resource_final_compatibility_uat.sql) SHA `cf01acb18db68afd85d26cf11a241f796fa4649d2dbc4140237756bbe99cd777`.

Actual failure assertions bind lost cleanup ACK repair,142 reviewed/commit receipts,144 exact committed reload and verified source/resource lineage. The passed marker demonstrates those prior callers remain compatible with146 verified resource prerequisites.

## Exact roster142 rollback/recovery receipts

- [docs/release/roster-import-provenance-2026-09-30/rollback142.json](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/docs/release/roster-import-provenance-2026-09-30/rollback142.json) — `pass`, SHA `d7478524f6320fab2076245fdaaecedbff5430d1f71f52de05169ea8ec486a7a`.
- [docs/release/roster-import-provenance-2026-09-30/recovery142-trace-attempt2.json](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/docs/release/roster-import-provenance-2026-09-30/recovery142-trace-attempt2.json) — `rollback_rehearsal_pass`, SHA `cf71e34e12e6178c8532c30bb63e018e407f2b7dac8b8337ed90c369845eb546`.
- [docs/release/roster-import-provenance-2026-09-30/recovery142-applied.json](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/docs/release/roster-import-provenance-2026-09-30/recovery142-applied.json) — `recovery_applied`, SHA `fa7f37d87940c3ac0165457874fc4121af0cabaa176481c4d82eff262fbbf6ed`.
- [docs/release/roster-import-provenance-2026-09-30/runtime-verification.json](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/docs/release/roster-import-provenance-2026-09-30/runtime-verification.json) — `local_scoped_pass`, SHA `af92265fd2037d66b9a34c0bd9d93d73c9767b0f3b650b0a3e8bd58e0c4e67c5`.

- Rollback142:96 assertions, all129 table fingerprints restored, all SQL rolled back; sequence counters explicitly not reset.
- Trace2 before/after digest equals `0601263ec5a4c38d2fc852201a6990dd7f009072224d928c00cfd5494cc5c2f6`.
- Applied recovery exit0 pins successful trace SHA `cf71e34e12e6178c8532c30bb63e018e407f2b7dac8b8337ed90c369845eb546`, immutable backup/failed/recovery source and unchanged pre-recovery controls; post-state equals131-table baseline digest `b40cf394629383ba989f65cc1def811aa5f4d367aaab7e52610ec697aa0d322c`.
- Subsequent `local_scoped_pass`:96 SQL assertions/11 real concurrency scenarios/two SQL receipt cases. This proves operation after recovery of that exact failed fixture, not a full185 migration downgrade.
- Current recovery harness [scripts/tests/roster_import_provenance_recovery_uat.rb](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/scripts/tests/roster_import_provenance_recovery_uat.rb) SHA `666c66c853665fc2d993a87e42ea5e7cc83df9f7ee1b994e9ebfd69cd4cd8166` equals trace/apply binding.

## Current final-email transaction abort/replay

- Accepted receipt [docs/release/rapid-completion-2026-10-01/e1-roster-final-email-current1/attempt5-exact-inspection-contract/result.json](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/docs/release/rapid-completion-2026-10-01/e1-roster-final-email-current1/attempt5-exact-inspection-contract/result.json) SHA `aef08b67add5b8fa1128c4aa7f21b2580aaa0007e8af586fd0533e09907012d1` — PASS25 actual cases/two observed blocking orders.

- `public email revocation wins before established-snapshot transfer and leaves no branch`: PASS.
- `transfer wins before public email revocation but cannot be recovered after committed revoke`: PASS.
- `actual changed draft CAS refuses the genuinely prior etag`: PASS.
- `exact transfer replay is byte-equivalent without another transfer audit`: PASS.
- `explicit commit replay creates one durable commit and one audit`: PASS.
- `durable commit recovery returns the same recorded result`: PASS.

The first race establishes the old snapshot, observes actual blocking, requires40001 (or explicitly allowed fresh-authority42501), no success result, and zero transfer rows for the original request. The opposite race records transfer before committed revoke and then denies recovery. Negative calls execute real `begin; ...; rollback;` and require exact SQLSTATE/message. These are real aborted transaction/no-branch checks, not mocked rejection.
- Exact runner [docs/release/rapid-completion-2026-10-01/e1-roster-final-email-current1/attempt5-exact-inspection-contract/runner.py](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/docs/release/rapid-completion-2026-10-01/e1-roster-final-email-current1/attempt5-exact-inspection-contract/runner.py) SHA `af7cf163defd9676ff63f17ce2181745b0798158bd363ebd6d97c4072f4af193`.
- All seven named consumed source files still equal the accepted source map; the receipt retains ten actual dependency definition hashes. No whole mutable SQL definition catalog is inferred.

## Current185 forward upgrade and incompatible request

- [docs/release/rapid-completion-2026-10-01/ordinary-installer-current-resumption3-private-platform/result.json](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/docs/release/rapid-completion-2026-10-01/ordinary-installer-current-resumption3-private-platform/result.json) SHA `6aa1729f789d2df9ca1f3df586a5b915b246ca24dd8b0c882d1d4976007f6f9d` — PASS36,185 clean/185 populated,370 actual applications, task containers removed.

- `every current application migration replays under ordinary local authority`: PASS.
- `every pending migration preserves 18 predecessor financial receipt Auth and approval projections`: PASS.
- `confirmed payer migration cancels only the incompatible legacy intent`: PASS.
- `all retained journals remain two-line balanced`: PASS.
- `paused predecessor payment is never silently backfilled`: PASS.
- `upgraded read calls preserve all predecessor projections`: PASS.
- `entire migration set and source bytes match the captured ordinary rehearsal`: PASS.

The incompatible intent assertion compares exact current rows: `SYNTHETIC-VALID: pending`, `SYNTHETIC-UNVERIFIED: cancelled`. Retained predecessor850 RWF/three balanced journals/two immutable primary receipts are preserved. This proves current-set legacy-state handling, not an old-client UI interaction.

## Named migration compatibility guards

- [docs/release/local-database-runtime-2026-09-30/staged-bundle154-attempt24-current23-final-policy/result.json](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/docs/release/local-database-runtime-2026-09-30/staged-bundle154-attempt24-current23-final-policy/result.json) SHA `df1fb753be6f9cb75052aa79272910d86bd7741b88699a40a56df8b69971cf68` — actual86-case scoped PASS at177 sources.

- `combined receipt content policy preserves non-dispatch member-only v2 scope`: PASS.
- `existing pending contribution replay survives full staged bundle`: PASS.
- `exact request guard still rejects oversized amount after all stages`: PASS.

The exact amount RPC case supplies9007199254740992 and requires22023/`contribution_amount_not_exact`. The145 v2 wrappers require service authority, leave uncertain requests `unresolved` and refuse fabricated completion success. Declaration bodies remain in current185. Historical service-only OTP and legacy phone-authority fixtures are not current email/provider release acceptance; current email race and185 migration proofs separately cover their declared scopes.

## Verified named source equality

Each of these eight migration bodies was rehashed and equals the current185 ordinary receipt inventory. This bounded check is not a new exhaustive migration scan.

| Source | Current/current185 SHA-256 |
| --- | --- |
| [20260930100000_roster_import_provenance.sql](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260930100000_roster_import_provenance.sql) | `75a315d8a41c2c19f62f2fcd4557e27cb7c14e3f9ebe251f57b18e748d7349d7` |
| [20260930120000_roster_import_reload_recovery.sql](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260930120000_roster_import_reload_recovery.sql) | `751be9afb6a1da5e221160b0201b0c3b7c532dc56f170f630ca03870929455b9` |
| [20260930130000_signed_otp_uncertain_recovery.sql](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260930130000_signed_otp_uncertain_recovery.sql) | `7c3fb624d65a9d70b8503d8fd5c265a8d452242638129b6d30de557633bbebe5` |
| [20260930140000_roster_resource_integrity.sql](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260930140000_roster_resource_integrity.sql) | `d68f8fc45eb92b7ca34ac710548f105b926bfe9026e3214f0e8b030075026f4b` |
| [20260930170000_roster_fresh_auth_recovery.sql](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260930170000_roster_fresh_auth_recovery.sql) | `53e5591e5901acc345101c5113a0c75b7b993011b5743119a59f52c883ceb00d` |
| [20260928170000_confirmed_momo_payer_posting.sql](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260928170000_confirmed_momo_payer_posting.sql) | `f7f644d1d3c129d1b89c658737760db2d86fcd9b78bcb43b8225eb4b67ff1182` |
| [20260930234000_exact_request_amounts.sql](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260930234000_exact_request_amounts.sql) | `0ca10f9a069c83f12bc1c1f4529cac2d31579e6132d98382fb57921585b790ba` |
| [20261001100000_receipt_financial_policy.sql](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20261001100000_receipt_financial_policy.sql) | `cfddaa7700550de824616dacff772352fe15d98af1b3022c4479311f929f83e0` |

## Acceptance limit and preserved lookup failures

The rollback/forward/client clauses have the scoped named evidence above. Root can bind them to the final source candidate alongside current185 replay/preservation and current critical auth/ACK/finality/session evidence. No inspected receipt asserts a full185 downgrade/redeploy, platform-extension rollback, real network/provider side effects or signed app/backend compatibility.

Read-only lookup encountered a list-versus-dictionary metadata assumption (`AttributeError`) and a report-string concatenation of a dictionary (`TypeError`). Both failed before this file was written and before any mutation. The corrected supplement reads named rows/hashes only; no SQL/test runtime failure was discarded.

## Recorded exact final-email function signatures

These are the accepted actual `pg_get_functiondef` digests in the final-email receipt. This supplement verified its named declaration sources against live files and the current185 migration inventory; it did not execute a fresh SQL catalog read. Reuse is confined to this source closure and the receipt’s exact function definitions.

| Signature | Captured definition SHA-256 |
| --- | --- |
| `admin_commit_roster_import(uuid,uuid,uuid,text,boolean,text,uuid,text,text)` | `27494d9ec43843cf0e77faa43dae2bb4bc62d081a6c1d889452b0ae89584826a` |
| `admin_execute_roster_import_intent(uuid,text,boolean)` | `3ca1ecf213f33e088d024f7d33aa9f4596e9cfb2f78d369c2b20ad617a385d9b` |
| `admin_recover_roster_import(uuid,uuid)` | `83b8badc0c186e4bc17aaa2abbf762be9074112bcc50c10a0dbf4c79b9c05697` |
| `admin_revoke_email_operator_v1(uuid,text)` | `454baca7fc880c96d7d7fb94c491c45703e725d09b8f52691f4f69456fd89809` |
| `admin_transfer_interrupted_roster_import(uuid,uuid,text,boolean)` | `02895e2fd6b71501ded41dbe96847cda83e1e6246d6a7a41d48889c0b70e0be6` |
| `assert_admin_permission(text)` | `620faec8017b23299cc189619a10d410c27b18ee2e7651832ac478cceafe6151` |
| `collect_hybrid.require_fresh_roster_auth()` | `6765032b68aa13acd04627bd6f9a3fc6115e8ee6f8f97986ee642f743c4262e5` |
| `collect_hybrid.require_roster_actor(uuid,uuid)` | `cc60737f3c11f45648f2f53fbfa59be10ece3e82f21ae13ee8013b44e17b31cc` |
| `collect_hybrid.require_roster_actor_authority(uuid,uuid,text,text[])` | `8d97c1f96e0fe295070dfd4a9429d657eeff4c18f79bef95279227c8b08493bc` |
| `collect_hybrid.require_roster_caller()` | `49ebc05485e5541e025a5fc738d9299211cc9d354e3cdabf415088796ef8aef4` |

Current142 recovery’s direct concurrency harness SHA `94fd6a7e7859ad2f220b88cf6419dcc99f46701411fd32eafc33ccd1f4a1e1b9` equals the trace-bound direct harness digest.
