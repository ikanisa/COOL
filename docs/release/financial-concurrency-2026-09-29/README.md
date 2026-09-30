# Local financial concurrency rehearsal — 29 September 2026

**Status: F08 remains open; production NO-GO.** The task-owned local Supabase
CLI project `collect_fin_concurrency_qa_20260929` was verified by Docker
labels, fixture configuration and database port 55722. It held only synthetic
Rwanda users and RWF 2,500 evidence. No customer record, real provider call,
hosted service or signed device was used. The replay harness disabled scheduled
jobs.

## Deadlock found and corrected locally

The earlier [134-migration results](baseline-134/) included one passing
provider-finality race and a later run that missed the strict two-worker wait
condition. After starting both database sessions before dispatch, a fresh
134-migration run failed with [one worker still waiting](pre-fix-race.stderr)
and only one processed request. The local PostgreSQL server log reported a
deadlock between the two `process_provider_finality_event` calls while
`confirm_provider_payment` locked the same `payments` tuple `FOR UPDATE`.
This was a genuine transaction failure, not merely a timing problem in the
overlap probe. The server log was inspected during the run; the raw container
log was not retained after the isolated fixture was reset.

The cause was lock order. Each gateway transaction first inserted a
`provider_finality_requests` row, obtaining a foreign-key `KEY SHARE` lock on
the payment. Each then tried to upgrade to `FOR UPDATE`; both held a lock the
other needed. The additive [migration 135](../../../supabase/migrations/20260929120000_provider_finality_payment_lock_order.sql)
acquires a transaction-scoped, payment-keyed advisory lock **before** that
insert. The service-role-only grant, request validation, replay check,
confirmation/rejection calls and journal logic remain in place.

The [one-migration 134-to-135 upgrade](lock-order-upgrade.json) passed on a
populated synthetic fixture. The [before](pre-lock-upgrade-snapshot.json) and
[after](post-lock-upgrade-snapshot.json) snapshots each contain 14 complete
financial/evidence rows with the same SHA-256
`0f488b684973b8439d66db9299b342f000d62ce72118fb235a7e0566db9a2ece`.
The existing posted payment, one provider request/confirmation, receipt
journal and RWF 2,500 confirmed balance did not change. This proves a bounded
synthetic upgrade, not representative hosted migration safety.

## Clean 135-migration sequence

The [clean replay](clean-replay.json) applied **135/135** application
migrations on PostgreSQL 17.6. In that fixture, the [duplicate SMS race](race-result.json)
observed both workers waiting on the same advisory lock; one review candidate
was created and the duplicate was ignored without credit.

The [provider-finality race](finality-race-result.json) observed **both**
service-role workers waiting on advisory locks. Two distinct processed request
IDs produced one provider confirmation, one posted payment, two legacy ledger
entries, and one balanced canonical receipt journal, with RWF 2,500 on each
side. Replaying the same request ID returned its replay marker. The
[Admin reversal race](reversal-race-result.json) then observed two authenticated
workers blocked on one lock and returned one fresh reversal plus one replay.
Readback found one reversal request/journal, two RWF -2,500 compensation
entries, balanced reversal lines, a reversed payment and zero confirmed group
balance. No worker sessions remained.

## Conflicting confirmation race

A separate [clean 135/135 replay](conflict-clean-replay.json) and
[SMS candidate race](conflict-seed-race-result.json) prepared a second review
payment. The [conflict harness](../../../scripts/tests/financial_conflicting_finality_concurrency_uat.rb)
then held the new payment advisory lock until **both** service-role sessions
were waiting. The sessions supplied different request IDs, payload digests
and provider confirmation IDs for the same payment. The
[result](conflict-race-result.json) shows one confirmation succeeded and one
conflicting confirmation was rejected. Independent readback found one
processed request, **zero orphan `processing` requests**, one provider
confirmation, one posted payment, two ledger entries, one balanced receipt
journal and RWF 2,500 confirmed balance. The
[post-state digest](conflict-post-snapshot.json) covers 14 financial/evidence
rows. Function-grant readback was `anon=false`, `authenticated=false`,
`service_role=true` for the finality gateway, and `pg_get_functiondef` showed
the payment advisory lock preceding the request insert. This does not
authenticate the synthetic provider payloads.

## Late confirmation and rejection order

A third [clean 135/135 fixture](ordering-clean-replay.json) reached one review
candidate. The [rollback-only ordering UAT](../../../scripts/tests/financial_provider_ordering_uat.sql)
passed both cases in [its output](ordering-result.txt): confirmation first
followed by a rejected late-rejection request left one posted payment and its
balanced credit intact; rejection first followed by a rejected late-confirmation
request left no posted payment, provider confirmation, ledger entry or journal.
The [before](ordering-pre-snapshot.json) and [after](ordering-post-snapshot.json)
snapshots are byte-identical, with four review/evidence rows under SHA-256
`13294d6d27906507707607c98da6a553685eae04f69d18c99e7ab3ff54c52659`.
The UAT made no lasting data change and did not establish which provider
message is authentic when real messages disagree.

The harnesses, [ordering UAT](../../../scripts/tests/financial_provider_ordering_uat.sql)
and [synthetic seed](../../../scripts/tests/financial_concurrency_seed.sql)
show local idempotence and balanced accounting for these exact sequences. F08
still needs authenticated conflicting/delayed provider events, duplicate
references across payments, historical reversal variants, representative
data, deployed function and grant readback, late-receipt policy and operator
approval. The [snapshot script](../../../scripts/tests/financial_concurrency_snapshot.sql)
and local archives support further upgrade rehearsals. F02, F07, F09, D09 and
O10 remain open.

Post-change checks passed: `make source-integrity`, `make qa-tooling-test`,
Ruby syntax checks for all four concurrent harnesses, `git diff --check`,
evidence JSON parsing, link resolution and the SHA-256 table below. The
current `make release-status-json` decision remains **NO-GO** with seven
candidate, deployment and owner-evidence blockers.

| Source or evidence | SHA-256 |
| --- | --- |
| `20260929120000_provider_finality_payment_lock_order.sql` | `a3bc8db4dbd7ea70077e222d3639dc8e7a940ad1f9275160b6b29292431f9440` |
| `financial_concurrency_snapshot.sql` | `54b3b0e30ad26f01a6ccc6953fd2e0517a37c54f862c6bf60098aa1c62ec068b` |
| `financial_concurrency_seed.sql` | `4b0710649e0f6a06ce0ddb6d8d60a6cc26ad774a99eb10d1efcd7196fe6ea287` |
| `financial_concurrency_uat.rb` | `296c70ff7973e4fbde5f3ed8c5bfe58f5cee399ff3eb532f89c20ae30f8572ad` |
| `financial_finality_concurrency_uat.rb` | `3a37e6f1995d1ac0d1e3eda2044a490a3df4395bb70c1fb000c46a58b5685546` |
| `financial_reversal_admin_seed.sql` | `b68f982872f2009186d4f4a5f50e8ab2e7f93cd10c4f89544fe09fc021462e7b` |
| `financial_reversal_concurrency_uat.rb` | `9e7937b049508fce839d52db0ca8994706cad30769994d5fdbe01e76a7961a5b` |
| `financial_conflicting_finality_concurrency_uat.rb` | `55870ec218e3d0ed4b30b049e611e81112baab87210ac1882233f6cd5ab49889` |
| `financial_provider_ordering_uat.sql` | `c86ad90c5416105646cbff1a587cbd0898ee4d952b558020568111e866752b75` |
| `clean-replay.json` | `177b244f6a6e669b3cdccc0e494d43b1104a4d7a7aa2e3eb56c3cc252a32166b` |
| `race-result.json` | `c84ece12aea1f05398409b0dcbb6733a003ae3a364963a298ff7d161b08d58ed` |
| `finality-race-result.json` | `3334b799686e42aaa6070629162fe1e2bb8cbe400f62a029e262ec3f17f7b730` |
| `reversal-race-result.json` | `7747b37aea210a224a3051e6bc08a2aaab91807bc1e126678d58c8c75443e2de` |
| `conflict-clean-replay.json` | `cbc8df9213ab318dbeb46c2a050232b8dd2a9f793b5fa4c63c941b81979b9d34` |
| `conflict-seed-race-result.json` | `c84ece12aea1f05398409b0dcbb6733a003ae3a364963a298ff7d161b08d58ed` |
| `conflict-race-result.json` | `b1bcee57366def751c62d4241f4d8f9790866efc0199d33e1dbdb8c46ea7eef4` |
| `conflict-post-snapshot.json` | `26c0e37e51f3f75257e0724adba583d418cda788eca61bcd6968ceceadd46afd` |
| `ordering-clean-replay.json` | `ee3ee503eef4d9b2fa7367936357eeb556387e497b1f619f0862a4393dac1292` |
| `ordering-result.txt` | `853d5b4ad1d012b6f2e54dc64afdcd2e6df46e5bf9629931390b79c7c2278315` |
| `ordering-pre-snapshot.json` and `ordering-post-snapshot.json` | `b3805d1ddbd6a0720c8773c6b175295ec3f9fe91bfd76965fc0ff17767568157` |
