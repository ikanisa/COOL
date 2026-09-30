> Historical Increment 05 branch record. For the combined candidate and new group-summary behavior, see GROUP_SUMMARY_INTEGRITY_2026-09-26.md. Earlier test counts refer to their original run, not this increment.

# COOL / Collect — reconciled integration candidate

## Why this increment exists

Two different deliveries were both named Increment 04. The local
Recovery_Lists package contained the prefixed contribution viewport and lazy
group-list changes. The separately filed Drive Recovery_Integrity package
contained guarded data refresh, account/repository ownership checks, honest
success detection and SMS-attention handling. They were not interchangeable.

Increment 05 uses the Drive branch's recovery implementation unchanged, adds
the local branch's viewport-prefix and lazy-list changes, and updates the
local branch's outdated recovery tests and runner to the retained behavior.
No original Drive source file is overwritten by preparing this candidate.

## Integration decisions

- Keep `connection_recovery_screens.dart` byte-for-byte from Drive Increment 04.
  The existing data refresh is retained; an older navigation-only implementation
  must not replace it. Tests for newer timestamps, stale cache, repeated taps,
  account/repository changes and SMS attention remain in the candidate.
- Keep the local branch's `forms.CollectFormViewport` import prefix. It resolves
  the collision with the legacy component of the same name without deleting
  either class or changing their constructor APIs.
- Keep lazy contribution-group lists and original row rendering. Activity,
  payment methods, repository loading/state and disabled-danger-button tokens
  remain unchanged from the respective inspected inputs.
- Adapt the eight old recovery widget cases to use the repository fixture and
  current copy. The 19 Drive recovery cases and three disabled-action cases are
  preserved. No obsolete test suite is silently dropped.
- Retain the historical local recovery note with a supersession notice. Current
  recovery behavior is described by RECOVERY_INTEGRITY_2026-09-26.md and this note.

`revolut-design` remains the only design authority. This integration does not
constitute visual review, performance measurement or release authorization.

## Unified validation entrypoint

From the authorized complete checkout, with dependencies already resolved:

```bash
python3 scripts/qa/verify_candidate.py --check
python3 scripts/qa/verify_candidate.py --run
```

The default/check mode validates prerequisites and version probes but never
runs formatting, analysis or tests. It reports ready_not_executed, not passed.
The run mode performs non-writing Dart formatting checks, full-checkout Flutter
analysis with fatal infos and no pub resolution, then the explicit delivered
suite inventory in `scripts/qa/candidate_check_scope.json`.

Preflight checks include a Collect package, nonempty lockfile, exact Flutter pin,
local resolved packages, a collect_app root pointing to this checkout, matching
reported Dart and Flutter-Dart versions, safe target paths and complete declared
test/format coverage. Version output is not cryptographic SDK attestation.

The runner hashes declared source targets, the scope file, package manifest,
lockfile, SDK pin and resolved package configuration. A change to those inputs
stops the run. It does not roll back third-party changes or claim to monitor
unlisted files. Each subprocess has a timeout; failures stop later stages.
No SDK install, pub get/upgrade, dependency rewrite, source formatting write,
deployment, SMS replay or payment mutation is requested by the runner. SDK tools
may still write their normal cache/build outputs.

CI invokes the unified check in addition to, not instead of, the existing full
analysis and full unit/widget suite. Repository hygiene also runs the Python
runner and reconciliation-source regressions. These Python tests use disposable
fake executables; passing them does not compile or execute Flutter code.

## Source application and filing

Three hash-checked installers are supplied outside the source tree: original
baseline, Drive Increment 04, and local Increment 04. Each allows only its
reviewed before-bytes or the final candidate bytes; it rejects unreviewed edits.
Choose the matching installer for the full checkout. Never apply one to this
partial delivery folder, and never layer one Increment 04 package over the other.
The installers default to a read-only check and back up before writing. No Git
history rewriting, commits, remote writes or production release are performed.

The current session cannot upload or update Drive files. The newly prepared
Increment 05 therefore remains pending filing. The separately discovered Drive
Increment 04 is filed and was read back in this session; it is distinct from the
local Recovery_Lists package. See the delivery manifest for exact input hashes,
merge decisions and pending destination. A pending record is not a filing receipt.

## API references checked

- https://dart.dev/language/libraries — import prefixes for identifier collisions.
- https://dart.dev/tools/dart-format — non-writing checks and failure exit status.
- https://docs.flutter.dev/reference/flutter-cli — analyze/test/version commands.
- https://raw.githubusercontent.com/flutter/flutter/3.44.4/packages/flutter_tools/lib/src/version.dart
  — frameworkVersion and dartSdkVersion fields for the pinned toolchain.

These references document commands; they are not evidence of this application's
compilation, widget behavior, accessibility, security review or production safety.
