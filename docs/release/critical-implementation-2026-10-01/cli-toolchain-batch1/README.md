# ARC08 pinned CLI prerequisite and executable closure

Supabase CLI 2.114.0 is available in the task cache. No global shell, app or plugin installation changed.

```sh
SUPABASE_BIN=/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/.cache/toolchain/supabase/2.114.0/darwin-arm64/supabase
SUPABASE_GO_BINARY=/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/.cache/toolchain/supabase/2.114.0/darwin-arm64/supabase-go
```

The exact cached npm binaries were compared byte-for-byte with the official Darwin arm64 release archive. The archive matches both the published `checksums.txt` entry and the GitHub release API digest. Both extracted executables report `2.114.0`; each is a regular executable Mach-O arm64 file. The native main executable has a minimum OS version of macOS 13; the companion specifies macOS 12. The current host is macOS 26.6.2. Local version/signature probes used a private `SUPABASE_HOME`, no credential variables, disabled telemetry and disabled keyring access.

| Input | SHA-256 |
| --- | --- |
| Official `supabase_2.114.0_darwin_arm64.tar.gz` | `bdd67161af7c7e537e15ec72db2f2c59bca569b41d959bcaaec7004ba400e653` |
| Official `checksums.txt` | `ed484a19890af772cd665c39966ff67b94024e0af17653b9bc365de78a1b8d75` |
| Main `supabase` executable | `372e2b371842ba3c8175a7eeeff694ad48ea383fa9c923d93953b1a29551206b` |
| `supabase-go` companion executable | `7223e137d82f38fcc35715c80e6c6d1c0abfc2c91ce880b58b1340060ae8d66e` |

The [official pinned release](https://github.com/supabase/cli/releases/tag/v2.114.0) and [asset digests](https://github.com/supabase/cli/releases/expanded_assets/v2.114.0) were checked directly. The release metadata reports `immutable=false`. Both binaries pass `codesign --verify --strict`, but their embedded signatures are ad hoc, with no publisher TeamIdentifier. No independently authenticated signed asset provenance or human release approval was established. Registry metadata advertises an npm signature/SLSA attestation; those were not verified in this bounded task.

## Controller correction

The pinned CLI ships a native main executable and a Go companion. Its actual [v2.114.0 resolver source](https://github.com/supabase/cli/blob/v2.114.0/apps/cli/src/shared/legacy/go-proxy.layer.ts) gives `SUPABASE_GO_BINARY` priority, then checks the co-located binary and npm package locations. A main-only executable hash leaves that secondary code input unbound.

The backend controller now requires `supabase_go` alongside `supabase` and `deno` in approval toolchain metadata. It verifies the companion's exact approved bytes and repository version before project operations, explicitly supplies its checked absolute path to child processes, and rechecks it before every controller/Management transport operation. Missing/swapped companions and unapproved override bytes are rejected before project calls; drift after preflight stops the first write. Older main-only approval records require fresh authorized review.

All 30 deployment contract tests passed, with no failures or skips, in 199.593 seconds. Python/Bash syntax, owned-path whitespace and final executable/source hash readback passed. Controller/helper inputs stayed unchanged during the full run. Missing/replaced companions, unapproved overrides and mid-run companion drift are covered alongside the existing approval/candidate/target/partial-failure tests.

The [operator contract](../deployment-batch1/OPERATOR_CONTRACT.md) contains the revised schema. [Controller proof](controller-proof.json) and [regression log](delivery-contract-tests.log) record the final tested source boundary. [Integrity receipt](integrity.json) records exact official URLs, asset/member identities, architecture/version probes and signature limitations. The canonical candidate exporter did not change in this follow-up; its existing 39-pass regression proof remains applicable at its unchanged recorded hash.

The current controller SHA-256 is `8b28c6053ed18ed09bb4f1312590090966cbed3a67fea0c05e353d4cd9a5a5b2`; the current deployment test SHA-256 is `0d6466630fb28114a3b99c36524abb9fee0c84f0159c2a3f162e48cc5925368d`.

No Supabase login, linking, migration, hosted database, function, provider or credential-storage operations were performed by this task. Local metadata binds bytes and scopes; authentic external authority, final reviewed candidate delivery and hosted production acceptance remain separate.
