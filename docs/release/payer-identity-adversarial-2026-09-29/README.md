# Payer identity adversarial rehearsal — 29 September 2026

**Local result:** [15 rollback-only assertions](uat-result.txt) passed against
the task-owned `collect_financial_qa_20260928` Supabase CLI fixture. Docker
labels identified that project and its `.cache/financial-qa-20260928` workdir;
the database was healthy on local port 55422. The guarded fixture held 133/133
migrations through `20260928174000`, one synthetic Auth user, two payments,
three raw SMS records, two parsed events and one intent before the run. No
customer record or provider transaction was used.

The [full-schema UAT](../../../scripts/tests/payer_identity_adversarial_uat.sql)
created two rollback-only Rwanda members with the **same name, last three
phone digits and RWF 2,000 request amount**, but different confirmed Auth
phones and hashes. Their SMS events formed separate review candidates bound
to the correct user and intent, with no ledger or journal credit. A third
event with only the shared name/suffix/amount went to review without a
payment. A conflicting public ID also went to review. A second payer's replay
of the first payer's provider reference was ignored without a new candidate.
Two active intents for one payer and amount on different receiving routes were
ambiguous when the event lacked a receiver, so no payment was created.

The [before](pre-snapshot.json) and [after](post-snapshot.json) financial
snapshots are byte-identical (SHA-256
`8e68e83fc4e1e856d1964cd72227b5be810df901397f28386cb0bbd1424871fd`):
16 retained evidence rows, the original posted/review statuses, cancelled
historical intent and **RWF 1,500 confirmed group balance** were unchanged.
The UAT committed no writes. To reproduce, run the SQL with
`psql -XqAt -v ON_ERROR_STOP=1` against only the named local fixture after
verifying its Docker labels and guard counts; compare the read-only
`scripts/tests/historical_financial_upgrade_snapshot.sql` output immediately
before and after.

This adds evidence for F09 and duplicate-reference containment under F08. It
does **not** prove concurrent workers, provider identity or settlement,
operator dispute handling, a representative historical upgrade, hosted
deployment, or signed-device behavior. Those [acceptance items remain
open](../PRODUCTION_READINESS_REMAINING_TASKS_2026-09-28.md).

Evidence SHA-256: UAT SQL
`cefe463900e257db7c50ea8f2f08f24cc58d26ffd0bc57beaf320febe4d6794d`;
[result](uat-result.txt)
`99b08198edfed8fd9801ee1d6296146a1b09b186651990e25e86a8e942a44bbf`.
