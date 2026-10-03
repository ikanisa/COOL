# Receipt source contention — sealed integration handoff

Root is the sole canonical promoter. This worker wrote only its owned staging
directory. No hosted service, provider, real device, Keychain or live SMS was used.

`20261001260000_receipt_source_busy_deferral.sql` is additive maintenance after
the accepted250 language migration, whose exact SHA-256 is
`ee3168ff191a9ba9a623fb4d31ca2b1d3f354f44d0d617824786e41fdc8f1d8e`.
The new migration SHA-256 is
`fe529b7b48ba0e57a5dccf5f0c38eb72cb67a0976d4a074fbdbfcb9a4cdb3cd2`.

All eight existing private ensure row-lock acquisitions use `NOWAIT` inside one
caught subtransaction: payment, lifetime-primary outbox, collection, member,
membership, policy, consent and contact. On contention the subtransaction releases
any earlier acquired row locks and returns the closed result `SOURCE_BUSY`, with
`ok=false`, `business_handled=false` and `receipt_id=null`. It writes no receipt or
immutable content proof. Successful source locks remain until the caller commits
the required durable receipt and evidence. Financial finality, source eligibility,
authorization, policy modes, caps and emergency-stop code are retained.

The existing operational caller durably records the false result in its run event
and event deferral/backlog record; it never inserts a handled-event ACK for busy
work. The exception source allowlist and existing exception reason CHECK admit
`SOURCE_BUSY` and `RECEIPT_OPERATION_SOURCE_BUSY`. Both function bodies and the
entire prior CHECK definition are guarded before any new behavior is published.
`CREATE OR REPLACE` preserves existing function OIDs, owners, signatures, execution
ACLs and security configuration; the migration introduces no new public RPC.

The Edge and MCP finite code registries recognize the new closed result. Both
decoders reject a busy result paired with a receipt UUID, fabricated handling,
private fields or an invented code. Admin labels the cause “Receipt source is
busy”; its evidence decoder also refuses a busy result with a receipt UUID.

## Actual proof and limits

`accepted-sql/result.json` is the retained terminal SQL attempt3:36 distinct
checks, all passed,547 command receipts, inputs unchanged and the network-none
task container removed. The exact executed scope is177 unchanged source08
prerequisite migrations plus110/120/130/140/150/210/220/250 and staged260. This is
185 prerequisite migrations plus the changed migration, not a full196-migration
rehearsal. `excluded-current-migrations.json` lists current canonical migrations
outside this proof, including the four newer foreign migrations2330/2340/2350/2355.
The actual installer was demoted to NOSUPERUSER before260 DDL and drift tests.
Platform role normalization and SQL Auth claims are synthetic local trust
fixtures, not hosted installer, GoTrue, email or provider validation.

The actual two-session claim/ensure experiment observes claim waiting on the
ensure caller's payment while holding the member/contact locks. Both commit
without the former inverse-order deadlock; ensure returns and durably records
SOURCE_BUSY. An existing receipt in the same partial batch is independently
handled, and completion retains the deferred count. A fresh request reads back
the exact original durable response without blind retry.

Successful account claiming still makes that member ineligible for assisted SMS.
The proof explicitly retains its `RECIPIENT_INELIGIBLE` refusal. Recovery uses an
independent unclaimed member with explicit consent: temporary contention records
SOURCE_BUSY, the trusted exception scan persists its closed reason, and a later
run rediscovers the event, saves exactly one immutable receipt/proof, then records
handling. Original busy evidence remains immutable and the obsolete exception
clears. The due-time fixture advances only its task-local mutable deferral
timestamp; production retry timing is not overridden.

Consumer acceptance is composed from four actual commands on one unchanged
private source copy:

- `consumers/edge.stdout`:31 existing Edge contract and signed-handler checks.
- `consumers/mcp.stdout`:7 new actual SQL DTO, signed Edge/MCP and refusal checks.
- `consumers/admin.stdout`:7 actual SQL Admin model checks. No rendered route,
  responsive, keyboard, screen-reader or Revolut comparator acceptance is claimed.
- `typecheck-tail/result.json`:the corrected TypeScript7 command, terminal exit0.

`consumers/frozen-inputs.json` binds98 source inputs,3 selected executable hashes,
1608 dependency files and12 symlink targets. `typecheck-tail` verifies those inputs
and the private runtime source manifest unchanged before/after the corrected
command. It is not a fresh successful aggregate consumer command: the original
typecheck invocation failed TS5112 because TS7 requires `--ignoreConfig` beside an
existing tsconfig when explicit files are supplied. Earlier Edge/MCP/Admin commands
passed and were reused unchanged; they were not rerun or counted again.

Prior SQL attempt1 stopped after its passed claim/durable-deferral checks because
the fixture used the wrong positional inbox argument order (22007). Attempt2
correctly encountered `RECIPIENT_INELIGIBLE` after successful account claiming;
its later lock-branch expectation used the wrong recipient fixture. The migration
bytes were unchanged across all three attempts. Failed raw commands and their
target cleanup are retained as superseded evidence and are not added to the36.

## Promotion

Use `promotion-manifest.json`:verify each existing old SHA/mode immediately before
promotion, preserve old bytes, and copy each new file byte-for-byte from this
sealed packet. Four existing consumer files change; the migration, SQL runner,
MCP test and standalone Admin check are new. No old migration or ACL should be
restored. Source association binds canonical prerequisites separately.

Copy `accepted-sql/observed-busy-ensure.json` to
`docs/release/collect-codex-goal-2026-09-30/receipt-source-busy-20261001/accepted-sql/`
alongside its proof. The new MCP test uses that canonical fixture path by default.
The standalone Admin check accepts the actual fixture directory as its sole CLI
argument. The promotable SQL runner resolves the canonical migration first and
falls back to the exact owned stage. `runner-path-association.json` binds its
runner-only input-path delta to the retained executed runner; all executed logic
is byte-identical after that delta is removed. This association does not claim a
fresh whole SQL run of the path-adapted runner.

Full candidate replay, hosted authenticated services, real Android/carrier work,
complete visual acceptance, telemetry, recovery drills and release GO remain
separate requirements. This packet establishes the bounded source-contention
slice only.
