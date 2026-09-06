# Developer account verification — 5 September 2026

Status: **Live mobile, Admin and Supabase data reconciled. Membership filtering
corrected and a source-bound Android QA candidate installed and signed in.
Mobile distribution remains blocked.**

## Live account and data checks

The owner supplied separate normal WhatsApp codes for mobile and Admin. Both
sign-ins succeeded for the registered developer account ending 7816. No static
code, session copying, impersonation or access-control change was used.

Admin's live Groups page returned five rows. Names, public/private status and
active member counts exactly matched the read-only Supabase query at
2026-09-05 10:27 UTC:

| Group | Visibility | Active members | Developer owns or belongs |
| --- | --- | ---: | --- |
| Buri Munsi | Public approved | 0 | Yes |
| Gikundiro | Public approved | 0 | Yes |
| Test Group | Private | 1 | Yes |
| dddddd | Private | 1 | Yes |
| BuriMunsi | Private | 1 | No |

The developer has a verified active platform-owner role, matching WhatsApp
approval and a fresh Admin session. This explains access to the fifth group's
private record through All Groups. The legacy profile admin flag is not the
current authorization authority. No broader permission was granted for QA.

All five canonical confirmed balances are RWF 0. Public ledger credits, posted
MoMo payments and reconciled bank payments also total zero for these groups;
the developer has no posted/reconciled payments. The signed-in mobile candidate
displayed matching zero totals and the truthful Activity empty state.
Test Group is a real database record; its name alone is not evidence of a
hardcoded runtime fixture.

The earlier retired-group audit found no matching live group, function or view
identity. The fresh APK and AAB were scanned again: no retired or synthetic QA
identity was present in any of their three native app binaries. Production
fixture mode is disabled. This targeted check does not imply that presentation
constants such as spacing or labels must be stored in Supabase.

## Membership correction

Live QA found that the Groups screen's My groups control selected confirmed
contributors. An owner with no payments therefore saw No groups yet, despite
owning groups visible on Home.

Home and Groups now share the actual ownership/membership predicate. Home keeps
its three-card preview; View all opens the full My groups list. That list has no
three-card cap and includes joined or owned groups without payments. Featured
groups remains a separate Home section populated by approved public records.
The old contributed deep link remains available with the accurate Supported
groups title.

On the final candidate, My groups contains the four expected groups and
Featured groups contains Buri Munsi and Gikundiro. The Groups tab preserves its
previous filter and scroll position. The native harness was corrected to use
Show all groups explicitly before comparing the complete five-row directory.
The corrected run passed all three comparisons: four My groups, two Featured
groups and five All Groups. Home and Groups card bounds both measure 992 px
wide, with equal 44 px side insets on the 1080 px display (16 dp). All displayed
totals and contributor counts match the zero balances and payments in Supabase.

## Tests and controlled candidate

The membership regressions cover unpaid owners, unpaid joined members, more
than three memberships, discovery-only empty recovery, View all navigation and
the retained contributed filter. **67 focused tests passed and Flutter analysis
reported no issues**, including a repeat against the isolated build snapshot.
The source hygiene gate passed. Earlier full-suite counts belong to their
earlier source revisions and are not claimed for this snapshot.

Another active design task changed the shared source during the first build.
The build wrapper correctly rejected that artifact's source binding. A stable
snapshot was then created, tested and built independently. The final wrapper
exited successfully at 2026-09-05T10:48:15Z; upload-certificate signing checks
passed and fixture mode was false.

| Identity | Value |
| --- | --- |
| Version | 1.2.4+23 |
| Snapshot source SHA-256 | `d7d4bc46e6614968edbc4c65545ff88790132c071fc122d03af889d9051d769b` |
| APK SHA-256 | `0e1556b427f9ec24d269edddeb5b494dd9db91418368499d93caa84bcfc3c6ef` |
| AAB SHA-256 | `1cdbe6bc1ad97ba54f9a2ea92ad58867012148f2915dd2f3122b30c8ab987587` |

The APK is installed on dedicated AVD `Collect_DevAccount_QA_20260905`,
emulator-5556. Installed bytes match the local artifact and recorded provenance.
The shared emulator's previous session was removed during the other task's
fixture work. A separate device now prevents further collision. Normal mobile
sign-in succeeded with a fresh owner code and reached live Home.
An app process restart retained that authenticated session. The restarted
process log contained zero Flutter unhandled exceptions or fatal errors.

Screenshot review also identified an unresolved native rendering issue:
navigation icons and labels disappear in some stationary ADB captures while
their accessibility nodes remain present and navigation remains operable.
Repeating the same APK after a cold emulator restart with host GPU rendering
reproduced the discrepancy. Changing the emulator renderer did not resolve it;
the cause has not been established. The paired `groups-bottom-settled.png` /
`groups-bottom-direct.png` and `host-renderer-groups-bottom.png` /
`host-renderer-groups-direct.png` retain the evidence. These captures do not
approve navigation fidelity. The developer's session survived the emulator
restart without another code.

The shared workspace has continued changing. Its observed source hash after
this build was `c5fbaba0c30640b9208de70e72186f536b96867a201186b5c9329f7164b825ac`.
This report therefore identifies the exact tested snapshot, not acceptance of
all concurrent or later changes. No edits from the other task were reverted.

## Evidence and release status

Evidence root: `.cache/dev-account-qa-20260905/`. Sanitized records include
`live-data-parity.json`, `admin-scope.json`, `admin-live-readback.json`,
`snapshot.json`, `snapshot-tests.txt`, `snapshot-analyze.txt`,
`snapshot-build.txt`, `artifact-fixture-scan.json`, `native/installed.json` and
`native/build-provenance.json`, `native/membership-verification.json` and
`native/restart-verification.json`. The earlier signed-in captures are in
`.cache/cleanup-candidate-20260905/dev-*.png` and corresponding XML; they precede
the membership correction and current shared-theme changes.

The physical Pixel and its data were untouched. No groups, memberships,
payments or access controls were mutated; normal authentication created normal
sessions. No new mobile artifact or store screenshot was distributed. The
previous Admin/database deployment remains separately documented in
`docs/release/ADMIN_SUPABASE_DEPLOYMENT_2026-09-04.md`.

MOBILE-DESIGN-100 remains a distribution blocker: all required native cases,
22 annotation closures, original-reference review, full accessibility,
keyboard/recovery evidence and current store screenshots are not accepted.
The intermittent navigation rendering finding also remains open. A fresh gate
run returned exit 2. No approval scores or case closures were invented.
