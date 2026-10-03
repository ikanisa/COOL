# Portable current41 fixture and capture proposal

This private proposal contains 49 candidate source paths: ten changed Dart files,
one shared capture helper, 34 byte-exact dated observed JSON receipts and four
small fixture provenance records. Maintained source, original release evidence,
APP, SDK and existing fixtures were not changed by this preparation.

The six readers are `test/admin_exception_models_test.dart`,
`test/admin_exception_workflow_test.dart`, `test/admin_receipt_cancel_models_test.dart`,
`test/admin_receipt_operations_sdk_test.dart`,
`test/admin_receipt_principal_integration_test.dart` and
`test/support/admin_exception_fixture.dart`. Their only deltas replace fixture
paths. The four operations receipts already exist byte-identically in
`test/fixtures/admin_receipt_operations_v2`; this proposal reuses them without
copying or changing that directory's existing provenance.

The selected SQL observations are dated synthetic outputs. Each new domain's
provenance identifies the original receipt path and SHA-256, original producer
result path and SHA-256, and recorded producer timing/status. The source receipts
and producer results remain intact. The principal fixtures retain the original
public SPKI payload and digest; the producer explicitly reports that no private
key was created. No SQL dumps, credential files, private keys or evidence PNGs
are proposed as source.

`evidence/fixture-name-review.json` records the literal and dynamic families.
The principal `expired-pending` case reads the existing identity-pages row through
the existing in-memory adapter; it does not require a separately invented file.
The selected 41 suites import 59 test Dart files before this proposal and 60 after
the one capture helper is added. The history SDK consumer uses the history model's
in-memory helpers without invoking its separate `main()` archive checks, so that
history/provenance boundary is unchanged. Its separate archive-reading tests remain
outside this affected41 portability slice.

The four capture writers are
`test/core/notification_registration_recovery_test.dart`,
`test/admin_investigation_test.dart`, `test/admin_receipt_overview_test.dart` and
`test/admin_roster_dialog_test.dart`. They share
`test/support/test_capture_paths.dart`. The helper accepts ten existing finite PNG
names and creates one fresh system temporary directory per test isolate by
default. It creates no repository parent directories and deletes no historical
evidence. A caller may pass
`--dart-define=COLLECT_TEST_CAPTURE_DIR=/absolute/existing/output-directory` to
use an explicitly selected existing directory. Relative or missing configured
directories and nonregular target files are rejected. The helper does not create
configured directories or their parents.

All existing capture flags remain unchanged. The notification recovery test still
produces its two screenshots during ordinary tests, now in its owned temporary
directory. Operations and roster captures remain under their original optional
flags. Roster `expectLater` and `matchesGoldenFile` image comparisons remain
intact. Optional roster capture setup gives `LocalFileComparator` the same capture
directory so its mismatch PNGs also remain there, and restores the previous
comparator afterward. Flutter's comparison semantics are retained: absent golden
baselines fail comparison; no baseline is silently created. An explicit capture
run must supply expected baselines in the configured directory or use its existing
explicit `--update-goldens` workflow. Four golden names can produce the framework's
finite derived mismatch names under `failures/` in that capture directory.

The private static proof verifies all declared before/proposed hashes, exact
allowed-delta reconstruction of every changed Dart file, unchanged assertion/test
registration/capture-flag/disposal tokens, byte identity of all receipt copies,
reuse of the four existing operations fixtures, and live preimage stability when
requested. It is not a new mandatory acceptance gate. Re-run it before integration
with `python3 verify_preparation.py --verify-inputs` from this directory. After
integration, the optional live-preimage check intentionally no longer describes
the changed maintained files; the private-only verification remains usable.

No Dart formatting, Dart analysis, Flutter test, APP export, SQL invocation,
provider call, SDK lock operation or actual capture was performed here. Root owns
batch formatting, integration, the required current41 consumer proof and output
readback. Static preservation and dated receipt provenance do not close ARC02 or
establish production or visual acceptance.
