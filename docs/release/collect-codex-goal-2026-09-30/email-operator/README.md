# Email operator login and approval — local evidence

This stage implements passwordless email operator login, the versioned redacted
operator approval panel and the fixed-target MCP login CLI. Member phone Auth
and the legacy repository method signatures remain intact. This is local source
and scoped validation evidence; it does not approve a deployment or a whole
Collect release and is outside snapshot02.

The Admin form normalizes the email, requests a code with `create_user=false`,
binds verification/resend to that email, validates the six-digit code, and checks
the current approved Admin identity before navigation. The visible primary
action is **Send code**. Email keyboard/autofill, one-time-code autofill,
duplicate-request blocking, a disposed cooldown timer, safe errors, changing
email, denied approval, and recovery are exercised. A verified but unenrolled
account is signed out. The synthetic review account is
`operator@collect.example`; its explicit fixture banner states that no email is
sent. Synthetic operator list rows use UUID targets and do not label email as
a phone number.

The approval panel calls `admin_get_operator_approval_v1` with no legacy read
fallback. The exact DTO checks nullable fields, enums, target UUID, masked
identity, valid zoned timestamps and coherent approval/role/access flags. Email
approval and revocation use the new target-bound RPCs. Approval requires the
entered normalized email to match an existing verified Auth account, with a
reason of 8–500 characters; it does not enroll or create an account. Activation
and deactivation continue to use the existing separate role service. Self
changes are unavailable. The panel keeps legacy controls only for an explicit
WhatsApp provider in transition mode, rereads before a change and retains
current identity/session/dialog fences. Denial, unavailable service, pending
verification, expired/revoked/changed identity and legacy-disabled states remain
distinct. Only masked identity and Kigali approval times are displayed.

The CLI targets the owner-selected `info@ikanisa.com`. Public configuration is
read privately for the fixed project through locally verified Supabase CLI
**2.84.2**, pinned at
`/Volumes/PRO-G40/Development/User-Developer/supabase_2_84_2_codex/supabase`.
The Auth origin, no-redirect requests, deadlines and hidden terminal input are
preserved. Verification requires the fixed canonical email, a valid Auth UUID
and a matching JWT subject before backend preflight. Token interpretation is a
local binding check; backend preflight establishes current permission. No
credential or response identifier is printed or saved before that preflight;
guarded Keychain persistence remains unchanged. Tests use injected local
responses and never run the public-config command, send an OTP or sign in to
the configured service.

Validation:

- `approval-tests-final.log`: 21/21 exact-contract, permission, intent, session,
  real-SDK and responsive/capture cases passed. This includes cutover while a
  legacy approval dialog is open and distinct unavailable/denied responses.
- `login-tests-final.log`: 19/19 current login and recovery cases passed,
  including the final Send code label, both themes at 320px with 2× text, actual
  SDK request bodies, no account creation and the primary/loading contrast.
- `flutter-tests-attempt6.log`: the other 58 legacy-panel, localhost Auth
  transport and PWA cases passed. Two new approval test assertions failed in
  that wider run; their map-record matcher and chip-label expectations were
  corrected and the complete 21-case approval file passed afterward. Combined
  with the current 19-case login file this covers **98 distinct Flutter tests**
  across passing scoped runs, not one single green combined run.
- `cli-tests-final.log`: 5/5 pinned-origin, email-only request, fixed identity,
  no-request invalid token and redacted HTTP error tests passed.
- `cli-analysis-final.log`: TypeScript analysis passed.
- `analysis-final.log`: 16 scoped files analyzed with no issues.
- `design-authority-final.log`: sole revolut-design authority hygiene passed; it is
  not a visual-fidelity certificate.

Earlier failed attempts are retained. Analysis also detected that a necessary
shared runtime import had disappeared during concurrent work; only the owned
operator approval import was restored. The email-only loopback identity fixture
includes the required `phone_masked:null` key. Older PWA assertions requiring
icon-only headings were updated to visible headings and independent C10
verification/allocation/ledger/notification columns, and to the current RWF
formatter. An actual light login capture exposed an invisible black-on-black
primary label; the existing white token now supplies its enabled foreground and
the existing muted token supplies its disabled loading indicator.

The four PNGs are synthetic component renders with bundled Inter and
MaterialIcons, inspected for readable masked data, status, dates and actions.
The login captures are 1440×1000; approval captures are 1440×844. They do not
provide authenticated browser, hosted or screen-reader acceptance. The selected
revolut-design skill and its brand/DESIGN/web/operator references remain the sole
design authority. The inspected Business comparator is the public dark
illustration `/Users/jeanbosco/Documents/ChatGPT/Revolut/assets/public-business/enterprise.png`;
an exact authenticated login/approval and light-state comparator remains
unverified. No 100% match or visual percentage is claimed.

The parent's isolated [backend email/cutover packet](../email-auth/README.md)
passed 67 cases, including
current email-only authority and a blocked legacy-approval versus cutover lock
race. That is synthetic local database evidence, not actual operator
provisioning or a hosted sign-in. Migration installation, controlled enrollment
and approval of the real operator, email-only cutover, the approved email code
template/SMTP deployment and delivery, hosted/browser/keyboard/screen-reader
acceptance, a later exact source/build binding and release approval remain
pending. No OTP, SMS, hosted login, production mutation, deployment or commit
was performed in this UI/CLI slice.
