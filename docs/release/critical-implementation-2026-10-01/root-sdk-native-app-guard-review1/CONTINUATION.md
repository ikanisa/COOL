Preservation support only; packet1 stage continuation withdrawn

Independent review found generated-membership omissions in the sealed packet1 reader. This directory grants no app-export, app-lock or native execution authority. Root requires a corrected preparation2 reader and review2. The sealed packet1 and old 37-test/guard proof remain historical evidence.

The preservation plan is read-only and binds 2,920 APP nodes, 25 app-export-control nodes and 14 app-lock-control nodes, including all 13 raw SwiftPM links. Each regular file is hashed through the unchanged pinned original safe reader; node kind, device, inode, mode, nlink, size, mtime, ctime, uid and gid are compared twice. All 12 current DROP source hashes matched. Root's separately created source-fence.json and preparation-review.json were not modified.

Root must first complete the corrected preparation2 full read-only candidate proof. After root review of the helper and concrete plan, preserve with:

```sh
/Volumes/PRO-G40/Development/Python/codex-agents-venv/bin/python3 -I -B /Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/docs/release/critical-implementation-2026-10-01/root-sdk-native-app-guard-review1/preserve_failed_candidate.py --mode preserve --plan-sha256 fbb5fd3721184f77a1634c1a2492790057731dc2c1b6b3781bd48ab6614f6e7b
```

The exact unique archive destination is recorded in preservation-plan.json. Each source is renamed only on its own physical volume, then reread for exact bytes and identities. Only the renamed root directory ctime may change; its before/after values are recorded. The archive preserves links as raw lstat/readlink nodes and never follows or rewrites their targets. Archived absolute links may dangle or later name a fresh APP; always treat them as inert evidence.

The three-tree sequence is not a transaction. An intent record precedes each atomic rename and a verified record follows it. Retain any partial archive after failure; do not roll back, delete or blindly rerun. Re-plan after any candidate/control/archive-parent/current12 change. The 300 second bound and live 4 GiB floor remain enforced. Plan comparisons do not attest source locks, exclusive source scope or absence of transient write/restore. No preservation, exporter, Flutter, Gradle or real stage was executed by this agent.
