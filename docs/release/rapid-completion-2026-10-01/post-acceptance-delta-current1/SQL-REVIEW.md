# SQL delta review

Review scope: the two added migrations in the immutable 2026-10-01T15:25:51Z capture. This is an additive review of the accepted 185-migration source, not an acceptance of the later mutable checkout.

## Follow-up v2

The migration adds an email-owner-only directory, fingerprint-bound mutation receipts and an original-request lookup. It delegates mutation to the existing v1 function and retains its revision, recipient, expiry, request and audit controls. Reads recheck authority; pending request lookup uses the existing request advisory-lock namespace and never treats a missing receipt as success. Public, anonymous and service execution of the added functions/helpers is revoked; only the declared public functions are granted to authenticated callers.

The existing `exception-followup-v2-20261001/attempt2/result.json` has 83 passing checks, an explicitly removed networkless private target and source hashes matching every declared input in this capture. This proof covers actual request/replay/conflict, recipient revocation, expiry, authority, paired directory pagination and nonempty financial-state preservation. Its owner-normalized retained schema and synthetic claims do not establish hosted installer or Auth-service acceptance. The exact observation is recorded in `sql-reuse-observation.json`.

## Inbox and joined history v2

The migration adds a private, immutable escalation-event table, source-derived retained facts, transition triggers, namespaced event identifiers and bounded history/inbox reads. History explicitly reports incomplete coverage and preserves original assignment/deadline facts. Retained events report an unknown historical executing identity. Service delivery remains distinguishable from human action. The current-operator inbox filters durable delivery by its recorded recipient. The new read acknowledgement delegates to the existing opening action and rechecks authority before returning.

The capture initially indexed physical source UUIDs while its combined cursor orders namespace-derived event UUIDs. The other chat subsequently added expression indexes matching all three actual history ordering keys. Those later bytes are outside this capture and require their own completed query-plan proof.

At this review, the inbox/history runner has not produced an accepted complete result. Failed attempts and later source changes are preserved in the other chat's evidence. A failed or running whole command is not counted as an acceptance pass. The final joined-history decoder must also be exercised against successful observed SQL responses rather than only presentation fixtures.

## Integration requirements

1. Capture the completed current inbox/history implementation and successful evidence with matching source/transitive inputs.
2. Exercise the actual observed response through the current Admin decoders and affected callers.
3. Validate both new migrations under ordinary installer authority, including populated predecessor and immutable source/audit preservation. Reuse the accepted 185-migration proof wherever its inputs still match.
4. Refresh the affected Admin browser artifact and lifecycle/state proof after application fixes and source ownership have been reconciled.

No hosted, provider, signing or production-release acceptance is claimed. Existing accepted source/build archives and registers remain unchanged.

## Completed verification addendum

The later inbox/history implementation subsequently completed **100 passing checks** in `exception-inbox-audit-v2-20261001/attempt8`. Every recorded source hash matched the shared files when read back; the result, actual responses, logs and exact executed inputs are retained in `sql-current/`. Its ordinary-owner/platform limitations remain explicit.

The Admin private derivative then passed **12 actual SQL-response decoder cases**, using those exact observations. The corrected read-order expression indexes are included in the separate completed SQL source.

The exact completed 187-migration set also passed **187 clean and 187 populated applications under non-superuser installer authority**, with **36 checks** and both private targets removed. See `sql-ordinary187/validation.json`. The earlier unsuccessful observations above remain historical and are not counted as completed whole-command passes.

Shared-source ownership, application of the two review fixes, a final combined-source capture and current Admin browser/PWA artifacts remain integration requirements. No updated mutable-checkout or release acceptance is claimed.
