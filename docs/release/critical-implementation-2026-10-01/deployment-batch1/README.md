# ARC05 local backend delivery repair

The initial 27-case proof below is superseded by the [30-case companion-binding proof](../cli-toolchain-batch1/README.md). The current approval contract requires both Supabase executable hashes; retain this batch as its original verification checkpoint.

The canonical deployment command now refuses a missing, stale, changed or wrong-target approval/candidate before project operations. It uses the existing strict source exporter/verifier and executes a private copy of reviewed bytes. Every backend file, handler dependency, migration, config, delivery/readback helper and CLI/Deno pin is bound to the approved operation scope. Current worktree backend drift and unexpected runtime metadata stop further operations.

The transport preserves one-shot migration apply, guarded per-migration Management API fallback, mandatory migration/function readback and bounded partial-failure receipts. A failed or lost mutation response stops downstream writes; earlier commits remain visible in reconciliation. Separately approved staging/remediation scope can run without declaring final production acceptance.

## Verified local outcomes

| Check | Result |
| --- | --- |
| Fake CLI/Deno/Management transport contract | 27 passed; 0 failures; 0 skips |
| Existing candidate exporter regression, including CLI-pin retention | 39 passed; 0 failures; 0 skips |
| Python syntax for four owned/affected modules | Passed |
| Deployment launcher Bash syntax | Passed |
| Owned-path Git whitespace check | Passed |
| Controller, tests and selected dependencies stable during tests/final checks | Passed |
| Hosted deployment, provider or native credential-storage operations | None performed |
| Real approval created | None |

Negative cases cover missing/wrong/expired approvals, wrong target/environment, changed or unlisted candidate/source, missing transitive handler dependencies, incorrect tool pins, frozen-closure failure, worktree/execution/runtime drift, non-connectivity dry-run failure, partial function/migration failures and blocked mandatory readback. Assertions check zero premature remote effects, halted downstream writes and retained partial outcomes. Test approval records and remote state are synthetic.

## Evidence and source boundary

- [Batch metadata](batch.json) records exact source hashes, commands and outcomes.
- [Deployment contract log](delivery-contract-tests.log) and [exporter regression log](candidate-export-tests.log) contain the completed test results.
- [Backend input checkpoint](backend-input-checkpoint.json) contains hashes/modes/byte counts for 300 files and 191 migrations at capture. It is a metadata checkpoint, not a reviewed release candidate or a global source freeze. BE07 and other authorized work can supersede it; recapture and externally review final candidate bytes before delivery.
- [Operator contract](OPERATOR_CONTRACT.md) describes the approval schema, inputs, operation scopes, runtime metadata exception, failure handling and remaining external acceptance.

The original tested controller SHA-256 was `2cf06be4bdad073d5fba317957348dc110e3707589ad84079314e43898994544`; the canonical exporter remains at SHA-256 `1cf2c61c09099b6249895bd3887532cf1672a3f69c3eb4c23cb58c52d94aa690`. The exporter change is limited to retaining `.supabase-cli-version`. Use the linked follow-up proof for the current controller hash.

Local matching hashes and reviewer metadata do not authenticate human identity or authority. Protected release delivery, actual target classification/access, hosted SQL/bundle/dependency identity, providers and full production acceptance remain open. The final export and its independently authorized approval must reflect subsequent backend changes.
