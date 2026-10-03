# Inactive restore overlay — finite handoff

The approved owner-side restore stop is implemented and locally proved in this private packet. Root alone reviews/promotes its seven files. No canonical file or hosted/live configuration was changed. The default restore path is unchanged.

## Final source and results

Final SQL: `promote/scripts/sql/collect_inactive_restore_overlay.sql`, SHA `556ec1f13ae0d331d5495ac85c545a076b40946f082cceabf2b67738117384b3`, 25,680 bytes.

Helper: `promote/scripts/audits/collect_inactive_restore_overlay.rb`, SHA `f056cc9da956f6845a0fc003cf7bcecda45d48ebdcadf22fd76b611ec0b1953f`.

Parser: `promote/scripts/audits/collect_recovery_source.rb`, SHA `3a548f7b587234153496120d0b5883259b008fe1a45816fe3bd6d7117b0aaebe`. Expected original SHA `8a5d497cd75ecc2eaddf3c6195648c5e664f524b4688c87d2b2fdb083a49aeb0`.

Restore caller: `promote/scripts/tests/production_archive_restore.rb`, SHA `087c9325a768d9b3551790525f974230458e40079d9eb787438b708a0544ac9d`. Expected original SHA `1d2d12d076b76d02d6a36b41cb0a0830188607119b3efca020f96009ea362867`.

`PROMOTION_MAP.json` binds every new file, old source and exact two-file diff. The unchanged copied `collect_recovery_source_catalog.sql` is a staged dependency and must not be promoted as a change. The approved proposal is preserved byte-identically; implementation refinements and explicit limits are in `ADDENDUM.md`.

`proof/sql-attempt17/result.json` is terminal PASS: **78 actual driver checks and two outer binding/cleanup checks**, separately counted. Its result SHA is `a78c8379cba1d08ffcd1b0e43d35155a05e3c51cd0b9f673a913ceb96883fe31`. The actual 160 driver commands, input digests, output/error hashes and raw terminal receipts are retained. The final target `collect-recovery-inactive-1adeeef43e02` was removed. There is no live process handle.

The actual proof covers owner/NOSUPERUSER/cron admission, lock acquisition refusals and rollback of partial changes, actual shipping producer overlap, exact authority and causal append closure, source/input expiry/conflict, real helper commit and post-COMMIT response timeout, original UUID replay, private definition drift refusals, old-key/run-fence denials, late primary/successor callbacks and uncertainty, cold known-UUID reconstruction, same-target postmaster restart, private API role denial and immutable evidence guards. The new collation/default/index/namespace owner-ACL negatives and the preceding ENABLE ALWAYS negative operate only on private metadata in rollback-only transactions. Original/global evidence guards are never disabled.

`proof/final-units4/result.json` is terminal PASS with all captured inputs unchanged, SHA `d75215ca829bdcc57c60bf77ae6a5b6f032e81df4ef16dbf60e9edac16caf111`. Its distinct scopes are:

| Scope | Cases | Assertions |
| --- | ---: | ---: |
| New owner/result boundaries | 13 | 87 |
| Exact caller branch, synthetic adapter | 6 | 16 |
| Original source contract | 13 | 59 |
| Original restore functions | 7 | 25 |

Eleven Ruby syntax checks also passed. These are 39 finite cases with 187 assertions in four scopes; they do not duplicate or replace the 78 real SQL checks. No giant suite was replayed.

## Retained attempts

All 17 actual SQL attempts remain; `ATTEMPT_INDEX.json` binds each terminal receipt and separates old inputs. The small attempt4 pass, attempt15 73 + 2 and attempt16 74 + 2 are preceding-input evidence and are not added to final counts. All real failures are preserved, including source ambiguities, expiry/scalar framing, original-row append and freshness expectations, P256 fixture refusal, owner/catalog probe settings and exact run-fence refusal. The first unit dependency failure and the later tuple/JSON-array adapter summary failure remain retained; the final finite correction passed. An initial directory-preparation error had no retained raw receipt or target and is explicitly not counted.

`FINAL_CLEANUP.json` independently inspects all seventeen exact owned target names after acceptance. It also retains the separate manual absence receipt for failed entry attempt3. No unrelated container or unique proof was deleted.

## Source and scope associations

`FINAL_VALIDATION.json` revalidates original callers, current dependencies, all 208 canonical migration source files, final source/tool/runtime vectors and reused prerequisite identities. `MANIFEST.json` covers every regular owned member, including failed and accepted observations; `SEAL.json` hashes the manifest and final result vectors. External sealed packets and the selected archive remain thin SHA references, avoiding another giant archive copy.

The database fixture reuses the selected205 raw SQL and admits only exact 420/440/800 guard deltas. The 208 inventory is a current source/guard association, **not a full208 archive or complete migration replay**. The actual stop is ordinary NOSUPERUSER `postgres`; initial fixture DDL/read-only corpus comparisons and synthetic Auth setup have separate, explicit local roles. No production credential/role/Auth/isolation parity, signed hosted JWT or physical Android/carrier acceptance follows from this fixture.

Root integration still needs exact seven-file promotion and affected canonical caller acceptance. Complete encrypted Vault/current-graph recovery, native and scheduler custody joins, already-capsulated target restore cycles, offsite retention, hosted/device RPO/RTO and release acceptance remain separate. The postmaster restart keeps the same container/tmpfs/PGDATA and proves that local restart boundary only. Sequence/global-role limits remain unchanged. A stop preserves late investigation evidence and cannot recall an already armed native invocation. Resume requires fresh controlled owner decisions and fresh enrollment; revoked original keys cannot be reactivated.
