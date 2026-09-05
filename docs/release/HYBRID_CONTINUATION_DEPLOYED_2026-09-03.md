# Collect continuation: deployed Admin and connected queue monitor

**4 September Kigali continuation:** the earlier MCP access-only session has
expired and current queue reads are blocked. Keychain-based opt-in renewal is
implemented and locally tested; fresh OTP provisioning and live rotation are
still open. Pixel RECEIVE_SMS remains granted. The mobile production-design
gate is blocked independently. See [current renewal and remaining-gate evidence](HYBRID_SESSION_RENEWAL_2026-09-04.md).

Observed: 3 September 2026, evening UTC. User expressly reconfirmed full authority
to proceed and choose from the existing configuration. Additional approval for
ordinary scoped deployment/configuration is not a remaining gate.

Latest device continuation: **native SMS opt-in PASS**. The Pixel was back in
Collect, the in-app receipt-only disclosure and Android permission dialog were
completed, and the app now shows `MoMo receipt SMS: Allowed`. Package readback
confirms `RECEIVE_SMS: granted=true`, with neither `READ_SMS` nor `SEND_SMS`
requested. The generic Android permission dialog's send/view wording does not
add those undeclared permissions. Backend consent for Collect ID 956974 is
`enabled=true`, recorded at **2026-09-03T20:54:54.248749Z**, channel
`android_sms_access`, device label `flutter_app`. Notifications/camera permission
were left unchanged. The [actual device screenshot](/Volumes/PRO-G40/COOL/.cache/hybrid-hosted-uat-20260903/screenshots/10-pixel-sms-consent-enabled.png)
was opened and inspected.

No feature flag changed: Android SMS access was already enabled; the four
`hybrid_*` flags and `native_sms_attestation_enforcement` remain false. Device
subscription metadata did not expose phone-number values, so the Pixel's link
to merchant code 41258 remains **unverified**. Permission/consent is not proof of
receiving the correct line's SMS, a valid attestation, posting, or delivery.

## Completed

- Applied `20260903200322_hybrid_directory_presentation.sql` using the existing
  authenticated owner CLI over the supported HTTPS Management route. Production
  is now **121 migrations**. The exact source SHA-256 is
  `2909300e938a4f09012e025c7d22136953ff53ffd9c4713662a9bc33ffc5c4c1`.
- The atomic transaction protected 15 member, role, approval, collection,
  receipt, flag and financial relations against changes and retained both
  function ACLs/owners. Its wrapper also passed in the isolated local database.
  Existing function definitions were saved for forward restoration. No monetary,
  role, approval or customer-record change occurred.
- Built real production assets, not the evidence-mode preview. Deployed Admin
  Worker `1b868d4f-1da5-4ecd-8d41-323616b87110`; independent readback confirms 100%
  traffic and deployment `c56f2424-7187-4a5e-8e4d-8a50f97a4c78`.
- Custom-domain live gate PASS. Exact remote/local matches:

  | Asset | SHA-256 |
  | --- | --- |
  | main.dart.js | `7ef5afc0decf12488a0523bd806e752323c4f02bec58689151522b827c8b3be3` |
  | custom-sw.js | `3aa2b610e066a5aa76c9a78d55ce346011a9dd03a578459e3876d52a90a4b848` |
  | flutter_bootstrap.js | `0a3b79bac16141f487369d1e54094a8ecfbfdd59ae81581071831612fb55006e` |
  | manifest.json | `65ceb8861614591828d638d720df08496c8e250138d8c9b6ed149f2d18261eb9` |

- Authenticated hosted Members now shows Collect IDs, app account state, masked
  contacts and two effective Admins. Admin users independently shows two records.
  The existing browser initially served its old cached bundle; a second reload
  after service-worker activation displayed the new version. The exact saved
  [production screenshot](/Volumes/PRO-G40/COOL/.cache/hybrid-hosted-uat-20260903/screenshots/08-deployed-member-directory.png)
  was opened and inspected.
- Security advisors before/after: 190 WARN, 46 INFO, no ERROR, **zero new items**.
  Existing findings are not certified resolved by this patch.
- The approved second operator completed a separate normal WhatsApp OTP login
  for MCP. A dedicated, device-local macOS Keychain item holds the short-lived
  user access token and public configuration; no token is in Git, logs, command
  arguments, or the host configuration. No browser token extraction occurred.
- Independent Keychain-backed process preflight and actual stdio MCP
  initialize/health/list both PASS. Queue disabled, zero pending jobs, zero
  send-started/uncertain attempts, zero provider sends or queue mutations.
- TypeScript check and **17 MCP tests PASS**, including real stdio transport,
  missing/expired/wrong-project/service-role rejection and sanitized Auth errors.
- Existing one-minute `Collect feature-phone receipts` heartbeat is **ACTIVE,
  READ-ONLY, NO-SEND**. Only health/list tools remain enabled. It stays quiet
  without meaningful change and can use the audited stdio preflight if this
  task's tool inventory has not refreshed. No new automation was duplicated.
- Hosted assisted-group form opens with the offline-identity explanation and a
  disabled final-create action until roster review. Empty preview submission
  shows field-specific name/reason errors. Cancelled without creating records;
  this is validation-only evidence, not live AI extraction acceptance. The
  deployed Admin browser returned no console error entries in the final check.
  Source inspection confirms the hosted AI preview itself is behind the same
  global onboarding flag as roster creation. It was not bypassed or enabled
  merely for a preview test while the physical pilot is not ready.

The saved session deliberately does not retain a refresh token. Expiry requires
normal reauthentication; the monitor reports the first expiry rather than
retrying or asking every minute. Durable unattended credential renewal remains
an operational improvement, not something established by this session test.

## Pilot choices resolved from records

- Receiving route: public **Buri Munsi**, MoMo merchant code **41258**, payee
  IKANISA LTD. Collect group `161b9af0-3b64-47b4-958a-2a8d4ca7db99`, receiver
  `8499a65c-0179-4e63-b0f9-aaa3ec7f6143`.
- Do not confuse it with private **BuriMunsi**, which uses code **2209724**.
- Legacy source: Buri Munsi v10 production sheet, group `GRPYTKHETMVC`.
- Only one complete registered destination exists there: the owner's number
  ending **7816**. It is already an authenticated Collect app member, so it is
  suitable for app-channel/suppression or an explicitly confirmed carrier test,
  **not proof of an account-independent feature-phone journey**.
- The other member has only last-three **716**, no full destination or reliable
  member name. Neither the full number nor a false offline identity was invented.
- Collect currently has no active members in that public group, no offline
  members, no notification jobs and no send attempts. No legacy balance or
  payment was copied into the financial ledger.

## Legacy handover decision

Both exact native services are loaded; nearby receiver health and source/runtime
parity PASS. Legacy dispatch is still send-capable despite its paused Codex
supervisor. Its configuration tightly couples capture with iPhone/Shortcuts
dispatch and does not currently offer a supported capture-only switch.

The bounded legacy Messages read found historical SENT, MIGRATED_UNSENT,
DESTINATION_REQUIRED and one READY_TO_SEND record from August. Treat all as
historical exclusions. SENT/Shortcut evidence is not new handset proof, and old
READY_TO_SEND must not become a fresh Collect notification.

Selected handover window: **immediately before the first fresh controlled
payment, after the receiving device can capture into Collect and the pilot
member's identity is valid**. At that point pause the two exact legacy services
and linked iPhone dispatch path, preserve their state/configuration, establish
a new-event watermark and verify a single sender before enabling Collect sends.
No further calendar choice is needed. Do not stop the only working intake path
while its replacement is not configured.

Read-only device inspection found a USB-connected Pixel 4a / Android 13 with
loaded SIMs and no Collect package. The already-built release APK was verified
against its approved evidence hash and then installed successfully:

- `app.cool.mobile`, version `1.2.4+23`.
- APK SHA-256 `b6fc920ebf786fe1216e243a62ed235c73dbf3ecdd12300366a8c86dcacbb6b6`.
- Signing certificate SHA-256 `9ee12172c78a8a487906d9159bfdd17b4d78aba3541f17b410659e6d60ddcc10`.
- Actual package/activity/version readback PASS; launch reaches native phone
  sign-in. The production variant already contains RECEIVE_SMS and excludes
  READ_SMS; an internal_receiver rebuild was not necessary.
- The route-owning approved Admin ending 7816 successfully completed the normal
  native WhatsApp login. An initial verification returned HTTP 403; clearing the
  code field and re-entering the same supplied code succeeded. No replacement
  OTP was requested. Native Home and profile readback confirmed Collect ID
  956974 and the registered Rwanda profile. The code was not saved in evidence.
- At that earlier installation stage RECEIVE_SMS was ungranted; no SMS, payment, SIM setting or legacy service
  change occurred. Before permission setup completed, the device visibly
  switched between screens and another application's foreground activity.
  Further taps stopped to avoid acting in the wrong application; the operator
  was asked to leave the Pixel untouched for the remaining setup. This is a
  shared-device interaction conflict, not evidence of a Collect routing defect.

The Flutter release-readiness skill guided package/hash/permission separation.
Its two optional linked mobile umbrella/QA files are unavailable; the complete
installed Flutter standards and existing repository/device tools were used.

## Still unproven, without blocking independent work

Receiving-line identity and fresh capture (installation, native login and SMS
permission/backend consent now PASS); a real
feature-phone member's complete registered identity; actual payment allocation
and balance snapshots; single-sender cutover; exact assisted send and physical
handset receipt. Hosted assisted-import/AI evaluation, durable session renewal,
and the separate Git/store publication chain also remain distinct work.
The four hybrid flags plus native attestation enforcement remain OFF and no real receipt SMS was sent. This report
establishes deployment and authenticated monitoring, not full production GO.
