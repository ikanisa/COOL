# Default privacy route integration — scoped local acceptance

The actual default repository and guarded router now retain a previously
profile-verified owner's deletion-request form while the same SDK owner renews
the Auth session and native/cache/member rereads are pending. Verified code and
selected reason survive the renewal; explicit confirmation produces the own
pending-review intake receipt. Logout, owner replacement and denied refreshed
member access remove the old form and prevent its submission. A deliberate
fresh entry for the new owner starts an unverified form without inherited reasons.

The original source genuinely failed: holding native synchronization after OTP
renewal sent the form to Auth and disposed it, then resumed to Home. Root reviewed
and corrected production router/repository behavior. Intermediate real failures
also exposed build-phase notification churn and stale encoded privacy requests
reopening for a replacement owner. The focused requested/settled URI diagnostic
preserves the causal sequence. All six behavior attempts use exactly the same
original assertion source; temporary diagnostic code is retained separately and
absent from final production. The final test differs only by braces, an explicit
diagnostic-print import and its lint-safe print call.

| Actual execution | Result | Bound inputs |
| --- | --- | --- |
| Old source, attempt 1 | 3 pass / 1 fail | 587, unchanged |
| Reviewed corrections, attempts 2–5 | Preserved failures; not acceptance | 587 each, unchanged |
| Focused owner-switch diagnostic | 1 intentional observed failure | 587, unchanged |
| Final causal correction, attempt 6 | 4 / 4 pass | 587, unchanged |
| Maintained ten-file consumers | 134 pass / 2 Security-heading failures | 1,344, unchanged |
| Exact real-cache Home stale-pill consumer | 1 / 1 pass | 1,344, unchanged |
| Post-heading affected chrome/header/default-route replay | 37 / 37 pass | 1,345, unchanged |
| Final focused analyzer | Exit 0, no issues | 1,345, unchanged |
| Actual post-heading design-authority hygiene | Exit 0, pass | 1,345, unchanged |

The two broader failures were the existing custom Security header missing heading
level 1. Root added only `headingLevel: 1` under its existing header semantics,
with no layout change. The affected replay includes all six maintained header
tests and the four default-route cases. The prior 134 passes remain evidence
of their executed source; this packet does not claim a fresh 136-case full run.
The pre-heading real-cache pass is retained with that exact source distinction.

The new test uses the actual default repository/provider, guarded app router,
autoDispose controller, locked Auth/PostgREST SDK and a genuine loopback WebSocket.
Native method replies, HTTP responses, environment keys, identities and receipt
records are synthetic. Financial repository, guard, subject authority and
controller are not replaced, manually set or artificially retained. Existing
assertions and framework errors were not filtered or suppressed.

Production changes belong to root. This subagent owns only the new test and
this evidence packet. See `post-header-source-delta.json` for the sole final
header amendment and the explicitly bound verifier/test-input extension;
`final-runtime-source-delta.json` covers the reviewed router/repository/scaffold
correction. `final-source-readback.json` re-reads every final bound input.

Acceptance is limited to these local default privacy-route consumers. Native
bridge/encryption/signing, hosted Auth/RLS, legal authority and retention,
actual erasure lifecycle, provider/device/store, rights, visual comparators and
full production/release acceptance remain open. Design-authority hygiene does
not establish visual fidelity. Prior public-media-batch3 remains a dated proof;
these production and registry-binding changes require a fresh final public
media/source/browser proof. No deployment or external service action occurred.

Original compiler typo, lint diagnostics, runtime failures, source copies,
complete logs and before/after maps remain in this packet. Byte reconstruction
used only for two earlier verifier/test snapshots is explicitly SHA-verified
and is not represented as a new execution.
