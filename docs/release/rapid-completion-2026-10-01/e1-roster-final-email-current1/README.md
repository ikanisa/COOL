# Final email roster essential acceptance

**PASS: 25 actual SQL checks, including two observed blocking races.** This closes the specific E1 final-email roster acceptance gap identified in the read-only audit. It does not certify the entire E1 register or production release.

## Accepted result

- [Actual result](attempt5-exact-inspection-contract/result.json): `aef08b67add5b8fa1128c4aa7f21b2580aaa0007e8af586fd0533e09907012d1`.
- [Accepted runner](attempt5-exact-inspection-contract/runner.py): `af7cf163defd9676ff63f17ce2181745b0798158bd363ebd6d97c4072f4af193`.
- [Validation](validation.json): `7de3991aed4ea7c2a3ce8e51994c6abd8d61dedb8a3c35ac6a7d2ebb03635dae`.

The successful command was `python3 docs/release/rapid-completion-2026-10-01/e1-roster-final-email-current1/attempt5-exact-inspection-contract/runner.py`, session74157, terminal exit0. No process remains owned by this packet.

## Behavior proved

The fixture uses verified synthetic email identities, current email approvals, fresh Auth sessions and explicit platform-owner permissions, with email mode enabled and no WhatsApp approval. It exercises the public roster RPCs rather than calling the authorization helper as the operation under test.

- A genuinely prior draft etag is refused after an acknowledged draft update.
- Transfer ACK binds the request, actor, fresh session, source, expiry and original proof. Exact replay returns the same ACK and one transfer audit.
- Recovery preserves saved rows and source provenance while resetting human approval.
- Current approved cross-actor access to inspection, recovery and transfer status is denied. Anonymous and service roles cannot invoke private recovery.
- Committed session, role and email-approval revocation each denies recovery; restored authority recovers the same receipt.
- Persisted review and commit intents execute with exact request/payload-hash bindings. Explicit commit replay creates one commit and one import audit.
- The durable import audit exactly binds actor, collection, request, import, revision, source hash, reviewed-row hash, affirmation, mode, count and reason. Recovery returns the recorded commit result.
- Public email revocation before transfer blocks the waiter, refuses its established snapshot with `40001`, and leaves no branch.
- Transfer before public email revocation blocks the revoker, commits in that order, and subsequent recovery is denied after revocation commits.

## Consumed scope and preservation

The schema-only clone retained installed154 definitions and reconstructed API relation/column ACLs. Only four migration sources were applied in the clone: operator email213000, cutover220527, sensitive authority233000 and final operator reason235500. Resource145 and recovery149 singleton rows were restored using their exact installed migration initializer statements, with source/installed statement equality. No shared data rows or credentials were copied.

The actual consumed function definitions and source hashes are in the result/validation. All consumed source bytes and recorder helpers remain unchanged. The clone owner was NOSUPERUSER; network and scheduling were disabled. No shared cron DML, superuser escalation or network workaround was used.

The owned database was dropped. All **153 shared tables**, catalog/ACL/control and cron fingerprints exactly match the before snapshot. The shared fixture remains **154 migrations**, latest20260930230000, quiet, NOSUPERUSER, cronoff/net0 and no cron DML privilege.

## Preserved attempts

The original failed packet and attempts2–4 remain unchanged. They exposed schema-only fixture omissions (resource policy/recovery budget initializers), a checkpoint UUID argument supplied as a hash, and a missing inspection etag argument. Each attempt dropped its clone and preserved all shared data/catalog/cron fingerprints. These are retained fixture failures; no production SQL or runtime source was edited.

## Limits

JWT claims were synthetic session inputs inside actual PostgreSQL API-role calls; this does not prove signed JWT/PostgREST routing, real email delivery or hosted configuration. Controlled source/decoder/provider metadata was supplied to service RPCs; no real image extraction/provider call is claimed. No full177/current23 migration replay, whole36-race suite, history benchmark, browser/native build or exhaustive matrix was run.
