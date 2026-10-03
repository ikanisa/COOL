# Android gateway identity foundation

**86/86 isolated SQL cases and 36/36 Edge tests passed.** The Edge index also
type-checks. The disposable database was removed. This is local source and
synthetic evidence; public deployment, real enrollment, app signing/attestation,
physical gateway/provider/carrier and live operator acceptance remain pending.

The additive CLI-created migration retains pending/active/revoked device
identity, installation UUID, exact DER P-256 SPKI key/SHA and certificate SHA.
Enrollment checks the actual public curve point; activation additionally needs
recent service-verified key-possession health and current owner authority.
Owner checks call the shared locked authority helper, allowing the separate
email cutover to preserve session/grant/approval safety without gateway-specific
phone rules. The certificate SHA is an owner-pinned identity declaration,
not independent proof of an Android application certificate.

Private tables have RLS and no direct API grants. The handset receives no
Collect Auth role, password, token or service key. The Edge signature boundary
selects only five narrow service RPCs. It enforces POST, at most 8KiB exact UTF8,
duplicate-key rejection, fixed envelope/actions/payload keys, recent UTC time,
SPKI header/hash matching, canonical DER ECDSA conversion and P-256/SHA256
verification over the original bytes, server-derived request digest, bounded
body/RPC deadlines, safe errors, no-store responses and strict nested outbound
key validation. Original messages/destinations and keys are never logged or
returned by the device endpoint.

Health rows retain reported and ingested times, permission/network/telephony,
SIM selection/revision and local pause as device observations. Service requests
are immutable, digest/input bound and reconcile by their original UUID. A
revoked device cannot submit new health or obtain dispatch authority. It can
reconcile prior requests and record callbacks for an earlier arm bound to its
attempt, fence, body/destination hashes and segment count. Segment callbacks
retain raw OS result and optional TP status; they do not set receipt/attempt
outcomes or claim carrier delivery.

**Dispatch remains unavailable.** `gateway_dispatch_grant_v1` records
`GATEWAY_DISPATCH_AUTHORITY_PENDING`, exposes no body/destination/grant and
creates no arm. No public function can create an arm. A future reviewed
run/policy/cap/eligibility authority stage is still required. Activation of an
identity cannot open that dispatch boundary.

SQL tests use the exact retained schema153 dump and reconstructed API ACLs in
a guarded local container with cron/network execution disabled. They cover
nonempty prior accounting/receipt/pre-send attempt data, current authority,
key/certificate/request conflicts, invalid P-256 points, freshness, typed health,
replay/reconciliation/cross-device isolation, missing/wrong prior arms,
concurrent heartbeat/callback duplicates, callback rollback, paused/revoked
late callbacks, retained evidence and original-session deletion. Sixteen
business-table fingerprints remain byte-for-byte unchanged throughout gateway
work. A synthetic arm is inserted only by the isolated fixture owner to test
historical reconciliation; it is not a released sender capability.

The 36 Edge tests generate actual synthetic cryptographic key pairs and cover
valid signatures, byte tampering/wrong keys, canonical/nonminimal DER,
expiry/hostile input, duplicate keys, bounded UTF8/body/deadlines, state/refusal,
safe unknown outcomes and outbound redaction. Database tests trust the service
signature boundary; they do not independently verify device signatures.
No real device/key, signed GoTrue session, carrier/provider operation, full
hosted upgrade, clean install, load/SLO or physical power/network-loss scenario
is accepted by these scoped checks. The source153 authority fixture precedes
the separately tested operator email cutover; current interface compatibility
is preserved but not asserted as a live sign-in result.

`CONTRACT.md` specifies the exact wire, RPC DTOs and refusal/reconciliation
semantics. `result.json`, raw SQL/DB/concurrency/install logs, actual observed
fixtures and Edge check logs retain the evidence. `MANIFEST.json` binds final
source/evidence hashes. Earlier attempt1 remains in `.cache` for diagnostics;
attempt2 adds concurrent duplicate-request/callback and rollback checks.
