# Admin roster review — source and interaction contract

## Reference and adaptation

The owner-selected `revolut-design` skill is the design authority. This workflow uses its **Business/operator application** guidance, not the consumer marketing hero or a stretched native overview. Source files read from `/Volumes/PRO-G40/Application Data/Codex/Codex-Home/skills/revolut-design/`:

- `SKILL.md`, `references/brand-adaptation.md`, `references/DESIGN.md`.
- `references/web-patterns.md`: Business 5 bulk operations and the 2025 AU operator guide; the source explicitly does not establish exact live authenticated table geometry.
- `references/component-contracts.md`: operational review, modal focus/dismissal, retained drafts and uncertain acknowledgements.

Classification: **inferred/adapted operator review pattern**. Existing shared Collect theme, Inter/Aeonik fonts, semantic colors, spacing, modal animation, field controls, buttons and info banner are reused. Collect's assisted groups, MoMo identities, permissions and audit reason remain the actual product concepts. No exact authenticated desktop comparator or universal visual match is claimed.

## State contract

| State | Behavior |
| --- | --- |
| Source | Paste UTF8 or upload original file bytes; XLSX also supplies explicitly client-derived TSV after existing archive/XML/formula checks. Consent is required for PDF/images. |
| Preparing | File reading, extraction and RPC completion belong to the original actor/session and invalidation generation. Per-dispatch token refresh is permitted only within that same session. Inputs are locked while awaiting a bounded request. |
| Initial preview | Every row is editable and accessible through 25-row pages. The original source/consent/extraction receipt and initial AI confidence remain separately available. Initial previews cannot commit. |
| Corrections | Local row errors identify corrections without issuing a review write. Saving sends the full ordered list with the acknowledged parent revision and a stable request ID. |
| Saved human review | Exact source/revision bindings, count, server hash and metadata are checked. Human validation is distinct from original AI confidence. An unavailable historical revision is shown but cannot submit. |
| Affirmation | All pages must have been visited and the operator explicitly confirms every row. Editing invalidates affirmation and requires another saved revision. |
| Commit | Create and existing-group additions submit references only. All receipt IDs/hash/count/mode/booleans must validate before success or closing. |
| Unknown result | The dialog and exact request/payload remain. Retry reuses them. No default count, null success or new commit ID is substituted. |
| Rejected review | An explicit action discards the rejected pending review request while preserving the original source and rows; the next review receives a new ID. Ambiguous requests remain frozen. |
| Terminal extraction failure | The old draft is retained, automatic provider reruns are absent, and the operator is directed to discard and start a deliberate new upload. |
| Sign-in changed | Source, form text, rows and receipt are immediately hidden/cleared. Late responses cannot repopulate the dialog or announce success. A new session starts a new import. |
| Dismissal | Outside clicks and Escape cannot silently discard the draft. The explicit discard action abandons it; uncertain commit copy states that the outcome may be unknown. |

## Local UI evidence

The current packet's widget tests use the real bundled fonts. Captures show a synthetic row-26 correction at 800×600, and wrapped validation errors at a 320px viewport with 2× text. Keyboard traversal/Escape and a simulated 240px keyboard inset are exercised. These are target widget captures and interaction tests, not browser/native device or spoken screen-reader acceptance.

`attempts/01` retains invalid-path/style evidence and placeholder-font captures; `attempts/02` retains the passing 130-test run before the visual error-wrapping correction and final style cleanup. Do not substitute those older images for the current captures.

## Boundaries still requiring acceptance

The draft is private and memory-only. Reloading or closing the browser abandons local draft state; this implementation makes no cross-reload recovery claim. Source/revision/commit evidence remains server-side according to the agreed API and requires its independently tested permissions/retention policy.

The SQL142 fixture, live Edge/SQL deployment pairing, provider privacy/budget controls, browser network loss and reload behavior, real operator usability, physical keyboard/screen reader behavior, and a current authenticated desktop comparator are separate acceptance evidence. Local widget tests do not close A01 or production readiness on their own.
