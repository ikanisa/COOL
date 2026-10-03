# Private BE-10 ordinary SQL CI proposal

`proposed-final/` is the sole review and promotion target. It contains six files: the existing CI workflow, a new canonical SQL runner, its focused boundary tests, and three narrowly selected fixtures. `proposed/`, `proposed-successor1/`, both frozen validation sources and every failed or successful proof remain retained precursors. No maintained source, APP, SDK, Docker, provider or canonical register was changed by this task. Root owns integration and the first actual execution of the new recipe.

The workflow preimage is `9ea409d2ef908441ecb72de72dc052f35d99133449952cc7df8549533612a624`. The final six-file diff is `proposal.patch`; `command-input-matrix.json` records the exact interfaces, command scopes, deadlines and unresolved acceptance boundaries. `packet-files.json` binds every retained packet file except itself.

## Proposed behavior and preserved SQL contract

`scripts/qa/run_sql_ci.py` captures the current 209 ordered migrations, four original helpers, workflow, runner, tests and three fixtures as 219 exact inputs before execution. It copies them into a fresh private source tree and runs the original `current_ordinary_installer_rehearsal.main`. The original helper files, migration SQL, 37 assertions, 18 projection fingerprints, complete clean and populated catalog comparisons, platform ownership checks, scheduler-disable readbacks and inner 120-second command bounds remain unchanged. A process-local adapter supplies the explicit Docker identity, extracted platform fixture and historical predecessor metadata; it records intended owned container names before creation and checks the Docker executable bytes before commands.

The new controller uses a 600-second whole bound, a 540-second execution allowance and a 60-second cleanup reserve. The execution reserve is stricter than the original rehearsal's outer 600-second allowance. Its local metadata commands have bounded output and deadlines. The original two unique containers retain `--pull=never`, `--network=none`, no published ports and 1 GiB tmpfs. Local installer setup still requires CREATE ROLE, CREATE DATABASE, BYPASSRLS and trusted platform memberships; these are a synthetic platform rehearsal prerequisite. They do not establish hosted ownership or least-privilege production acceptance.

The runner admits exact Python 3.12.14, a caller-pinned absolute physical Docker CLI, an explicit local Unix socket and the whole fixture manifest hash. It rejects unknown image IDs, platforms, runtime versions, changed fixture content, symlink inputs, source drift and arbitrary remote Docker hosts. It strips inherited provider and database credentials and uses an empty Docker configuration. An exact process-group absence observation is required after stop; permission refusal remains unknown until an actual ESRCH within the same five-second observation bound. Residual-group success and deadline completion are refused. Fallback container cleanup checks the exact registered name, image ID, ownership label, network mode and ports before removal, then requires actual absence readback. Using fallback cleanup makes the run fail; a daemon error does not prove absence.

Example interface after root promotion, with independently observed caller values supplied explicitly:

```text
<exact Python 3.12.14> scripts/qa/run_sql_ci.py \
  --docker <absolute physical Docker CLI> \
  --docker-sha256 <whole-file SHA256 of that CLI> \
  --docker-host unix:///<actual local Docker socket> \
  --fixture-lock-sha256 062f1f21d8ab847b4c94db4e4c86dc84af668157904e341e92bd9e6385c5f04d \
  --output .cache/sql-ci
```

This example provisions no real approval and performs no acquisition. The proposed CI job has `contents: read`, pinned existing actions, Python 3.12.14, `ubuntu-24.04-arm` and a 15-minute job bound. It separately acquires the named version tag `public.ecr.aws/supabase/postgres:17.6.1.095`, then requires image config ID `sha256:35ebf7c6d3b77a430146b0a91974ed1fc14432b5741db4a3e41cd5f899b17f1a`. Named-tag acquisition is mutable. Execution admits only that exact config ID, actual Linux/arm64 metadata and `--pull=never`. Prior 37-case evidence did not attest architecture or a registry RepoDigest; matching Linux/arm64 image availability remains an explicit prerequisite. The 13 original jobs and all original top-level workflow policies are preserved. No branch-protection or required-status setting is introduced.

## Narrow fixture provenance

`platform-bootstrap.sql` is the exact 50,231-byte output of the original helper's offline platform extraction from the retained schema-only dump, SHA256 `77262947961ac1a724195ea77bdb98088cebd30caecc625ded1d4a93ccbf6d3d`. It is byte-equal to the platform bootstrap used by the retained ordinary 37-case result. It contains 188 auth/storage schema blocks, omits the same seven application-owned triggers and copies no source rows. The full dump and cache history are not imported.

`predecessor.json` selects only the 124 historical migration names and versions from the retained dated hosted metadata, SHA256 `033232f7a67ff2eabec12e12c9f5023f2af6d055a6e2b948f5cfb9995391df8b`. The last historical ID is `20260906160000`; the current source contains 85 later migrations. No project keys, customer/Auth rows, Edge rows or current hosted claims are imported. `manifest.json` binds the fixtures, unchanged helpers, fixed runtime cohort, original case matrix and these provenance limits. Its final change corrects only the non-consumed acquisition description to say the named tag is mutable; `final-wording-binding.json` binds this exact change. Code, tests, SQL fixtures and all other manifest fields are unchanged from the proved successor.

## Actual proof and remaining gates

The first focused 17-case cohort genuinely completed with **16 passes and one error**, exit 1, in 3.096318 seconds. The detached-stdio descendant case raised a PermissionError during post-kill process-group observation. This failed attempt, traceback and all process traces are retained. Outer process-group absence was observed; the failed nested call did not return a receipt proving its own group's absence. A separate narrow shell diagnosis did not reproduce that permission refusal and is not treated as a proven environmental cause.

The successor changes only the post-SIGKILL observation loop: it tolerates a transient permission refusal within the existing five-second bound, while still requiring later actual ESRCH. All original 17 test bodies and every other runner function retain their ASTs. The unchanged failed case plus one new real-group test forcing a single transient probe refusal separately completed **2/2 passes**, exit 0, in 0.210985 seconds, with actual absence receipts. This is not an 18-case overall green result. The 16 unaffected prior outcomes are retained with exact semantic binding. `process-proof-summary.json`, `successor-semantic-binding.json` and both attempt directories identify the actual scopes and subprocess completions.

The maintained CI policy parser accepted the proposed workflow with no findings. Exact parsed comparison confirms the 13 previous jobs and top-level policies are unchanged. No actual GitHub job, Docker command, database replay, network acquisition or Linux recipe was run here. `final-preservation.json` binds the unchanged 226 original inputs and both 219-input validation cohorts; final seal readback binds the same original inputs again without overwriting either run.

The retained ordinary 209-migration/37-case result, committed recovery 27-case result and Linux 39-case shipping proof are dated separate evidence and were neither rerun nor rewritten. They do not constitute execution acceptance for this new canonical recipe. Root must review the six files and run the integrated recipe against its admitted local image before claiming current SQL acceptance. Full BE-10, hosted owner/runtime/history compatibility, shipping toolchain approval and production readiness remain open; the runner explicitly reports `full_BE10_closed: false`.
