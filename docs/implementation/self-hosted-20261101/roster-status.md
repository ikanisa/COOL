# Roster capability and remaining native parser gate — 2026-11-01

**Current owner decision:** roster uploads accept supported static images and
reject animated images with a clear message. Full APNG decoding and a separate
APNG supervisor are not release requirements. Earlier animation investigations
are retained as historical evidence; they are not an active delivery plan.
Task 29 remains open for the other decoder, custody and acceptance requirements.

The Supabase application already implements authenticated roster reservations, encrypted original-source storage, deterministic text/CSV extraction, explicitly client-derived XLSX provenance, human review, revision-bound commit, recovery identities and immutable AI processor/dispatch lineage. These were inspected in `supabase/functions/_shared/domain/roster.js`; no claim of new provider or device acceptance is made here.

The signed decoder bridge is implemented and source-bound. The remaining helper uses Python 3.12, Pillow 12.3.0, pypdfium2 5.2.0/PDFium, pypdf 6.19.0, openpyxl 3.1.5 and defusedxml 0.7.1. It relies on Linux process isolation, seccomp and resource limits; its supervisor persists replay nonces in SQLite. The existing parser's complete image/PDF/workbook validation is materially stronger than file-header acceptance. No compatible native Supabase/WASM parser with equivalent isolation and corpus evidence is bundled in this repository.

The inspected dependency mismatch is concrete, not a missing endpoint string. A faithful native parser needs a reviewed WASM implementation, private Supabase replay/outcome custody and exact Edge Runtime acceptance. The Python helper and its SQLite state cannot be relabeled as Supabase-hosted capabilities. The production configuration exposes the complete optional policy/model/project/decoder settings while refusing roster AI activation until that gate closes.

The native investigation is now reproducible in `tools/roster-decoder/native-probe/`, with exact synthetic corpus bytes, package/archive/source hashes and real pinned Edge Runtime probes. `roster-native-feasibility.md` records the concrete APNG codec limitation, strict JPEG improvement, PDF structural prototype, unimplemented native XLSX path and required native version2/PostgreSQL custody plan. `roster-native-observations.json` reports executed observations while explicitly keeping parser-contract and production acceptance false. **Original task 29 remains open.** No production decoder was replaced or enabled.

Required optional settings are `ROSTER_AI_APPROVAL_JSON`, `ROSTER_AI_APPROVAL_SHA256`, `ROSTER_AI_MODEL`, `OPENAI_API_KEY`, `OPENAI_PROJECT_ID`, `OPENAI_ORGANIZATION_ID`, `ROSTER_DECODER_PROTOCOL`, `ROSTER_DECODER_URL`, `ROSTER_DECODER_SECRET` and `ROSTER_DECODER_BUILD_SHA256`. Empty settings remain inactive. Configured values are not processor approval or native-parser qualification.

`docs/architecture/roster-ai-dispatch-policy.md` and the decoder README now describe the actual Supabase bridge, logical versus physical endpoints, preserved safeguards, SQL provenance, external provider copies and remaining acceptance requirements. Their earlier claim that no adapter existed was stale. No parser, authority check, policy guard, source byte or existing codec was changed during this work.

Primary runtime references inspected on 2026-11-01:

- [Supabase WASM modules](https://supabase.com/docs/guides/functions/wasm).
- [Supabase image manipulation and native-library limitation](https://supabase.com/docs/guides/functions/examples/image-manipulation).
- [Supabase Edge Runtime source](https://github.com/supabase/edge-runtime).

## Current consumer and recovery reconciliation

A source-only check on 1 November found that the shipping cookie Admin entry
uses CloudflareAdminRepository, whose inherited openRosterImport operation is
unsupported, and its cookie BFF has no roster import or recovery route. The
retained bearer Admin has a roster dialog and recovery gateway, but the current
Supabase dispatcher registers only review, commit, get, stage and execute;
the older draft, recovery and fresh-sign-in transfer operations are absent.
Manual cookie-Admin group/member operations are not equivalent to roster
import or recovery. No deployed route or user journey was exercised in this
check.

A committed import status currently returns its stored human-review preview
with can_submit still true, whereas the retained Admin status decoder requires
false. Replaying an exact original upload after a human review also returns
the latest revision rather than the documented original extraction preview.
Review-request replay is a separate immutable original-revision response.
These are current source-contract findings, pending fixes and actual current
SQL/consumer qualification; they are not evidence about deployed behavior.
The historical SQL142, SQL144 and SQL149 packets remain historical and cannot
be substituted for current-chain results.

The [cookie Admin recovery assessment](cookie-admin-roster-recovery-assessment.md)
records the missing cookie authority, target-provenance, recovery-lineage and
combined-upload boundaries. It is a source assessment, not a deployed result.
