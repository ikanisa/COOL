# Licensed Inter fallback: affected verification

The existing accepted APFS export was cloned; the prior export was preserved.
Only twelve named root typography/public/test/asset deltas were overlaid in order.
The dependency prefix in `pubspec.yaml` was unchanged, so existing locked package
bindings were reused. Source Aeonik binaries were removed only from the new
clone, retaining their original hashes in the overlay record.

## Completed checks

- Actual Inter landing tests: **8 passed**, including the homepage and public
  pages at **320px with 200% text**.
- The single licensed-Inter runtime contract: **1 passed**.
- Nonwriting formatter and selected analyzer passed for the six changed Dart
  files. Ruby syntax passed for the static publisher.
- The single static-route source/baseline case passed after copying its missing
  named historical fixture. The original `ENOENT` failure was preserved;
  successful Flutter/format/analyzer/syntax checks were not repeated.
- The staged Inter test asset hash equals the current bundled Inter bytes. Its
  local OFL text and named changed/direct-consumed source hashes are recorded.
  Current metadata references the local authoritative Inter licence; excluded
  website fonts retain their source separately.

## Reviewed public golden

Only `public website compares historical desktop baseline` was run. Its actual
Inter image differs from the existing Aeonik baseline; the expected mismatch is
preserved. The precision tolerance remains **0.0005**. Baseline and manifest were
not modified, and no `--update-goldens` command was used.

The root visually reviewed the actual old and new images and accepted the
explicit font difference: the same three-line hero and body content, no
occlusion, and unchanged controls, photo, Collect identity and layout. Only
the public baseline and its manifest entry were published; the old baseline
was retained.

The subsequent **public golden plus manifest consistency tests both passed**.
The other twelve manifest entries match the retained parent. No other golden
was executed or updated. Current named source/export hashes remained unchanged.

[Actual Inter candidate](golden-candidate/public_home_desktop.png).
[Final affected verification](final-validation.json) is **pass**. The original
pending-review packet and expected mismatch remain retained.

## Scope

Named changed/direct-consumed root and export inputs were unchanged through the
checks. This packet proves the affected Inter widget behavior and source font
contract. It does not attest a new browser/native/static site build, complete
Revolut visual fidelity or release-binary font contents. Older APK/iOS captures
may still contain pre-fallback font assets and retain their original scopes.

[Original checks and expected-mismatch history](validation.json).
