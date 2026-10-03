# Admin exception inbox — implementation evidence

Status: source implementation and focused local verification passed. Production,
browser/reference and whole-Collect acceptance remain open. This C12 source is
later than retained implementation source05; that checkpoint/build cannot accept
this later workflow.

The canonical `/admin/exceptions` page uses Collect's shared Admin shell,
components, theme adapters and explicit Africa/Kigali observation times. The
owner-selected [revolut-design skill](</Volumes/PRO-G40/Application Data/Codex/Codex-Home/skills/revolut-design/SKILL.md>)
is the sole design authority. Brand adaptation, DESIGN, Business/operator web
patterns and component contracts were applied. The inspected official Business
image was `/Users/jeanbosco/Documents/ChatGPT/Revolut/assets/public-business/enterprise.png`.
It is a static dark composition; authenticated geometry, light interactions and
route/state comparators remain unverified. Collect captures are implementation
evidence, not an additional visual specification.

## Actual contract and limits

The [published v2 contract](../exception-reads-v2/CONTRACT.md) and
`contracts/collect-admin-exception-v2.schema.json` are the wire authority for
data, permissions and supported actions. The list has server-side Active/Cleared
and source-category filters, paired changed-at/exception-ID pagination, a
60-second read TTL and explicit platform scope. It returns no overall count.
Rows retain their original observation times and strict immutable revision
identity. Read freshness does not rescan sources or renew their observation.
`source_scan_complete=false` is displayed; an empty inbox never attests that all
operations are healthy or that historical sources have been scanned.

Raw SMS links use their own accepted SMS ID. Allocation and payment links use
only the nullable server-derived SMS ID; their distinct IDs are never substituted
into transaction routes. Receipts link to their actual receipt detail. Gateway
observations expose their exact device source ID and link to the existing SMS
Gateway operations page; there is no invented device-detail endpoint. A missing
supported investigation link remains explicit.

Read access independently requires payments.read, notifications.read and
system_health.read. Mutations additionally require notifications.manage and a
fresh visible revision. The locked server validates current approved owner and
JWT-bound session; the client does not infer authority from a role label.
Configured navigation and disabled/empty menus are preserved. The published
`warning_amber` icon uses the existing shared icon adapter.

## Human review and reload recovery

A concrete review binds exception ID, revision, closed reason code, action and
one original request UUID. The current identity/session, permissions and visible
source are rechecked before submission. The same-tab session-storage checkpoint
contains only bounded opaque request references, closed action/reason codes and
a hashed owner binding for the fixed Collect project and exception-review purpose. No actor identity, token, contact, raw SMS,
receipt body or free-text reason is stored. Checkpoint write and exact readback
must succeed before the action request; unavailable storage prevents submission.

Acknowledgment and escalation use the existing v1 action RPC once, with automatic
retry disabled. Exact typed receipts describe persisted human review. They do
not resolve a source, change finance, send a message or verify escalation
delivery. Current source state is reread after an acknowledgment instead of
being changed optimistically.

Interrupted outcomes retain the original checkpoint across a same-tab reload.
Recovery starts with an explicit actor-bound v2 lookup. Recorded receipt must
match request, exception, revision and action. Not-recorded, in-progress,
expired and bounded authority-busy outcomes keep the original request
unconfirmed. A lookup never automatically repeats a mutation. Different owner bindings cannot expose the old checkpoint. Browser Auth is
memory-only: a fresh same-owner sign-in may recover this opaque reference, but
the new session must pass current authority before its manual lookup; old
authorization is never resumed. This tab-scoped bookmark
is not a cross-device recovery mechanism.

## Evidence and remaining acceptance

The backend packet retains 87/87 actual isolated SQL cases and eight observed
responses from a synthetic database. Published bytes are bound to the tested
cached source without claiming an additional duplicated SQL run. These outputs
are input to strict Dart parser tests; they are not hosted, physical device,
provider or delivery evidence.

Focused verification covers 71 distinct cases: 33 strict model/actual-SQL-output
cases and nine pinned SDK/session cases passed in `vm-tests-attempt1.log`; the
corrected current page suite passed 28/28 in `page-tests-final.log`; the real
isolated browser sessionStorage adapter passed 1/1 in
`browser-checkpoint-tests.log`. This is coverage across scoped runs, not a single
71-case run. The current Admin/PWA and shared readability regression files also
passed 33/33 in `current-admin-regressions.log`, including light/dark 320-pixel
layouts at twice normal text size. The 15-file final scoped analysis passed with
no issues in `analysis-current.log`.

The initial VM run exposed a real modal/background progress interaction after
55 passing cases and was interrupted; `vm-tests-attempt1.log` is retained. The
subsequent page run passed 27/28 and exposed a test expectation still bound to
the old session-only recovery policy. Its raw `page-tests-attempt2.log`, the
targeted corrected same-owner test and the final full page run remain separate.
The first browser attempt failed because its Chrome path was absent;
`browser-checkpoint-attempt1.log` is retained. The passing browser run used the
installed Chrome for Testing executable and an isolated headless test profile,
without personal browser state or hosted sign-in. The first final analysis style
information is retained separately from the corrected no-issues result.

The 1440-by-2200 dark/light synthetic captures load the actual Collect logo,
bundled Inter and MaterialIcons, and settle implicit state transitions. Both
were visually inspected: no desktop overflow was observed, labels and selected
navigation are readable, and Refresh inbox is visibly enabled. A widget test
also clicks that control and proves rereading without writes. Synthetic captures
do not establish authenticated comparison, reader task completion or physical
device behavior. Source and evidence hashes are retained in `validation.json`
and `MANIFEST.sha256`; shared-file hashes record a point-in-time observation in
the concurrent checkout, not a reviewed freeze.
Actual browser keyboard/reader/deep-link and responsive route-state acceptance,
authenticated reference comparison, hosted migrations/navigation/Auth readback,
controlled operational handling and an exact later release candidate remain
open. No OTP, live send, provisioning, hosted deployment, production mutation or
commit belongs to this UI slice. Sole-authority hygiene does not certify visual
fidelity or global production acceptance.
