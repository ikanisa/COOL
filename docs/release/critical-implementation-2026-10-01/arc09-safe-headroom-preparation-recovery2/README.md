Private unexecuted recovery2 for the first cleanup helper's actual Git CLI failure. The original proposal and root failure remain intact.

Installed Git refused `check-ignore -z` with argv paths: exit 128, `fatal: -z only makes sense with --stdin`. The derivative uses `check-ignore --stdin -z` and supplies the exact eight NUL-terminated input paths through `subprocess.run(input=...)`. The parser requires exit 0, no stderr, exactly eight NUL records and the same exact path set.

The new helper's actual read-only Git invocation passed: eight matching ignored paths; zero tracked paths. Fresh source identities and SHA256 hashes for all eight caches still match the original observation; the proposed internal destination remains absent. No copying, deletion, lsof, Gradle, cache/source mutations, networking or signals occurred. Seven unaffected pure fixtures and all original admission/preservation controls are reused.

Only stdin plumbing, ignore argv and an explicit eight-output-record count changed. The selected eight files, 121,842,984 bytes, exact internal destination, 15-second Git/lsof bounds, 300-second stage, copy/no-open/guard/refusal behavior and unchanged 4 GiB build floor are retained. The exact root-owned retry command is in root-plan.json.
