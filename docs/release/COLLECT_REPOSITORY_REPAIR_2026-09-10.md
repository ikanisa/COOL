# Repository audit fixes — 10 September 2026

Scope: repair the seven failures reproduced in the intact audit checkout at
`caafcef15f83de9baae84c377e1a99bb49ed6920`, validate, and publish the changes to
`main`. The unavailable external-drive checkout was not modified. No application
runtime code, database schema, production configuration or deployment changed.

## Fixed and verified

- CI no longer invokes the removed `revolut-parity-evidence-consistency` target.
  The current mobile design contract and fail-closed regression suite remain
  required. A source-contract test verifies both CI and repo-wide QA delegate to
  the existing checker.
- The approved visual-asset inventory now references the two Home/Groups PNGs
  already shipped and recorded in the 7 September native capture manifest.
  Their paths and full SHA-256 hashes agree. This repairs inventory drift; it
  does not renew their capture date or runtime provenance.
- The visual asset test derives coverage from exact path-set equality and
  checks every file hash, instead of assuming the historical 37-asset count.
  The current inventory contains 175 assets.
- At 200% text with the landscape keyboard open, the profile Save action is
  outside the sliver cache. The responsive test now scrolls its actual form
  before resolving the action, then verifies its visible bounds. Both Rwanda
  and diaspora variants also tap Save and read back the edited profile values.
  The platform SMS-access boundary uses an isolated fixture, as in the existing
  profile-editor tests; no device or customer SMS is accessed.
- The Home and Groups golden candidates were opened alongside their previous
  baselines. Only the existing category-specific Rwanda group-cover photographs
  changed. Layout, labels, colours and navigation are unchanged. Only those two
  baselines were regenerated, without changing the comparison tolerance. The
  design skill required visual review before this update; this is regression
  evidence, not owner acceptance or native release approval.

## Validation

| Check | Result |
| --- | --- |
| Flutter 3.44.4 analysis, fatal infos | Pass, no issues |
| Full non-integration Flutter suite, concurrency 4, seed 20260910, coverage enabled | 765 passed, 0 failed |
| Focused landscape/200% keyboard forms | 6 passed, including both profile saves |
| Deno 2.5.6 backend tests | 54 passed, 0 failed |
| Deno type checking | All 38 TypeScript files passed |
| Ruby/shell syntax | 169 files passed |
| Migration validation | Pass |
| Mobile design contract | Structurally valid; release not assessed |
| Mobile design gate regression suite | 35 tests, 143 assertions passed |
| Visual/source hygiene | Pass |
| Release secret scan | Tracked-file fallback passed; gitleaks unavailable |
| Notification source contract | Pass |
| Public media validator tests | 7 tests, 15 assertions passed |
| Public website static build | Blocked by unchanged screenshot runtime fingerprint drift |

Command logs and machine-readable validation results are retained locally under
`.cache/repo-repair-20260910/`. They are implementation QA, not evidence of a new
production release.

## Supabase readback

Project `lhbowpbcpwoiparwnwgt` has all 124 local migration versions, with no
pending or remote-only versions. The newest is
`20260906160000_group_cover_bank_and_atomic_creation_media`.
The three previously recorded name-only differences at versions
`202605230012`–`202605230014` remain unchanged. Version parity is not a fresh
schema/data-equivalence audit. No migration history was repaired and no database
write or redundant deployment was performed.

## Remaining external and release gates

The public screenshot records retain runtime hash
`42bf9d4ea467f96d8195e6181bddec8b1394feef87c468fc7fe25cbd8f9286f2`.
The current runtime fingerprint is
`d57df23bf969eb80858a0520e47abfb108b1947f34f118c8221d038c035b95df`.
Neither manifest was rewritten to pretend that a new native capture passed.

A fresh isolated iOS simulator was created for recapture. The first build found
a generated dependency link pointing to the checkout's former temporary path;
`flutter pub get --offline` regenerated that link without changing lockfiles.
The next build failed because Macintosh HD ran out of space. It produced no
passing route run, screenshots or installed-bundle verification. Only that new
simulator, the failed build products/DerivedData created by this run and the
downloaded Deno archive were removed. These temporary outputs can be recreated;
existing simulators, user files, source and historical evidence were preserved.
Free more internal disk space, then rebuild, capture, inspect and verify the
installed bundle before refreshing website provenance and running its full gate.

GitHub's existing main-branch checks also report that jobs were not started
because the account is locked due to billing. Publishing these fixes does not
resolve that account condition. Hosted CI success, website deployment, full
native acceptance, store review and public availability remain unclaimed.
