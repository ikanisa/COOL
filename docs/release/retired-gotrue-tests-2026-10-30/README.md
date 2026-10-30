# Retained partial GoTrue test sources

This archive preserves the 41 GoTrue test and fixture files that remained at
`third_party/gotrue/test/` in Collect commit
`f6d0f54f0c2d0033f2f1c45d1d64b99d4ac0d7f6`. Every file retains its exact bytes
and mode. `SHA256_MANIFEST.json` records the original path, archive path, Git
blob, mode, byte length and SHA256 for each file.

At that commit the original directory contained no `pubspec.yaml`, no
`pubspec.lock` and no `lib/` implementation. Collect's root dependency manifest
and lockfile did not contain GoTrue, and active app/test/tool sources did not
import this orphaned package. These fragments have no runnable package context.

The repository-wide Flutter analyzer was loading those orphaned test files as
active source and reporting 3,979 diagnostics from their missing imports and
dependent symbols. The files now live in the existing immutable release-source
archive, which the existing analysis and formatting configuration already
distinguishes from buildable source. No analyzer exclusion, lint severity, test
assertion, dependency or lockfile was changed for this archive.

These are preserved historical source bytes. The archived GoTrue tests were
not executed, and no passing-test, package-restoration, provider or production
acceptance claim is made for them. Current application tests and qualification
gates remain in their maintained locations.

To check preservation, resolve each `archive_path` from the repository root,
compare its bytes and mode with the corresponding manifest record, and compare
the original `git_blob` with the original path at `source_commit`. Do not
regenerate or format the archived files.
