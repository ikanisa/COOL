# Asset-manifest integrity — Increment 07

`revolut-design` remains the sole design authority. The checks below establish
file integrity and input safety, not design acceptance, source completeness, or
permission to delete an asset.

## Changes

The standalone approved-visual-manifest check now lives in
`scripts/qa/asset_manifest_integrity.rb`. Existing typography,
artwork-extension, official-logo, palette, fixture-isolation,
product-boundary, and secret-scan checks remain in place.
No approved asset hash, image, font, icon, dependency, or application file is
changed by this increment.

The manifest reader accepts canonical UTF-8 repository-relative paths inside
`assets/`, `android/app/src/main/res/`, `ios/Runner/Assets.xcassets/`, or `web/` and
only the visual extensions already inspected by the existing gate. It rejects
absolute and traversal paths, Windows drive paths, backslashes, control
characters, empty/dot components, duplicate entries, nonvisual files, and paths
outside those roots before hashing an entry. It checks each filesystem component
with `lstat`, rejects symlinks and nonregular assets, and checks file metadata
before and after reading. It never regenerates the approval manifest.

The 8 MiB manifest-size bound is a parser resource limit, not a visual policy or
product threshold. Asset hashes are streamed in 64 KiB chunks. Invalid lines are
reported by line number and reason, not by echoing their contents.

## Commands on a complete, quiescent checkout

```bash
ruby scripts/tests/asset_manifest_integrity_test.rb
ruby scripts/qa/asset_manifest_integrity.rb --root . --json
```

The standalone command exits 0 for matching inventoried files, 1 for integrity
failures, and 2 for a blocked/invalid environment. It requires the provided root
to be the Git checkout root, includes indexed missing paths and nonignored
untracked assets, and uses NUL-delimited Git output. It does not traverse Git
history, submodules, ignored untracked assets, or arbitrary Drive folders.
The existing CI hygiene job runs the Ruby suite before the existing hygiene
checks; the full Flutter analysis and application-test steps are unchanged.

## Limits

The helper protects reads directed by the approval manifest, not all file reads
or subprocesses in the wider pre-existing hygiene script. It is not a sandbox
against a malicious local process swapping parent directories during execution;
stop other writers before verification. Symlink checks and before/after file
metadata checks are defense in depth, not a guarantee against all filesystem
races or hard-link aliases.

A matching manifest is evidence of byte identity only. It does not prove artwork
ownership, approval authenticity, design compliance, absence of secrets, or that
an unreferenced asset is safe to remove. A partial source overlay cannot produce
full-repository readiness. No live cleanup, dependency removal, deployment,
production configuration update, or Flutter application validation is performed
by these scripts.

## References checked

- Ruby File/lstat/open documentation: https://docs.ruby-lang.org/en/3.1/File.html
- Ruby IO documentation: https://docs.ruby-lang.org/en/3.1/IO.html
- Git tracked/untracked and NUL-delimited inventory: https://git-scm.com/docs/git-ls-files
