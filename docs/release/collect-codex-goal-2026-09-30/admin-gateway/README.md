# SMS Gateway Admin operations — implementation evidence

Status: implementation and focused verification; production acceptance remains open. This packet
belongs to C14 and is outside the previously retained snapshot02 builds.

The page at `/admin/sms-gateway` uses Collect's shared theme, Admin shell,
visible status labels and Africa/Kigali timestamps. The owner-selected
[revolut-design skill](</Volumes/PRO-G40/Application Data/Codex/Codex-Home/skills/revolut-design/SKILL.md>)
is the sole visual authority. Its brand adaptation, DESIGN, Business/operator
web patterns and component contracts were read. The actual inspected official
Business image was
`/Users/jeanbosco/Documents/ChatGPT/Revolut/assets/public-business/enterprise.png`.
It is a static dark promotional composition; authenticated desktop geometry,
light state and live interactions remain unverified. Captures here are Collect
implementation evidence, never a competing design specification.

The device foundation is documented in
[the identity contract](../android-gateway-identity/CONTRACT.md). Device
enrollment, activation and revocation have distinct immutable action receipts.
An active identity and a heartbeat do not create dispatch authority or establish
physical delivery. Public identity review accepts only the exact handset v1
document, validates its public-key structure/hash and preserves the reviewed
installation/key/certificate fingerprints. The backend remains authority for
key validity and owner permission.

The strict wire contract is
[gateway Admin v1](../gateway-admin/CONTRACT.md), with the source schema at
`contracts/collect-admin-gateway-v1.schema.json`. The two authenticated reads are
`admin_list_gateway_devices_v1` (paired enrollment timestamp/device UUID cursor)
and `admin_get_gateway_owner_request_v1` (exact original request UUID). List and
request samples expire after 60 seconds. Handset observations independently
expire at `min(reported_at, ingested_at) + 120 seconds`; a read never renews them.
False, unknown, expired and absent reports remain distinct. Both read permissions
are checked before requests; actual current approved owner authority is checked
by the locked server contract. Read permission alone exposes no device changes.

Enrollment reviews the public key, installation and certificate fingerprints.
Activation and revocation review the pinned device and original request UUID.
Before submission, the UI rechecks current Admin identity, permissions, session
and sample freshness. The SDK fences each request and validates exact typed
receipts. Mutations have no automatic transport retry. A response interruption
retains the original UUID in-page, blocks additional changes and offers an
actor-bound read-only lookup. Unknown is uncertainty, not proof of failure.
Recorded results describe action time; the page refreshes actual device state
instead of changing it optimistically. Reload recovery uses the persisted last
owner action UUID in device evidence and original-request lookup. This page does
not persist credentials, original receipt bodies or destinations in the browser.

The canonical server navigation migration preserves changed/disabled entries;
the local fallback includes the route only when no server configuration exists.
A configured empty menu stays empty. The `router` icon from the server maps to
the existing gateway icon. Direct-route denial names both required reads.

Retained [backend UAT](../gateway-admin/README.md) passed 84/84 after
all 163 captured prerequisites. Its empty/pending/active/revoked/request outputs
pass the Dart DTO. These are actual SQL outputs from an isolated synthetic
database, including two synthetic raw OS callback records; they are not physical
handset or carrier evidence.

The five owned suites have 69 distinct cases passing across the retained scoped
runs, including SDK session fences, both read-denial gates, exact action receipts,
uncertain original-request reconciliation and actual isolated SQL outputs. The
15-file analysis had zero production diagnostics and two corrected test-only
lints; the affected-file recheck is clean. The sole-authority check passed.
Focused checks, raw failed attempts and capture hashes are recorded in
`validation.json`. These results are scoped verification, not a single combined
69-case run or global acceptance. Dark/light 1440×2200 captures use bundled Inter/MaterialIcons
and the actual Collect logo. Both were visually inspected; the selected route,
independent observation labels and action-time evidence are readable. Compact
320px layouts with doubled text expose visible controls and reviewed enrollment.
Widget semantics and responsive checks do not establish real browser keyboard,
VoiceOver/TalkBack or authenticated comparator acceptance.

Pending acceptance includes the later exact candidate build binding; hosted
migration/Auth/navigation contract readback; controlled real owner/device
enrollment and key possession; signed Android installation and permission/SIM/
network/pause lifecycle checks; browser/PWA keyboard, reader, deep-link and
responsive route/state acceptance; and the appropriate authenticated reference
comparator. Dispatch authority, governed run/policy/cap controls and actual
carrier outcomes remain separate future services. No live send, account
provisioning, OTP request, hosted deployment, production mutation or commit was
performed by this UI stage. Sole-authority hygiene is not visual fidelity or
whole-Collect production acceptance.
