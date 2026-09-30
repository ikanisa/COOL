# Browser reload recovery — proposed, not implemented

## Current safe boundary

The implemented dialog keeps source bytes, edited rows, request payloads and request IDs in memory. An uncertain commit is now checked with `admin_get_roster_import(p_import_id)` before another write. A recovered completion is success only when the complete receipt matches the existing pending request, import, revision, reviewed hash, mode, group and row count. A different request's completion is displayed as a terminal outcome and never returned as this request's success.

Closing/discarding the dialog or reloading the page loses that memory. This packet does not claim cross-reload or cross-tab duplicate prevention. Server migration142 still prevents a second commit of the **same** import; a deliberate fresh upload creates another import and must not be used to guess whether a previous import committed.

## Reference-only browser bookmark

A future change should persist only a versioned, bounded reference bookmark in session storage: deployment/project identity, captured actor UUID and Auth-session UUID, import UUID when known, stable upload/review/commit request UUIDs and acknowledged revision UUID. Do not store access/refresh tokens, original bytes, names, phones, edited rows, titles, reasons, extracted text or provider output. Treat every bookmark as attacker-controlled routing input, never authority. Establish the original actor/session before reading it; same-session token refresh is allowed, another account or session clears it. Clear on explicit discard, sign-out/revocation, rejected ownership and expiry. Do not copy it into URLs, analytics, clipboard or logs.

On reload, hide the private review and disable all writes until an authenticated, session-bound server read proves the referenced state. A successful read may restore server-held rows into memory. Preserve the original extraction receipt and initial confidence separately from later human revisions. Missing source bytes must not be described as present: PDF/image review may require the operator to reattach the matching original file locally before affirming the rows, without sending it to the provider again. A bookmark must never cause extraction, review or commit automatically.

## Required additive API work (current142 cannot supply this)

1. **Lookup a lost upload acknowledgement by stable request UUID.** Current public `admin_get_roster_import` accepts only an import UUID. The browser may have the upload request UUID but never have received the import UUID. The service-only source registration RPC is not an operator recovery API and requires the original complete upload. Add an authenticated read-only lookup scoped to actual actor, original live session, current permissions and feature flag; nonexistent/foreign IDs must not reveal another import. It must return awaiting/failed/ready/committed states without starting an extraction.
2. **Return initial and latest revisions, plus exact request status.** The current read returns the latest preview and optional commit. It cannot reconstruct the initial AI confidence after a human review, and human PreviewReceipt has no review request UUID. A recovery response needs the immutable initial preview, latest preview, and an explicitly requested review/commit request's acknowledged/not-acknowledged/conflicting result. Validate every reference; a lookup must not grant permission to use a superseded revision.
3. **Do not invent missing request payloads.** An unacknowledged review can contain unsaved edits that disappeared on reload. Current commit requires title/reason and records only an input hash plus final response, so an unacknowledged create request cannot be recreated byte-for-byte from current read data. A completed request can be acknowledged from its server receipt. An incomplete request must remain disabled until the operator explicitly abandons it and starts a newly affirmed request from verified server state. If exact continuation across reload is a product requirement, add a separately authorized server-side pending-intent mechanism and a reference-only idempotent execution API; do not reuse an old request UUID with reconstructed inputs.
4. **Bound cross-tab behavior.** Server ownership/revision/idempotency constraints remain authoritative. Add same-session tab coordination and stale-operation tests, but do not rely on a browser message or cache epoch as server authorization. A second tab's consumed import must return its saved outcome and block new submissions.

These are future additive contracts and acceptance requirements, not changes to migration142. Names/signatures must be coordinated with the SQL/Edge owners before implementation.

## Acceptance tests required before enabling persistence

- Reload before initial upload ACK, during provider attempt, after saved review, during commit and after committed ACK.
- Lost request response followed by the same or another tab; exactly one provider attempt/commit, no replacement payload under an existing UUID.
- Modified bookmark, another deployment, another actor, same actor/new session, A→B→A session events, actual revocation and expiry; no private rows before authorized read.
- Same-session token refresh pins the newly captured token for each read and fences late results.
- Original AI receipt/confidence is retained; missing original source is explicit; resumed review requires every page and a fresh affirmation.
- Storage inspection proves no raw source, roster PII, title/reason or tokens; failed reads never enable writes or fabricate success.
