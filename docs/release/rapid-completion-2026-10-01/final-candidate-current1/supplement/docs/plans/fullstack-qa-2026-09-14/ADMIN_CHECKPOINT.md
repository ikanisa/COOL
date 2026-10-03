# Collect Admin QA checkpoint

14 September 2026. P5 is in progress. This checkpoint covers local Admin
source, synthetic browser/widget behavior and a read-only published hosting
check. It does not establish full Admin workflow, installed-PWA, visual or
release acceptance.

The final application regression passes **867 tests, zero failures and zero
skips**, with 615 unchanged recorded source inputs. Coverage is
12,744 / 17,072 lines (74.65%) against the unchanged 40% CI minimum. Analysis,
formatting, source hygiene and the exact 1,200-line CI size step pass. Both
native former mobile visual acceptance rule gates remain blocked. The final isolated web build
passes with 413 unchanged build-source inputs and 154 hashed output files.

## Confirmed defects and local repairs

**FQA-031 — Recoverable failures lacked an in-place retry.** Identity loading
failure, overview failure and record detail failures left the user without
an inline Retry control. Lists had a toolbar Refresh control, but their
error panel also lacked the requested recovery action. Shared error panels
now invalidate the relevant identity, overview, list or detail request.
Retry does not relax authorization: a revoked identity still reaches denial.
The identity regression first failed; all 22 new record recovery cases also
failed before the corresponding repair. The resulting 91 access/recovery
tests pass, including all 22 protected routes with no session, no Admin
identity and no required capabilities.

**FQA-032 — Returning from a record discarded the queue context.** The
browser reproduced Groups search `Buri Munsi` → open record → Back to Groups
returning to an empty search and 25 of 30 rows. Shared lists now retain
search, status, sort, page and scroll in memory for the current Admin
identity. Records are fetched again. A country change resets pagination
and scroll on return; account changes discard the saved view state.
Regression cases cover filtered/sorted search, a later page with a real
scroll offset, identity changes on a detail route or open queue, immediate
navigation during identity change and country changes while away.
The browser confirms the restored search text and one matching row after
return and a subsequent Refresh.

**FQA-033 — The queue search label was attached to a disabled duplicate.**
Browser DOM and rendered-image inspection showed that a restored populated
search field retained its visible text but lost its accessible name. The
label belonged to a separate disabled text field. The semantics regression
reproduced three exposed fields instead of the intended global search and
one queue search. The shared control now merges its label, help and editable
field into one semantics node. The focused regression passes for the empty
field and the restored `Buri Munsi` value, including its focus action.
The rebuilt browser confirms one enabled, named field, successful editing
and the correct restored value after focus. A separate resting DOM read
still returned an empty value before focus, despite the visible text and
the passing Flutter semantics-value assertion. That failed observation is
preserved in `accessibility-browser/search-stages.json`; its effect on real
reader navigation is not established. FQA-033 remains open for that follow-up,
with its duplicate-field/name repair explicitly recorded as implemented.

No visual palette, product terminology, provider action or access permission
was changed by these repairs. The state cache contains view preferences,
not record data, and is not persisted to browser storage.

## Coverage and source mapping

[admin-route-dependencies.csv](admin-route-dependencies.csv) covers all
24 router entries: login, denial and 22 protected routes. It records the
15 default client navigation permission scopes, each primary read RPC,
applicable country wrapper and the latest located SQL source declaration.
`admin-browser/route-dependencies.json` binds 128 source files and includes
the matching declaration history and direct guard/dependency observations.
This is a discovery map: runtime metadata can override the client fallback,
and declaration discovery alone does not prove transitive server enforcement,
deployed schema parity or complete action/modal coverage.

The current source uses one combined Admin access level, backed internally
by `platform_owner`. Its server identity path checks the active, approved
WhatsApp identity/session boundary. The client reads `admin_current_user`
and checks capabilities before mounting the route data workspace. The
country wrapper allows nine list RPC names and delegates to their permission
checks; a missing scoped endpoint is not replaced by an all-country request.
No live sign-in, OTP delivery or production permission mutation was attempted.
Earlier isolated SQL contract results retain their separately recorded schema
state; browser fixture results do not replace them.

## Browser evidence and its limits

The isolated entry point uses the actual Collect Admin app, router and shared
widgets with an in-memory evidence repository. It refuses non-loopback hosts,
non-evidence configuration and any configured Supabase URL/key. There is no
backend client. Its action responses cannot establish persistence, financial
completion or provider delivery.

- After the recovery repair: 72 settled ready-state cases pass across all
  24 routes at 320 × 900, 834 × 1000 and 1440 × 1000. Ten additional failure
  and Retry journeys pass at 320 and 1440 px, covering identity, overview,
  group list, transaction detail and system health failures.
- After the queue-state repair: another 72 ready-state cases pass on the
  recorded `queue-fixed` build, plus the Groups search/detail/return/refresh
  journey. That build predates the final search-semantics repair.
- On the final `accessibility-browser` build: all 72 ready-route cases pass,
  including one enabled named search field on all 13 queues at three widths.
  All ten failure/Retry cases and twenty signed-out, denied, missing-permission,
  loading and empty cases pass. These are **102 browser cases**, separately
  from the five search-value observations (four passes and one unfocused-value
  failure). Actual reader and installed-platform behavior remain unverified.
- The public Admin hosting gate passes its seven HTTP response checks.
  Headers and static asset availability do not establish authenticated
  workflows, installation, offline recovery or version-update behavior.

Captures require an unchanged rendered frame before recording route geometry
and visible fixture content. Earlier captures taken during route transitions
overlapped outgoing and incoming pages; they are retained as invalid visual
measurements in `transition-captures/`, not classified as layout defects.
Initial selector/fixture mistakes, a synthetic harness compile error and the
semantics-test cleanup error are also preserved, not attributed to the product.

The implementing agent inspected settled overview, group queue, transaction
list/detail and restored-search images. This is limited implementing-agent
review. The selected authority remains the `revolut-design` Business/operator
reference family and its operational-table/component contracts. Compact
operator layouts and recovery behavior are target adaptations; marketing and
native mobile screenshots do not certify these Admin surfaces. No independent
visual review, source-authenticated full-state comparison or owner acceptance
has been recorded.

## Capacity and remaining work

Available disk space recovered independently enough to complete several
isolated builds, then fell below 1 GiB again during this checkpoint. The last
blocked attempt at the final browser build recorded 1,505,058,816 free bytes
and stopped at its unchanged 3 GiB preflight requirement. A subsequent read
found approximately 3.07 GiB available; a separate retained attempt then
completed the final build. This fluctuating capacity does not establish
capacity for the native matrix. At 19:37:10 UTC the exact owned database
container inspection succeeded and reported `exited`, `running: false`.
Shutdown is now observed; removal and database readiness are not established.
The source, prior artifacts and stopped database are retained. Other project
processes and containers were not stopped or removed.

Next work includes the unfocused search-value/reader follow-up, complete
per-route state/geography/keyboard/reader coverage, the action/modal-to-RPC
matrix with persisted synthetic outcomes, session expiration/revocation during
tasks, stale/conflicting changes, and installed-PWA lifecycle/update tests on
named platforms. Native member journeys, four remaining SQL fixtures,
provider/concurrency outcomes and real mobile acceptance remain separate
full-system requirements.

All detailed evidence is under
`.cache/fullstack-qa/20260914T151002Z/admin-browser/`. Current test counts,
source/artifact hashes and preserved attempts are indexed in
[results.json](results.json). See [STATUS.md](STATUS.md) for the latest
cross-system state. No deployment, message, production migration, signing,
store publication or acceptance decision was performed.
