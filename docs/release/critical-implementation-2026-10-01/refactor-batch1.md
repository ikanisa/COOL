# ARC02 implementation batch 1

The four oversized roots now satisfy the existing 1,200-line CI limit. The refactor retains public import paths, repository virtual methods, the existing library-private state, session fences, RPC parsing and retry choices. Dirty source present before the batch was preserved; before/after hashes and exact commands are in `refactor-batch1.json`.

| Root | Before | After |
| --- | ---: | ---: |
| lib/shared/repositories/collect_repository.dart | 1830 | 1092 |
| lib/admin/core/admin_runtime.dart | 1501 | 1133 |
| lib/admin/core/admin_roster_import.dart | 1554 | 1052 |
| lib/admin/admin_shell.dart | 1237 | 918 |

## Responsibility boundaries

- `collect_repository_notification_actions.dart` holds preference revision/read/save generations, pending preference intent, acknowledged device registration, refresh/save/read and device-registration operations. Auth/session lifecycle, loading and disposal remain in the root and reach the same inherited state.
- `collect_repository_group_actions.dart` holds joining, reading/rotating invitation codes, member roster reads, member promotion, archiving, ownership transfer and owner health. It retains virtual methods; a private concrete-repository getter passes the same object into the existing invitation-authority extension and Expando request ledger. Payment reads and core session/access guards remain in the root.
- `admin_receipt_repository.dart` holds receipt overview and investigation, unattended policy, receipt operation policy/configuration, worker health/transport, current-owner principal directory/action/lookup and safe unsent cancellation APIs. `admin_exception_repository.dart` holds inbox, deferral evidence, workflow/follow-up reads/actions/lookups, escalation and exception review. Both call the existing `AdminRepository.rpcMap` session fence; typed model validation and automatic retry choices are unchanged.
- `admin_roster_gateway.dart` holds safe transport errors, gateway interface and the Supabase gateway lease/session/expiry fencing. `admin_roster_upload.dart` holds safe filename and source upload admission/hash construction. `AdminRosterDraft` editor, acknowledgement and recovery behavior remains in the original root. All remain one Dart library.
- `admin_shell_navigation.dart` holds navigation entries/types, permission checks, section grouping, matching and header navigation helpers. The shell/widget layout and public access helper imports remain in the original library.

Seven new modules contain 129–480 lines. No threshold, design token, route, auth policy, SQL or business behavior was changed. The root `rpcMap` gained an override annotation required by its new mixin contract.

## Affected consumers

Existing Admin PWA and security source checks now read the moved definitions. The Admin source inventory includes the navigation part; runtime-control source hashes and Admin-read evidence exports include the new operation parts. Root analyzer entrypoints and existing glob-based snapshots already resolve/cover parts and needed no relaxation.

## Verification

- Flutter 3.44.4 / Dart 3.12.2 affected analysis: no issues.
- 37 existing SDK/widget test files: 1,064 passed, 3 skipped, 2 failed. Existing operation/session/account/permission/roster/notification tests passed. Both failures are the 320px enlarged-text dark/light Overview layout cases, with a 66 pixel overflow at `admin_overview_runtime.dart:696`. That unchanged file is outside ARC02; root owns the responsive fix. The full failing run and machine events are retained.
- Two affected security source-consumer tests passed.
- Admin source inventory passed: 28 routes, 119 endpoints (90 active), 452 hashed sources, unchanged during capture. This is source inventory, not complete Admin acceptance.
- Current CI-size scope: 358 modules, zero violations above 1,200 lines, 54 existing advisories above 500.
- Changed Python syntax, focused Dart formatting and diff whitespace checks passed. Owned sources matched the frozen verification hashes on final readback.

This batch is locally implemented. The two retained Overview failures prevent claiming the whole targeted run passed; production, provider, deployment and device/store acceptance are outside this structural refactor proof.
