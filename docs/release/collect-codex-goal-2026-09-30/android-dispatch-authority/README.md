# Android dispatch and callback authority — local evidence

The selected migration implements separate automatic attempts, backend-derived
receipt grants, a final signed arm after the handset's durable reservation, and
immutable multipart callback observations. It does not create assisted human
approvals. Defaults remain Paused. No hosted configuration, device activation,
carrier call or SMS was performed.

The final unchanged-source checks are:

- `backend-uat/result.json`: 55/55 SQL checks on a disposable network-none PG17.6
  container. Its `task_container_removed` evidence is true; direct ID readback
  also found no container. Cron launches and pg_net processing were disabled.
- `native-uat/validation.json` and `tests.stdout`: 126/126 JVM tests, plus
  compilation against the actual Android36 API. Source and cached binary drift
  lists are empty. Tests use synthetic keys/AES and narrow filesystem shims;
  they do not exercise Android Keystore, physical power loss or SmsManager.
- `edge-uat/result.json`: 109/109 offline signed-handler tests, including ten
  tests using actual synthetic SQL results copied unchanged into the contract
  fixtures. The handler and new tests pass lint. No HTTP request left the
  process. SQL authority and signature verification are separate local proofs.

The SQL fixture replayed the exact 177 app migrations retained in source08,
then stable `20261001110000_receipt_operational_authority.sql` and the new
`20261001130000_android_dispatch_authority.sql`. This is a focused composition,
not current whole-chain or hosted upgrade acceptance. The row-free platform
bootstrap mocks Auth shape, normalizes local installer ownership, and contains
no source identities or credentials. Local PG17.6 is not hosted runtime/security
acceptance.

The nonempty fixture proves preservation of payments, balanced journals,
snapshots, member/group balances, lifetime primary identity and immutable
receipt body/contact/hash. Actual concurrent grants reserve one lifetime
attempt. Assisted claim and cancellation cannot overlap that reservation.
Grant and final arm reject stopped policy, stale run/fence, paused SMS, revoked
consent, changed contact/SIM and unavailable device health. A locked financial
source refuses before authority rather than waiting into a send race.

The handset validates the initial grant, commits its invocation reservation,
obtains and verifies the original arm ACK, rechecks local pause/health/expiry,
and invokes once. Lost, replayed or mismatched acknowledgements preserve
uncertainty. Original-request lookup never recovers body or an invocation
permit. Callback observations remain reconcilable after stop, expiry and
revocation; contradictory SENT evidence folds irreversibly to uncertain.
`observed_sent` means framework observations, not carrier or delivery proof.

Prior failed SQL attempts1–4, accepted preceding-byte attempts5/7, interrupted
duplicate attempt6, and the first Edge lint attempt remain under
`prior-diagnostics/`. The Edge lint failure is a preexisting `require-await`
warning in unchanged `handler_test.ts`; final lint covers the handler and new
tests while all existing behavioral tests run. Worker timeout/cancellation
observations are retained and superseded by the final native suite.

Remaining work is explicit: background Bridge/service scheduling; separate
Admin automatic-attempt timeline; missing-callback timeout/manual closure;
terminal attempt ACK and late-callback-safe archival/export; physical handset,
carrier, restart and power-loss verification; deployment and exact current
source/build/release acceptance. `terminal_archive_ack` and `carrier_proof`
remain false. Missing callbacks retain send_started/unknown evidence and never
authorize a retry. Source08 and this packet are historical retained bytes as
later implementation continues.

`completion.json`, execution bindings, retained executable inputs, raw query/
install logs and observed fixtures describe the exact scope. `MANIFEST.json`
binds the packet files; it is integrity evidence, not release authorization.
