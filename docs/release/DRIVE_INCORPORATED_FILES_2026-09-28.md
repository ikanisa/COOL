# Files incorporated from the COOL Drive review

The original integration manifest recorded **144 distinct Drive-sourced paths**: **135** current v2 source paths, **one** adapted historical ZIP test, **one** path with reviewed portions of an otherwise excluded candidate, and **seven** exact index/audit/evidence copies. Subsequent execution recovered **three additional current-v2 paths** that were missing locally, bringing the cumulative manifest to **147 paths**. Two raw source manifests were archived externally, so **145 manifested paths remain in the active repo**. This inventory is not production release approval. The [machine-readable manifest](DRIVE_INCORPORATED_FILES_2026-09-28.tsv) carries both selected Drive and repo SHA-256 values recorded at incorporation; later local changes may change current repo bytes.

For the 135 original current v2 paths, 113 matched the selected Drive candidate byte-for-byte and 22 had local adaptations at the integration snapshot. The historic test was adapted; the one safe-subset path was a partial incorporation. The seven index/evidence paths were exact copies at that snapshot. The late scope file was verified separately against the Drive current v2 bytes.

## New repo paths from current v2 (92)

| Repository path | Byte relation |
|---|---|
| `.github/workflows/hardening-contracts.yml` | exact Drive candidate |
| `android/app/src/main/kotlin/app/cool/mobile/receiver_sms/ReceiptAckPolicy.kt` | exact Drive candidate |
| `android/app/src/main/kotlin/app/cool/mobile/receiver_sms/ReceiptCipher.kt` | exact Drive candidate |
| `android/app/src/main/kotlin/app/cool/mobile/security/ProtectedSnapshotStore.kt` | exact Drive candidate |
| `android/app/src/main/kotlin/app/cool/mobile/security/SnapshotCipher.kt` | exact Drive candidate |
| `deploy/hardening/readiness_readonly.sql` | exact Drive candidate |
| `deploy/hardening/receipt_security_v2.sql` | exact Drive candidate |
| `deploy/hardening/reconciliation_approval_v2.sql` | exact Drive candidate |
| `deploy/hardening/signed_otp_limits_v2.sql` | exact Drive candidate |
| `docs/IMPLEMENTATION_DELIVERY.md` | exact Drive candidate |
| `docs/production/HARDENING_ROLLOUT.md` | exact Drive candidate |
| `docs/production/PROTECTED_CACHE_AND_VIEW_INTEGRATION.md` | exact Drive candidate |
| `docs/production/SECURITY_AND_OPERATIONS.md` | exact Drive candidate |
| `docs/production/VERIFICATION_MATRIX.md` | exact Drive candidate |
| `docs/release/ASSET_MANIFEST_INTEGRITY_2026-09-26.md` | exact Drive candidate |
| `docs/release/GROUP_SUMMARY_INTEGRITY_2026-09-26.md` | exact Drive candidate |
| `docs/release/HISTORY_INTEGRITY_2026-09-27.md` | exact Drive candidate |
| `docs/release/INTEGRATION_RECONCILIATION_2026-09-26.md` | exact Drive candidate |
| `docs/release/PAYMENT_DECODING_2026-09-27.md` | exact Drive candidate |
| `docs/release/PAYMENT_INTENT_DECODING_2026-09-27.md` | exact Drive candidate |
| `docs/release/RECOVERY_AND_LAZY_LISTS_2026-09-26.md` | exact Drive candidate |
| `docs/release/RECOVERY_INTEGRITY_2026-09-26.md` | exact Drive candidate |
| `docs/release/RECOVERY_RECONCILIATION_2026-09-26.md` | exact Drive candidate |
| `docs/release/RUNTIME_ASSET_VERIFICATION_2026-09-26.md` | exact Drive candidate |
| `docs/release/SUMMARY_DECODING_2026-09-27.md` | exact Drive candidate |
| `lib/admin/core/admin_list_paging.dart` | exact Drive candidate |
| `lib/core/security/durable_sms_receipt.dart` | exact Drive candidate |
| `lib/core/security/protected_snapshot_store.dart` | exact Drive candidate |
| `lib/shared/models/collect_payment_json.dart` | exact Drive candidate |
| `lib/shared/models/collect_summary_json.dart` | exact Drive candidate |
| `lib/shared/widgets/collect_form_viewport.dart` | exact Drive candidate |
| `scripts/hardening/ReceiptPolicyTest.kt` | exact Drive candidate |
| `scripts/hardening/SnapshotCipherTest.kt` | exact Drive candidate |
| `scripts/hardening/admin_headers.py` | exact Drive candidate |
| `scripts/hardening/admin_headers_test.py` | exact Drive candidate |
| `scripts/hardening/check_edge_types.py` | adapted after review |
| `scripts/hardening/contracts.test.cjs` | exact Drive candidate |
| `scripts/hardening/edge_http.test.cjs` | exact Drive candidate |
| `scripts/hardening/register_staged_sql.py` | exact Drive candidate |
| `scripts/hardening/release_gate.py` | exact Drive candidate |
| `scripts/hardening/release_gate_test.py` | exact Drive candidate |
| `scripts/hardening/restrict_drive_sharing.py` | exact Drive candidate |
| `scripts/hardening/run_contract_tests.py` | exact Drive candidate |
| `scripts/hardening/run_edge_http_tests.py` | exact Drive candidate |
| `scripts/hardening/run_jvm_tests.sh` | exact Drive candidate |
| `scripts/hardening/run_snapshot_jvm_tests.sh` | exact Drive candidate |
| `scripts/hardening/source_integration_test.py` | adapted after review |
| `scripts/hardening/source_inventory.py` | exact Drive candidate |
| `scripts/hardening/v2_source_test.py` | exact Drive candidate |
| `scripts/qa/asset_manifest_integrity.rb` | exact Drive candidate |
| `scripts/qa/group_runtime_integrity.rb` | adapted after review |
| `scripts/qa/run_compact_ui_checks.sh` | exact Drive candidate |
| `scripts/qa/run_integrated_candidate_checks.sh` | exact Drive candidate |
| `scripts/qa/run_recovery_checks.sh` | exact Drive candidate |
| `scripts/qa/run_recovery_list_checks.sh` | exact Drive candidate |
| `scripts/qa/verify_candidate.py` | exact Drive candidate |
| `scripts/tests/asset_hygiene_integration_test.rb` | adapted after review |
| `scripts/tests/asset_manifest_integrity_test.rb` | exact Drive candidate |
| `scripts/tests/group_runtime_integrity_test.rb` | exact Drive candidate |
| `scripts/tests/group_summary_source_test.py` | exact Drive candidate |
| `scripts/tests/member_history_source_test.py` | exact Drive candidate |
| `scripts/tests/payment_decoding_source_test.py` | exact Drive candidate |
| `scripts/tests/payment_intent_source_test.py` | exact Drive candidate |
| `scripts/tests/recovery_list_source_test.py` | exact Drive candidate |
| `scripts/tests/recovery_runner_test.py` | exact Drive candidate |
| `supabase/functions/_shared/integrity_policy.ts` | exact Drive candidate |
| `supabase/functions/_shared/production_contract.ts` | exact Drive candidate |
| `supabase/functions/_shared/receipt_ingestion.ts` | exact Drive candidate |
| `supabase/functions/_shared/roster_file_policy.ts` | exact Drive candidate |
| `supabase/functions/_shared/signed_sms_hook.ts` | adapted after review |
| `test/admin_filter_bar_responsive_test.dart` | exact Drive candidate |
| `test/admin_list_models_test.dart` | exact Drive candidate |
| `test/admin_list_paging_test.dart` | adapted after review |
| `test/admin_repository_paging_test.dart` | exact Drive candidate |
| `test/collect_disabled_action_regression_test.dart` | adapted after review |
| `test/collect_form_viewport_test.dart` | adapted after review |
| `test/collect_lazy_group_list_test.dart` | adapted after review |
| `test/connection_recovery_screen_test.dart` | adapted after review |
| `test/connection_recovery_screens_test.dart` | adapted after review |
| `test/form_viewport_namespace_test.dart` | exact Drive candidate |
| `test/group_summary_cache_recovery_test.dart` | adapted after review |
| `test/group_summary_decoding_test.dart` | adapted after review |
| `test/group_summary_integrity_test.dart` | adapted after review |
| `test/hardening/durable_sms_receipt_test.dart` | exact Drive candidate |
| `test/hardening/editorial_summary_availability_test.dart` | adapted after review |
| `test/hardening/protected_snapshot_store_test.dart` | exact Drive candidate |
| `test/member_history_controller_integrity_test.dart` | exact Drive candidate |
| `test/member_history_page_integrity_test.dart` | adapted after review |
| `test/payment_cache_integrity_test.dart` | exact Drive candidate |
| `test/payment_intent_cache_boundary_test.dart` | exact Drive candidate |
| `test/payment_intent_decoding_test.dart` | exact Drive candidate |
| `test/payment_json_integrity_test.dart` | exact Drive candidate |

## Existing paths updated from current v2 (30)

| Repository path | Byte relation |
|---|---|
| `.github/workflows/supabase-readiness.yml` | exact Drive candidate |
| `android/app/src/main/kotlin/app/cool/mobile/MainActivity.kt` | exact Drive candidate |
| `android/app/src/main/kotlin/app/cool/mobile/receiver_sms/CollectSmsReceiver.kt` | exact Drive candidate |
| `android/app/src/main/kotlin/app/cool/mobile/receiver_sms/SmsQueueStore.kt` | exact Drive candidate |
| `docs/release/ADMIN_SUPABASE_DEPLOYMENT_2026-09-04.md` | exact Drive candidate |
| `docs/release/GOOGLE_PLAY_SUBMISSION_1.2.4_23_2026-09-07.md` | exact Drive candidate |
| `ios/Runner/AppDelegate.swift` | exact Drive candidate |
| `lib/admin/core/admin_models.dart` | exact Drive candidate |
| `lib/admin/shared/components/admin_filter_bar.dart` | exact Drive candidate |
| `lib/core/security/sms_access_channel.dart` | exact Drive candidate |
| `lib/features/home/home_public_groups_section.dart` | exact Drive candidate |
| `lib/features/payments/contribute_entry_screen.dart` | exact Drive candidate |
| `lib/features/status/connection_recovery_screens.dart` | adapted after review |
| `lib/shared/repositories/collect_repository_history.dart` | exact Drive candidate |
| `lib/shared/repositories/collect_repository_providers.dart` | exact Drive candidate |
| `lib/shared/widgets/collect_foundation.dart` | exact Drive candidate |
| `lib/shared/widgets/collect_group_card_editorial.dart` | exact Drive candidate |
| `lib/shared/widgets/collect_group_card_metrics.dart` | adapted after review |
| `lib/shared/widgets/collect_group_cards.dart` | exact Drive candidate |
| `supabase/functions/_shared/apns.ts` | exact Drive candidate |
| `supabase/functions/_shared/cors.ts` | exact Drive candidate |
| `supabase/functions/_shared/fcm.ts` | exact Drive candidate |
| `supabase/functions/_shared/hash.ts` | exact Drive candidate |
| `supabase/functions/auth-send-whatsapp-otp/index.ts` | exact Drive candidate |
| `supabase/functions/dispatch-notifications/index.ts` | exact Drive candidate |
| `supabase/functions/ingest-payment-sms/index.ts` | exact Drive candidate |
| `supabase/functions/parse-payment-sms/index.ts` | exact Drive candidate |
| `supabase/functions/prepare-roster-import/index.ts` | exact Drive candidate |
| `supabase/functions/verify-play-integrity/index.ts` | exact Drive candidate |
| `test/admin_data_sync_test.dart` | adapted after review |

## Existing paths selected after review (8)

| Repository path | Byte relation |
|---|---|
| `assets/group_covers/rwanda/README.md` | exact Drive candidate |
| `assets/group_covers/rwanda/runtime-manifest.json` | exact Drive candidate |
| `lib/admin/core/admin_list_runtime.dart` | exact Drive candidate |
| `lib/admin/core/admin_runtime.dart` | exact Drive candidate |
| `lib/shared/models/collect_models.dart` | exact Drive candidate |
| `lib/shared/models/collect_payment_models.dart` | exact Drive candidate |
| `lib/shared/models/member_history_page.dart` | exact Drive candidate |
| `lib/shared/repositories/collect_repository_contribution_actions.dart` | exact Drive candidate |

## Current v2 merged with local code (5)

| Repository path | Byte relation |
|---|---|
| `lib/features/home/home_screen.dart` | exact Drive candidate |
| `lib/features/payments/contribution_flow_screen.dart` | adapted after review |
| `lib/shared/repositories/collect_offline_cache.dart` | adapted after review |
| `lib/shared/repositories/collect_repository.dart` | adapted after review |
| `lib/shared/repositories/collect_repository_live_reader.dart` | exact Drive candidate |

## Adapted historical ZIP source (1)

| Repository path | Byte relation |
|---|---|
| `test/group_list_summary_availability_test.dart` | adapted historical ZIP source |

## Reviewed portions of excluded full candidates (1)

| Repository path | Byte relation |
|---|---|
| `.github/workflows/ci.yml` | reviewed portion only; full candidate excluded |

## Late recovered Drive source (3)

| Repository path | Byte relation and reason |
|---|---|
| `scripts/qa/candidate_check_scope.json` | Exact current v2 Drive bytes (`06107e7efb9a22e333ce13f73870ba47daeb999e0194fbb51b8eaf005a0dd2f4`); required by the imported candidate verifier and source tests. Its absence was discovered when those tests ran. |
| `scripts/tests/integrated_candidate_runner_test.py` | Exact current v2 Drive bytes; 17 fake-SDK tests verify missing toolchains, version pins and fail-closed orchestration. |
| `scripts/tests/candidate_runner_test.py` | Current v2 Drive test adapted for this repo's explicitly scoped 25-suite verifier and full-suite CI; 27 fake-SDK tests pass. |

`scripts/tests/asset_hygiene_integration_test.rb` was already one of the original 144 manifested paths but disappeared from the active tree during this work. It was restored from current v2 Drive bytes, then its final authority assertion was limited to `revolut-design`; its eight isolated tests pass. Its older adapted bytes (`40a61914ec72a4ba4c129d0bc04151293775c43c620f03ade0aae85c36e32589`) are preserved in the pre-edit archive outside the repo; those bytes asserted the retired rule and are unsuitable under the owner's current instruction.

The selected current-v2 Drive source contains 190 files. A fresh path comparison after these recoveries leaves seven source paths absent by decision: two retired parity contracts, three retired scoring scripts/tests, and two guards specific to the retired rule. Their original bytes remain in the external Drive review archive. This is a selected-v2 path reconciliation, not a claim that every archived ZIP member is active application source.

## Exact Drive index and audit evidence (7)

| Repository path | Byte relation |
|---|---|
| `00_ALL_COOL_DELIVERABLES_2026-09-28.md` | exact Drive bytes |
| `docs/release/drive-evidence/AUDIT_2026-09-27.md` | exact Drive bytes |
| `docs/release/drive-evidence/FINDINGS_REGISTER_2026-09-27.json` | exact Drive bytes |
| `docs/release/drive-evidence/MASTER_FILE_MANIFEST_2026-09-28.json` | archived externally with exact Drive bytes |
| `docs/release/drive-evidence/V2_SOURCE_MANIFEST_2026-09-27.json` | archived externally with exact Drive bytes |
| `docs/release/drive-evidence/V2_TASK_REGISTER_2026-09-27.csv` | exact Drive bytes |
| `docs/release/drive-evidence/V2_TASK_REGISTER_2026-09-27.json` | exact Drive bytes |

## Local follow-up files prompted by the comparison

These seven paths were locally corrected or authored during the review; they are **not counted** among the Drive-sourced paths. Further local changes within the 135-path overlay, including `lib/shared/repositories/collect_repository.dart` and `test/group_summary_integrity_test.dart`, are represented above as adapted paths.

| Repository path | Role |
|---|---|
| `lib/features/collections/collections_screen.dart` | Local correction or fixture update |
| `lib/features/collections/collection_detail_screen.dart` | Local correction or fixture update |
| `lib/features/collections/collection_manage_screen.dart` | Local correction or fixture update |
| `lib/features/collections/share_screen.dart` | Local correction or fixture update |
| `lib/features/ledger/ledger_screen.dart` | Local correction or fixture update |
| `test/fixtures/collect_repository_fixture.dart` | Local correction or fixture update |
| `docs/release/drive-evidence/README.md` | Evidence context written locally |

## Other reviewed Drive files

The current v2 reconciliation also records **22 paths already byte-identical before integration** and **33 full candidates excluded for policy or provenance reasons**. The partial path listed above is among those 33 full candidates. The [Drive-only disposition](EXTERNAL_REVIEW_EVIDENCE_2026-09-28.md) covers **613 additional downloaded paths** kept in external evidence; that count was the original disposition, before the scope file's late recovery. The [recursive ZIP inventory](EXTERNAL_REVIEW_EVIDENCE_2026-09-28.md) and [ZIP source variants](EXTERNAL_REVIEW_EVIDENCE_2026-09-28.md) cover archived members. The [comparative integration report](DRIVE_COMPLETE_COMPARATIVE_INTEGRATION_2026-09-28.md) explains the feature and release decisions.

The retired scoring rule is absent from current release commands. Visual review remains open under `revolut-design`; this manifest does not authorize an APK, deployment, or release.
