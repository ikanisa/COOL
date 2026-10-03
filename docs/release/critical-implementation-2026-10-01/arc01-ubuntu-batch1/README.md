# ARC-01 Ubuntu formatter cohort — failed, preserved

The actual maintained `make format-check` ran on an isolated Ubuntu 24.04.5 ARM64 checkout with official Dart 3.12.2. It returned **exit 2: 669 files checked, 15 would change**. No source bytes changed. ARC-01 remains open: the malformed-fixture and final passing phases were not executed after the baseline failed.

This is the original architecture finding's real Linux execution, but it did not reproduce CI's preceding Flutter/Pub bootstrap. The clean checkout had no `.dart_tool/package_config.json`, and the formatter reported unresolved `package:flutter_lints/flutter.yaml`. Those limitations are retained rather than treating the run as complete CI acceptance.

The source export contains 751 SHA-bound inputs, including all 737 existing non-documentation Dart paths reported by the maintained Git inventory, untracked authored files, package manifests, options, Make, CI and the upstream manifest. The formatter's existing exclusions removed 68 byte-identical GoTrue upstream files, producing 669 applicable files. Its 163,006 dated documentation snapshot exclusions were preserved. No root Git objects, generated package configuration, caches, environment files or credentials were copied. Ubuntu created a fresh independent Git repository and committed the exported inputs. The final readback found no root/private changes or newly applicable paths.

The source and process receipts are in `preparation-attempt2/` and `formatter-attempt1/`; `final-source-scope-readback.json` records the later dated readback. `initial-make-format-check-result.json` retains the 90-second deadline, actual 4.28-second command, exit 2 and full-log digest. `container-identity.json` proves a network-none, port-free, non-privileged container with bounded CPU, memory and PID counts. The owned container was removed, and both immediate and final absence readbacks are retained. The authenticated SDK archive/private source checkout and two owned derived images remain available; this packet does not claim they were deleted.

Ubuntu's official ARM64 manifest was `sha256:11dc1ccb427f0464a2369e645454c272bb0baece7357c892ba69d313b3a332cf`. Dart's official archive SHA-256 was `f82c83ece7d168047550dfd4a664e4071ac7c488bddb72dc43102c22d7e0b518`. Actual executable/version, `/etc/os-release`, Git 2.43.0, Make 4.3, Ruby 3.2.3, signed Ubuntu package acquisition and derived-image identities are retained in the acquisition/build/preflight receipts. Publisher records were obtained over HTTPS and checksums/image identities read back. [Dart SDK archive](https://dart.dev/get-dart/archive), [official Canonical Ubuntu images](https://hub.docker.com/_/ubuntu).

The Ubuntu run reported these 15 files:

```
lib/admin/core/admin_exception_checkpoint_web.dart
lib/admin/core/admin_gateway_checkpoint_web.dart
lib/admin/core/admin_governed_settings_checkpoint_web.dart
lib/admin/core/admin_receipt_cancel_checkpoint_web.dart
lib/admin/core/admin_receipt_operations_checkpoint_web.dart
lib/admin/core/admin_receipt_principal_checkpoint_web.dart
lib/admin/core/admin_receipt_successor_checkpoint_web.dart
lib/admin/core/admin_roster_checkpoint_web.dart
lib/admin/core/admin_runtime.dart
scripts/tests/admin_receipt_source_busy_test.dart
test/admin_governed_settings_checkpoint_browser_test.dart
test/admin_receipt_operations_checkpoint_browser_test.dart
test/admin_receipt_principal_browser_test.dart
test/features/runtime_component_contract_test.dart
third_party/firebase_messaging/lib/src/messaging.dart
```

A separate read-only host execution of the same actual Make command checked 669 files and reported only three changes: `lib/admin/core/admin_runtime.dart`, `scripts/tests/admin_receipt_source_busy_test.dart`, and `test/features/runtime_component_contract_test.dart`. These are current source failures requiring their owners' review. The host's existing generated package metadata recorded Collect language 3.12, Firebase Messaging 3.6 and GoTrue 3.9; only its digest and bounded public metadata were recorded, never reused in the private checkout.

A small read-only experiment with the same official Linux Dart executable shows that the default clean-context output for `admin_exception_checkpoint_web.dart` differs by a blank line before its extension type, whereas an explicit 3.12 diagnostic produces the captured bytes. This supports a package-language-context explanation for at least that difference. It does **not** establish that all remaining 12 files are acceptable; only a genuine canonical Pub bootstrap can resolve the cohort. No language override, fabricated package mapping, inventory narrowing or formatter change was applied to the maintained gate. [Dart formatter behavior](https://dart.dev/tools/dart-format), [Pub's generated package configuration and enforced lockfile](https://dart.dev/tools/pub/cmd/pub-get).

The initial wrong checksum suffix produced HTTP 404 and remains in `preparation-attempt1/`. A later historical Flutter feed URL also produced HTTP 404; its bounded observation remains in `canonical-bootstrap-discovery/`. Corrected publisher paths were researched before subsequent metadata calls. No identical timeout was retried. The actual archive acquisition, image pull, image build and formatter command all completed within their recorded deadlines.

`bootstrap-plan.md` describes a separate fresh attempt using official Linux Flutter 3.44.4 and CI's exact `flutter pub get --enforce-lockfile`, after the three genuine current source issues are reviewed by their owners. This packet grants no Flutter analysis/build, hosted CI, UI fidelity, production deployment or broader readiness acceptance. `batch.json` and `SHA256SUMS` seal this failed cohort and its diagnostics.
