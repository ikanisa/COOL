# SMS Gateway original-request recovery — later implementation evidence

Status: source correction and focused local verification passed. This is a later correction to the
earlier C14 packet; source05 and its configured build do not contain this change.
Production and visual acceptance remain open.

Before enrollment, activation or revocation, the Admin page saves and reads back
one bounded checkpoint in the current tab. The payload is only a hashed operator
binding for the fixed Collect project and gateway-review purpose, the original
action/request UUID, reviewed installation/device UUIDs and key/certificate
fingerprints. It excludes the original public SPKI, Auth identifiers/tokens,
contacts, credentials and message content. Enrollment's device UUID is still
unknown at submission; the exact immutable server result establishes it.

Current identity, session, permissions, a fresh device sample and reviewed
identity fingerprints are checked before the one mutation request. Unavailable
or corrupted storage prevents submission. A current owner/request match and
strict typed receipt are required to clear the saved reference. A changed saved
checkpoint cannot be removed by another response. Definite current service
refusal may clear its matching unsent/refused reference; unknown transport,
malformed receipt, departed-session or storage-clear failures retain it.

The browser uses actual `EmptyLocalStorage` and `persistSession=false`, so a
reload requires fresh sign-in. The same operator may recover the opaque bookmark
afterward, but this restores no old authority or draft. Recovery requires a
manual actor-bound original-request read under the new current session. No
automatic lookup, mutation replay or background resend occurs. Another operator
cannot read the saved reference. Unknown, busy, stale or mismatched results do
not clear it. A recorded result must match the original action/request and all
reviewed immutable identity fingerprints before the explicit **Use recorded
result and refresh** control can clear the bookmark and reread device state.

The checkpoint is a same-tab recovery mechanism, not cross-device storage.
Closing the tab, changing browser origin or clearing its sessionStorage may lose
the bookmark. Actual hosted sign-in/reload, installed browser and reader tasks
remain acceptance work; a synthetic widget session and real adapter recreation
are narrower evidence.

The existing v1 device/read/receipt contract and permission fences remain in
force. Backend read-only review found no material mismatch. Device observations,
active identity, raw OS callbacks and the independent pending dispatch authority
retain their meaning; recovery creates no dispatch or physical delivery claim.
No SQL/native source, Auth persistence, send service or business mutation beyond
the existing concretely reviewed owner identity action is introduced.

The selected [revolut-design skill](</Volumes/PRO-G40/Application Data/Codex/Codex-Home/skills/revolut-design/SKILL.md>)
is the sole design authority. This narrow state uses existing Collect tokens,
Admin components, accessible visible labels and the inspected static Business
reference described in the earlier packet. Synthetic dark/light captures are
implementation evidence. Authenticated source comparisons, actual browser
keyboard/reader workflows, hosted migration/menu/Auth checks, governed real
owner/device handling and a later exact candidate build remain open. No live
send, OTP, provisioning, hosted deployment, production action or commit was
performed by these tests.

## Actual scoped checks

`models-page-final.log` is one all-pass current 52-case run: 13 strict checkpoint
cases and 39 gateway page cases, including the new recovery paths, original
response/session fencing, storage failure/readback corruption, same-owner fresh
sign-in, owner isolation, busy/unknown results, changed bookmark preservation,
failed storage clearance, dark/light captures and 320-pixel doubled-text layouts.
`browser-checkpoint-tests.log` passed 1/1 using the actual browser sessionStorage
adapter in an isolated headless Chrome profile. This proves adapter recreation
and owner separation, not a hosted sign-in/reload acceptance task.

The first scoped run passed all 65 existing actual SDK UI regression cases and
13 model cases; its page file failed to load because a fixture used an instance
property as a const default. `vm-tests-attempt1.log` retains that failed run.
The next model/page run passed 49/52; two tests reused one disposed session
controller between containers, and another sampled before its dialog close
transition. `models-page-attempt2.log` retains those fixture failures. Separate
fresh session controllers and settled submission boundaries corrected them;
the final 52-case run then passed. No failing attempt is counted as all-pass.

After the final checkpoint-clearance guard, `sdk-clearance-final.log` passed
14/14 affected actual SDK UI cases covering exact success, departed-session
responses and invalid/private receipt evidence. These overlap the earlier 65
regression cases; they are not 14 additional cases. There are 118 distinct scoped
cases across the retained passing subsets (52 + 65 + 1), not a single 118-case
run. The complete 65-case SDK matrix was not rerun after the final guard; its
affected 14-case subset was. `analysis-current.log` reports no issues across ten
files, and `design-authority.log` reports sole-authority hygiene PASS. Earlier
style information remains in the attempted analysis logs.

The two 1440-by-2200 recovery captures use the actual Collect logo, Inter and
MaterialIcons with settled transitions. Both were inspected: the original
request and manual lookup are visible, device changes stay disabled, independent
observations retain their values, and no desktop overflow was observed. The
source/evidence bindings and acceptance limits are in `validation.json` and
`MANIFEST.sha256`. Shared-file hashes record a point-in-time observation in the
concurrent checkout, not a reviewed freeze. The earlier C14 packet is annotated
by its additive `LATER_SCOPE_NOTICE.md`; its original evidence remains intact.
