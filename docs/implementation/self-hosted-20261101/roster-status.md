# Roster capability and remaining native parser gate — 2026-11-01

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
