# Collect source preservation and trust checkpoint — 28 September 2026

**Status: preserved locally; release provenance remains open.** This checkpoint
protects the recovered working tree before a release-source freeze. It does not
approve the Drive source, establish branch protection, or create a release
commit.

## Current readback

- `HEAD`, `origin/main` and a fresh `git ls-remote origin refs/heads/main`
  return `c2569a47c7f87de68a60c4a247b5c5e3ca640f06`.
- `git fsck --full --strict` exited successfully. It reported dangling trees,
  one dangling blob and the recovered WIP commit
  `f6ae063da44a36514a56d7845f6b7c0a6ce121a8`; it did not report a missing
  or corrupt object. That WIP commit now has the local recovery ref
  `refs/codex/recovery/wip-20260914`.
- The working tree remains dirty. The preservation manifest covers **397
  modified or non-ignored untracked files and 96 tracked deletions**. It records
  file hashes and verifies every archived member by readback. Ignored caches,
  credentials, build output and signed-in device data are outside this archive.
- The private external checkpoint is at
  `/Volumes/PRO-G40/COOL_Drive_Review_2026-09-28/source-preservation-20260928T163735Z`.
  `dirty-working-tree.tar.gz` is 2,763,839 bytes, SHA-256
  `1d1cff551838bbfede60ba5e07fba4d17680095f76ab018cb2159f435de32b6b`.
  The two complete-history Git bundles passed `git bundle verify`; their sizes,
  hashes and recovery ref are in `git-bundle-manifest.json`. The checkpoint
  directory and files are accessible only to the local owner account.
- The recovered checkout's systematic executable-bit mismatch is suppressed
  by local `core.filemode=false`. This changes Git's local status reporting,
  not tracked file bytes or the executable bits recorded in commits. A release
  build must use a clean checkout to validate permissions and inputs again.

## Trust and sharing still open

- On 28 September, authenticated Drive metadata for the COOL root and the
  review environment file still returned `anyone` / `writer` /
  `allowFileDiscovery=false`. The review file's contents were not fetched for
  this check. This is an exposure lead, not proof of unauthorized access.
  The available connector cannot revoke folder or file permissions; the owner
  must remove those grants and supply before/after permission readback.
- The GitHub branch-protection API returned HTTP 403 with the message that the
  current plan does not enable that feature for this private repository. No
  protected-branch claim is made. An owner-approved equivalent release control
  or plan change is required before G04/G09 closure.
- The remote URL and matching commit hash prove synchronization, not trusted
  authorship, source review or artifact identity. No release commit, signed
  artifact or owner-approved provenance manifest exists yet.

## Next source-freeze work

1. Review the 397 preserved files and 96 deletions against the Drive
   incorporation ledger, current Rwanda scope and retired design-rule removal;
   resolve every unique/conflicting source path without losing tests or fixes.
2. Complete credential/history review and Drive access restriction. Record a
   named release owner and the branch/artifact publication control.
3. Freeze one reviewed candidate commit, verify a clean checkout with pinned
   dependencies, run full tests and builds there, and bind resulting artifact
   hashes and approvals to that exact commit.
