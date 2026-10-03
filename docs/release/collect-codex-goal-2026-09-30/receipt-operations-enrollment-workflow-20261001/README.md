# Receipt-operations identity and local profile workflow

This is a focused implementation packet for the deadline-bound v3 owner APIs and
usable local enrollment/profile CLI. It does not attest a whole release candidate,
hosted enrollment, hardware possession, scheduler activation or SMS sending.

The guided flow retains explicit original enroll/proof/activate UUIDs, fsynced
private evidence before transport, and one mutation attempt per original. It
publishes an exclusive 0600 profile only after signed key possession and fresh
active identity validation. Original-request lookup permits reauthentication by
the same owner, but no blind replay; an absent lookup closes evidence only after
the retained server-enforced original deadline. Current identity and directory
reads expose bounded redacted metadata with a 60-second sample TTL.

Revocation uses the ordinary current owner session, the original principal/key,
a retained 90-second deadline and an immutable reason digest. It does not execute
the possibly compromised signer. The CLI supports both a published profile and
an explicit principal/fingerprint when enrollment is pending or activation is
stalled. Expired pending/active identities remain revocable. Replacement keys
require a distinct explicit UUID tag; default and old keys remain intact. The
existing direct helper delete-local command is preserved for compatibility and
was never invoked by this workflow or tests. No automatic deletion, overwrite,
key reuse, policy migration, scheduler startup or host allowlist widening occurs.

Use the exact command/prerequisite guide at
`tools/collect-notification-mcp/ENROLLMENT.md`. The six backend RPCs and wire
projections are bound by the current enrollment contract module and the actual
isolated SQL fixtures under `sql/attempt3/observed-*.json`. They require current
verified email-owner/session authority and existing management permissions;
local token parsing is hygiene, not the authority decision.

## Actual focused results

- **180/180 Node tests** across nine current non-history unattended consumer files;
  102 copied source inputs, dependencies and tools were stable/read back. The
  source includes the pending revocation variant and replacement-tag propagation.
- **TypeScript exit 0**, associated from the actual attempt3 command/log after
  exact 101 prior input, dependency and Node hash readback. It was not rerun.
- **Swift compilation exit 0** with explicit installed MacOSX27.0 SDK and
  **24/24** synthetic envelope/tag self-test checks. No Keychain API was called.
- **92/92 isolated SQL cases**, with unchanged source08 177 prerequisites plus
  current111000 and new180000. The task-owned network-none PostgreSQL17.6
  container was removed. SQL claims were injected synthetic authority; no Auth
  provider or hosted JWT verification was claimed. The separate SQL leaf has
  1,147 files independently hashed/read back with no mismatch.

Actual software-P256 Edge verification is exercised by Node tests; eleven Node
checks parse real output from the isolated SQL API calls. These are separate
local proofs, not a hosted Edge/PostgREST/GoTrue/hardware acceptance run. Test
counts from different scopes and predecessors are not added.

## Retained incomplete attempts and limits

The first runner setup selected a nonexistent npm lock; it was corrected to the
existing pnpm lock and the setup failure is retained. Two combined runs then hit
180/360-second limits in long unchanged history filesystem tests. Both retain
raw partial logs, copied inputs and unchanged-source receipts; neither is a
current aggregate pass. The focused 180-case run succeeded but its first Swift
command could not resolve the SDK in a clean environment. A separate explicit
SDK compile/self-test passed, associated to those unchanged successful Node
inputs. No successful Node or TypeScript checks were repeated for that SDK fix.

The prior146 history packet remains historical. Full current history/candidate
regression is open because signer/profile transitive inputs changed. The actual
Secure Enclave key/enrollment/rotation/revocation drill, hosted current-owner
installation, Admin identity workflow integration, real policy/allowlist/cap and
scheduler activation, complete current migration/candidate acceptance, device
and carrier proof remain outside this packet. The existing installed host MCP
profile was not changed; no live send or operational activation was performed.

`completion.json` gives precise receipts/source hashes and remaining gates.
`MANIFEST.json` binds this parent leaf and the separate SQL seal references;
`sql/evidence-seal.json` independently binds the SQL subleaf. Work authorization
is recorded separately from artifact-specific approval and production readiness.
