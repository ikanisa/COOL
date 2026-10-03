# Receipt backlog and committed-event foundation — 30 September 2026

Local implementation and focused isolated UAT passed. Nothing in this packet
establishes deployment, authentic provider payment, carrier sending or
production acceptance. The full unattended C21 target remains open: these
acknowledgements record human monitoring observations, not validated business
actions by an unattended supervisor.

Implemented source:

- `supabase/migrations/20260930230100_receipt_backlog_events.sql` adds committed
  immutable UUID events and actor-bound per-consumer observation progress;
  retains newly eligible SMS receipts while dispatch is paused; fences all
  assisted claim/exact-read/confirmation/send-start paths and future private
  state/attempt insertions with the locked real dispatch flag.
- `scripts/tests/receipt_backlog_events_uat.py` clones schema definitions and
  reconstructs API ACLs in a new disposable local database. It accepts only
  the labelled local QA container and specifically known source versions.
- `CONTRACT.md` describes the five authenticated owner RPCs, exact event
  projection, reason codes, pause/suppression semantics and pending historical
  catch-up refusal.

The migration was renamed from the earlier `20260930230000` filename to avoid
a collision with another chat's group-share migration. Its SQL bytes did not
change. The retained final result records the corrected `20260930230100` path.
The other migration was preserved.

## Validation and retained evidence

Final attempt8 passed **79/79 cases** and removed its isolated database.
`result.json` contains the actual counters, source hashes, nonempty business
fingerprints and each named assertion. The repository migration structural
validator passed (`migration-structural.log`).

Tests cover a preexisting immutable 50 RWF primary receipt and a separately
posted 250 RWF historical payment skipped by the old pause behavior. Installing
the new migration preserves all nonempty financial/outbox fingerprints. New
paused eligible posting retains one receipt with exact canonical balances.
Consent exclusion, app-linked exclusion, policy exclusion, contact changes,
primary duplicate rejection, late allocation, compensating reversal,
definite failure and unknown-outcome evidence retain their existing rules.
Old attempt uncertainty reporting/replay remains possible while paused.

Authority tests use actual `authenticated` SQL role execution with synthetic
JWT-context fields. Anonymous and service roles cannot execute the new RPCs.
Missing/expired sessions, revoked approval/grant, missing permissions and
sessions predating approvals/grants are refused. Foreign consumers are denied.
Deferred observations remain pending; exact request replay, conflict,
independent consumers, ACK rollback and partial batches are covered.

Concurrent sessions prove that a later-committing earlier-created event is
still discovered, concurrent observations create one terminal per-consumer
row, pause cannot cross a held dispatch boundary, and parallel canonical
postings preserve balance increments while creating distinct receipts/events.
The final journals remain exactly balanced, the net group balance equals the
nonempty posted payment value, and the old primary receipt remains byte for
byte unchanged after all later work.

`queries.sql`, `queries.log`, `concurrency.log`, restore/install logs and
backend-shaped `events.fixture.json` / `backlog.fixture.json` are retained.
`synthetic-seed.sql` is a reusable local fixture; `preexisting-receipt.sql`
adds the separate prior primary receipt used by the final UAT. They contain
synthetic identities, contacts and financial examples only. No provider or
carrier API, OTP, live send or hosted database was used.

## Isolation and source limits

The quiet local source advanced during earlier attempts. Final attempt8
captured **153 migrations ending `20260930220000`**, with cron launching off
and pg_net batch size zero, and verified the same metadata immediately after
the schema-only dump. It required normalized exact current-source equality
with installed migration registry text for navigation151, shadow152 and
runtime-authority153. The relevant149 authority function's source also matched
the stored installed prerequisite text. These are source/registry parity
checks; they do not attest all deployed function bodies or the live hosted
database. The exact final restored schema snapshot SHA-256 is
`77262947961ac1a724195ea77bdb98088cebd30caecc625ded1d4a93ccbf6d3d`, also recorded in `result.json`.

No source rows or credentials were copied. Owners were normalized and API
ACLs reconstructed. Cron, pg_net, GraphQL and statistics extension members
were excluded; empty local cron catalog fixtures were used. No shared QA or
production schema migration was applied by this runner. Earlier passes and
metadata-refused attempts remain under `.cache/receipt-foundation-attempt*`;
they are historical diagnostics, not added to the final passing case count.

This packet does not cover hosted upgrades with representative production
rows, real signed JWT/PostgREST/GoTrue execution, provider/carrier approvals,
physical devices, production volume, restore RPO/RTO, or unattended action
principals, scheduling, caps and validated run-bound event completion.
Historical contact/consent catch-up remains `CATCHUP_POLICY_PENDING`: no
automatic historical receipt enqueue is enabled.

Final migration SHA-256:
`543ee1a606c3498d254066fcfe356598e1fe50efc54760ff036596395c15b626`.
Final runner SHA-256:
`10bc5b416b745387a5bce012b5fe432259396b9b7052d80ea87cce66d8bfb0ba`.
