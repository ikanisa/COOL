# BE05 staged member fresh authentication and own-request recovery

Local source and acceptance packet, 2 October 2026 (Africa/Kigali). This slice
is implemented in new files and has not been wired into a member screen, router,
repository, logout flow or CI. Full BE05 remains open.

Final client attempt8 passed **84/84 visible tests**, no failures or skips,
and targeted Flutter analysis reported no issues. Tests used Flutter 3.44.4,
Dart 3.12.2, the actual local gotrue 2.27.1 implementation, pinned Supabase
Flutter 2.17.1/Supabase 2.16.0 and HTTP 1.6.0. Auth and PostgREST HTTP responses
were synthetic. No OTP, customer data or provider/network request was sent.
Exact source/dependency readbacks, commands and full JSON test output are retained.

SQL attempt1 passed the complete captured **202 migrations** through
`20261002042000`, the new 27-case own-current status fixture, the preserved
53-case intake fixture and the existing privacy lifecycle fixture. All 244 table
row snapshots were restored after each rollback. The before/after addition
catalog proves 717 existing application functions, 350 foreign keys, 221 table
ACL/RLS entries and all existing policies unchanged; only the new public wrapper
was added. Repeatable-read access fails with the existing 40001 fence. The
task-owned PostgreSQL 17.6 target had network disabled, no published ports,
cron disabled and pg_net batch size zero; removal and absence were verified.

This SQL proof uses a retained row-free Auth/storage schema, explicit local
installer/superuser normalization and synthetic injected JWT claims with actual
Auth session rows. It does not attest managed hosted installer privileges, signed
JWT admission, a GoTrue deployment, a storage provider or hosted migration parity.

## New public interfaces

`lib/features/privacy/privacy_contract.dart` provides a fixed error enum and
safe exception, bounded reason normalization, credential-free in-memory
`PrivacyPendingIdentity`, and the strict `PrivacyIntakeReceipt` parser. A receipt
can only represent `pending_review`; policy/scope review remain pending and all
erasure, restriction, Auth-removal, retention-approval and processor-start flags
must remain false. Private/extra/missing or inconsistent fields fail closed.
The identifier codec exists for typed in-memory handoff only; this implementation
persists neither it nor any draft, phone, reason, OTP or credential locally.

`privacy_session.dart` exposes `PrivacySessionAuthority.capture()`, synchronous
`adopt(original, verified)` and `invalidate()`. The installed
`GoTruePrivacySessionAuthority` observes the real pinned synchronous Auth stream
and tracks subject, SID and generation; queued event identities preserve account
switch/return evidence. A new subscription cannot adopt until an actual Auth
event has been observed, closing the initial ReplaySubject delivery gap. Capture
can start an explicit OTP send or status read before that barrier is ready.

Adoption requires the original subject/SID/generation to remain current, a
healthy authenticated non-anonymous returned session for the same subject, a
new SID, a refresh token and expiry more than 30 seconds ahead. The controller
also verifies the returned trusted Auth phone against the captured phone.
Local JWT parsing is only an ownership fence; Auth and SQL enforce authority.
The pinned nonexpired `recoverSession` branch installs synchronously, then the
ordinary signed-in event updates SDK persistence and member listeners. No AAL2,
platform-admin, roster-owner or service authority is substituted.

`privacy_transport.dart` provides `PrivacyRequestTransport` and
`SupabasePrivacyRequestTransport`. Send implements the pinned phone OTP body
with `create_user:false` (SDK `shouldCreateUser:false`), WhatsApp channel and the
captured existing Auth phone. Verify uses the pinned phone/SMS OTP body without
calling shared-client `verifyOTP` or constructing another Auth client. It returns
a candidate for guarded adoption; it cannot change live Auth during an await.
CAPTCHA is required when the existing environment enables it. HTTP uses captured
session tokens, fixed endpoint paths, redirects disabled, a 15-second deadline
with the pinned actual abortable request and a 64-KiB response bound. Errors
expose only fixed codes; provider bodies, OTPs and credentials are never logged.

`privacy_request_controller.dart` exposes `sendCode`, `verifyCode`, `submit`,
`retrySubmission`, `refreshStatus`, `cancel`, `dispose`, and read-only busy,
challenge, pending-identity, ambiguous-outcome and receipt state. Duplicate
concurrent actions fail. Every asynchronous operation is fenced against cancel,
disposal, Auth generation, account switch, logout and SID change. Cancellation
never signs out a newer session or claims to retract a server request.

`privacy_providers.dart` contains staged Riverpod providers for the authority,
transport and a view-owned auto-disposed controller. The controller watches and
binds the existing authenticated-user provider: an actual UID change disposes
and recreates it; same-owner OTP SID adoption retains it. Immediate live-owner
method and cached-state getter fences operate before async provider delivery.
There is no local-fixture
success fallback. These providers are not imported by existing routes/screens.

## RPC and recovery behavior

The existing `request_account_deletion_v1(p_request_id, p_reason)` remains the
write API. The client allocates one in-memory submission UUID per intent and
keeps it across ambiguous responses. Different payloads are refused locally;
server replay, canonical reuse and conflict rules remain authoritative. Writes
and OTP actions are explicit. No automatic write replay occurs after timeout,
cancel, restart, a gateway error or a malformed success.

After an ambiguous reply, `refreshStatus` reads the existing specific status API
using the stable submission UUID. An equivalent request may legitimately return
a different canonical UUID. An explicit retry preserves the original UUID and
normalized reason, and still needs the verified current SID. Cancellation drops
the raw in-memory reason, so that cancelled intent cannot silently resubmit.

The additive migration creates only
`public.get_current_account_deletion_request_status_v1() returns jsonb`.
It uses the effective live-session gate, finds the immutable private canonical
request by `auth.uid()`, and delegates to the established status wrapper. It
returns SQL null when that subject has no canonical intake record after the
live gate is rechecked. Only `authenticated` receives execute; PUBLIC, anon and
service role do not. Private table/helper ACLs and legitimate session-gated
legacy Admin support reads remain unchanged. No legacy newest-row heuristic
is used, and an Admin caller can only recover their own canonical request.

After restart the new own-current RPC recovers an accepted canonical receipt
without a local checkpoint. A null observation cannot prove that an in-flight
write was cancelled or failed. Unsent drafts and raw reasons are not restored;
the owner must explicitly enter a new intent and complete OTP verification.
The server's canonical uniqueness and conflict checks prevent another intent
from silently replacing an already accepted request. The client never writes
to the existing single-account protected financial snapshot or plaintext storage.

## Required integration boundary

Root owns existing deletion/settings screens, repository, router, startup,
logout and CI. Before route wiring, connect the staged controller to the actual
member surface and its existing CAPTCHA/shared components, call `refreshStatus`
for authoritative recovery, and retain server-confirmed `pending_review` wording.
Controller state needs ordinary view state updates around explicit awaits; the
plain controller is not itself a Flutter notifier.

**Call the authority's `invalidate()` before the first await of every local
logout or account-reset action.** GoTrue's completed sign-out stream cannot
announce a logout operation that has only just begun. The tests prove both this
start fence and actual completed sign-out handling. Cancel/dispose the view's
controller when its scope ends and recreate it for a different account. Never
remove a session in a stale verification catch block. Recheck the pinned Auth
adoption bridge when upgrading its SDK; do not use an awaited shared-client OTP
verify followed only by a UID comparison.

Existing `CollectRepository.requestAccountDeletion` and its original member
screen remain untouched, including the legacy void consumer. The old screen
has no new status/fresh-auth wiring yet. No migration was applied to hosted
infrastructure. Root must integrate, verify affected callers and independently
validate the required deployment/provider/device/route evidence before promoting
this staged slice.

## Retained diagnostic history

- Attempt1: observed 72 passing / 2 failing client tests; initial replay delivery
  and the synthetic logout fixture needed correction. Its tool-output observation
  is retained without claiming an immutable source snapshot or full transcript.
- Attempt2: full captured run retained; 73 passing / 1 failing expectation and
  14 brace lint infos. The new-SID fixture needed real ReplaySubject delivery
  before testing resumed access; source/test brace issues were fixed.
- Attempt3: captured 79-test pass and clean analyzer retained as prior evidence.
  It lacked the later same-tick initial-replay acceptance case.
- Focused attempt4: reproduced the real gap, allowing stale adoption before any
  initial Auth event delivery. Pre-fix source hashes and full failing output are
  retained. The authority barrier closes this gap.
- Attempt5: 81 passing tests, including same-tick adoption refusal both
  before initial replay and after stream priming, plus clean analysis and exact
  unchanged source/installed HTTP readbacks.
- Attempt6: 82 passing tests and clean analysis after adding live-owner fences
  to cached receipts/pending identity, preserving the account-segregation proof.
- Attempt7: 84 passing tests after adding actual Auth/Riverpod lifecycle checks;
  one brace lint info was retained and fixed.
- Final attempt8: 84 passing tests, clean analysis and unchanged exact input,
  installed HTTP and toolchain readbacks. Actual Auth UID changes, same-owner
  OTP SID retention and logout disposal are covered without real HTTP effects.

The packet enables intake/status mechanics only. Full evidence redaction,
principal/Auth removal, derivative and backup/processor erasure, legal holds,
retention approval, policy/scope review and a complete BE05 lifecycle are pending.
