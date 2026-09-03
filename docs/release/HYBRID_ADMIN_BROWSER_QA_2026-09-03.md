# Collect Admin browser QA — full release matrix

Date: 3 September 2026  
Verdict: **PASS — 69/69 ROUTE/VIEWPORT CASES**

## Executed scope

- Built the current Admin Flutter web candidate and served it locally in authenticated evidence mode.
- Exercised 23 Admin routes at compact `390x844`, tablet `834x1194` and desktop `1440x900` sizes.
- Captured 69 screenshots and checked route resolution, semantics, required labels, responsive navigation, horizontal overflow, accessibility exposure, interactive names and minimum target sizes, keyboard traversal, console messages and page errors.
- Source evidence: `/Volumes/PRO-G40/COOL/.cache/admin_pwa_authenticated_render_smoke/hybrid-members-20260903-uat3/browser-qa/admin_browser_qa.json`
- Evidence SHA-256: `ac8927d5846e656fcd3adba6a5095f316fcb5f30bcbca5e86fb3d3b55f878b62`

The report is release-admissible local synthetic evidence and contains deterministic masked test data only. It is not a production-authenticated session, physical-device acceptance or permission to activate notification sending.

## Result

| Matrix | Routes | Viewports | Screenshots | Failures |
| --- | ---: | ---: | ---: | ---: |
| Full Admin release matrix | 23 | 3 | 69 | 0 |
| SMS receipt list/detail subset | 2 | 3 | 6 | 0 |

All automated checks passed. The SMS receipt list remains usable as cards on compact screens and as a table on desktop. Its detail route exposes status, route, Collect ID, group, payment, member/group after-balances, reference, attempt state and timestamp while keeping destination numbers masked and exact claim-gated bodies outside the general Admin view. The UI also distinguishes an observed Messages send state from handset delivery.

A separate live in-app-browser spot check reached `https://admin.collect.ikanisa.com/#/admin`, correctly displayed `Admin access required` for the existing unapproved session, and routed to the approved Admin WhatsApp sign-in screen. No phone number was entered and no OTP was requested; authenticated production workflow acceptance remains open.

## Earlier 47-finding triage

The first full-matrix run reported 47 findings. Review against the rendered accessibility tree showed that they were test-contract drift, not 47 product defects:

- exact synthetic row counts were replaced by stable table/list accessibility contracts;
- dynamic record-detail headings are now checked by their invariant suffix;
- Flutter's duplicated semantics text for table headings is handled explicitly;
- the removed group CSV-export keyboard assertion was deleted while record-opening keyboard coverage remains;
- interactive controls are scrolled into view and measured rather than waived when nested containers initially clip them;
- current member, user and Admin-role controls are asserted by their actual accessible names.

The corrected harness did not relax route resolution, browser/page error, keyboard traversal, accessible-name, semantics, overflow or 44 CSS-pixel target requirements. The final zero-failure rerun is the authoritative result.

## Acceptance boundary

- The local automated portion of `G-11` and `UI-03` passes.
- Hosted approved-role and permission-denial journeys, 200% zoom, manual screen-reader/keyboard use, dark theme and physical-device testing still require controlled UAT.
- Mac Messages and feature-phone delivery require a separately approved exact recipient/body test. No message was sent during this run.
