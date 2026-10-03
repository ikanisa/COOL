# Firebase Messaging and GoTrue exact-release fork provenance

ARC09 local source-origin slice. The exact official pub.dev metadata and archives
were fetched over certificate-verified HTTPS using the new separate fetch caller.
The official metadata digests, downloaded archive bytes and all retained original
`UPSTREAM-SHA256.json` file hashes agree. This packet verifies source origin and the
reviewed exact-byte delta; it supplies no behavioral, provider, distribution-rights,
signed-artifact, advisory or release approval.

| Retained fork | Official version | Upstream files | Retained files | Identical common files | Changed | Added | Omitted |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Firebase Messaging | 16.5.0 | 148 | 39 | 34 | 2 | 3 | 112 |
| GoTrue | 2.27.1 | 79 | 83 | 73 | 6 | 4 | 0 |

The Firebase omissions are precisely enumerated example application and upstream
test files. Every runtime/platform/package file and the unchanged license remain
retained. GoTrue retains every upstream file. Both `LICENSE` files are byte-identical
to the authenticated official archive. That preservation does not establish rights
approval for the final redistributed artifact or its complete notices.

The Firebase review binds the existing workspace declaration removal and the iOS
scene delegate `BOOL` compatibility fix. The notification handling body remains
unchanged; FCM `gcm.message_id` handling consumes options while non-FCM/deep-link
options remain available to later consumers. No callback code was changed by this
work.

The GoTrue review binds the existing browser-only departed-session invalidation
protocol, exact actor/session/project ownership, bounded payload handling,
replacement-session logout protection and removal of browser credential logging.
Native branches remain retained. The two changed upstream tests replace copied
signed fixtures with synthetic opaque/invalid-signature fixtures; remaining changes
there are Dart formatting. The analyzer change uses the app's locked lints and
excludes retained upstream test/example cohorts with their separate unavailable dev
toolchain. This packet does not claim those upstream integration tests executed.

The new manifests under `scripts/supply_chain/fork_deltas/` enumerate every changed,
added and omitted path with original/current SHA-256 values and review rationale.
The verifier pins each manifest's exact byte digest. It never learns or accepts a
new delta from the current worktree. Updating a fork requires an explicit reviewed
manifest and verifier trust-root update. The complete retained file set is checked
without generated/cache exclusions, and every unchanged common file must match its
authenticated upstream bytes.

## Verification and use

Fetch and offline verification are separate operations. Fetch requests only the
exact known metadata and archive endpoints, refuses foreign/redirected origins,
checks archive digests and tar safety before caching, and refuses overwriting an
existing cache. Neither operation extracts tar entries to disk, installs packages,
edits forks or contacts Firebase/Supabase providers.

```sh
python3 scripts/supply_chain/verify_pub_forks.py fetch --cache-dir .cache/pub-fork-origin-v1
python3 scripts/supply_chain/verify_pub_forks.py verify --cache-dir .cache/pub-fork-origin-v1
python3 scripts/tests/pub_fork_origin_test.py
```

The retained packet can be checked without network:

```sh
python3 scripts/supply_chain/verify_pub_forks.py verify --cache-dir docs/release/critical-implementation-2026-10-01/fork-auth-batch1/fetched-official
```

`--root` supports verification of an immutable export; the reviewed manifests are
loaded from that export by default. `--manifest-dir` remains digest-checked and
cannot authorize new contents. Use canonical physical paths: source/cache symlinks
are refused. Root owns subsequent CI/Make integration; this slice changes neither.

`comparison.json` records every official and retained file hash and both tree
identities. `fetch.json` records actual public-download identities from the pre-review fetch caller. Its source hash is dated; the authenticated metadata/archive bytes are unchanged and reverified offline by the final verifier. No extra network fetch is needed to reuse those exact bytes. The final run
passes 30 adversarial tests, fourteen real-copy CLI mutation cases and Python syntax
checks against 130 unchanged inputs in `inputs-before.json`/`inputs-after.json`.
The tests reject archive byte mutation, unsafe/duplicate tar paths, links/devices,
archive expansion abuse, foreign metadata, source changes/additions/removals,
cache-manifest mismatch, altered reviewed manifests, source symlinks, license loss,
license mutation disguised as an approved delta, and changes during verification.
No production runtime or retained fork README/license/test bytes were edited.

An initial test run failed because macOS's temporary directory spelling traversed
its `/var` system symlink. The fixture root now resolves that trusted temporary
root to its physical path before creating inputs; source/cache symlink rejection
remains enforced. The final current tests pass. Independent review then identified output traversal/hardlink aliases, case-insensitive filesystem aliases, silently skipped unreadable subtrees, blocking FIFO inputs and inter-package drift gaps. Those were fixed with canonical containment plus existing ancestor directory identities, protected input/alias checks, atomic receipt replacement, traversal error propagation, nonblocking regular-file checks and a final aggregate input readback; each has adversarial tests. The pre-review attempt remains explicitly superseded under `pre-review-attempt1/`. Four byte-identical bootstrap
public-download copies were removed after comparison; the authenticated actual
fetch copies remain in `fetched-official/`.

## Primary sources and evidence limits

- [Firebase Messaging 16.5.0 package](https://pub.dev/packages/firebase_messaging/versions/16.5.0)
- [Firebase exact release metadata](https://pub.dev/api/packages/firebase_messaging/versions/16.5.0)
- [Firebase exact archive](https://pub.dev/api/archives/firebase_messaging-16.5.0.tar.gz): `55cf1000dd72d229ebff3ce6a399bd35705a7675275478b31308afd90ac85751`
- [GoTrue 2.27.1 package](https://pub.dev/packages/gotrue/versions/2.27.1)
- [GoTrue exact release metadata](https://pub.dev/api/packages/gotrue/versions/2.27.1)
- [GoTrue exact archive](https://pub.dev/api/archives/gotrue-2.27.1.tar.gz): `f6f42ea035953b2439664c1afb46630460edbb917093843a3a0618bfa45619f6`

The independently queried HTML pages confirm exact package/version context but
have cached relative publication dates. Exact publication timestamps in the receipt
come from the directly fetched release API metadata. The two API pages could not
be read through the web text tool; their exact bytes were fetched directly with
Python HTTPS and verified against the pinned archive digests.

The trust basis is official HTTPS pub.dev metadata plus pinned archive and per-file
digests. No independent publisher signature or signed provenance attestation was
available or asserted. ARC09 still requires current advisory review, observed
resolved native/signed-artifact dependency inventories and notice/rights acceptance.
The prior aggregate source inventory remains dated evidence; its old file counts
are not repurposed as current provenance or clearance.
