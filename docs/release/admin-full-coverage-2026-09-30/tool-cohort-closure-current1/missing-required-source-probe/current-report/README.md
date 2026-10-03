# Admin observed client matrix

Observed exported-source SDK and widget tests. SQL receipts are retained parser inputs; no SQL, hosted provider, live navigation or persisted audit was executed by this gate.

Aggregate client gate passed: **True**. Full Admin acceptance: **false**.

Inventory client inputs match tested export: **False**. Missing required inputs: **1**; changed shared inputs: **0**.

Protected route state cases: **0/0** observed passes.

| Route | Allowed | Loading | Empty | Revoked | Signed out | Non Admin | No capability | Retry |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |

## Observed custom action states

**0/143** observed passes using actual production widgets and the locked SDK against synthetic HTTP.

| UI action | Operation | Passing states |
| --- | --- | --- |
| createGroup | admin_create_platform_public_group | 0/11 |
| createPayee | admin_create_collect_payee | 0/11 |
| editPayee | admin_update_collect_payee | 0/11 |
| deactivatePayee | admin_set_collect_payee_status | 0/11 |
| activatePayee | admin_set_collect_payee_status | 0/11 |
| deactivateGroup | admin_set_group_active | 0/11 |
| activateGroup | admin_set_group_active | 0/11 |
| approveGroup | admin_update_collection_support_status | 0/11 |
| rejectGroup | admin_update_collection_support_status | 0/11 |
| metadata | admin_update_platform_public_group_metadata | 0/11 |
| note | admin_record_operator_note | 0/11 |
| profileNote | admin_record_operator_note | 0/11 |
| featureFlag | admin_set_feature_flag_v2 | 0/11 |

## Typed SDK, provider and approval-panel states

| Cohort | Observed finite states |
| --- | --- |
| Gateway SDK and providers | 0/66 |
| Gateway production SDK dialogs | 0/65 |
| Private authority SDK providers | 0/70 |
| Loaded private production detail | 0/14 |
| Exceptions SDK and providers | 0/38 |
| Gateway checkpoint decoder | 0/13 |
| Gateway checkpoint production page | 0/11 |
| Actual Chrome checkpoint adapters | 0/5 |
| Email approval SDK | 0/30 |
| Email approval production panel | 0/8 |

## Current active consumer cohorts

| Consumer cohort | Passing finite events | Source |
| --- | --- | --- |
| entity_history_sdk_authority | 0/0 | test/admin_entity_audit_authority_test.dart |
| entity_history_production_page | 0/0 | test/admin_entity_audit_page_test.dart |
| receipt_sdk_authority_ack_uncertainty | 0/0 | test/admin_receipt_cancel_sdk_authority_test.dart |
| receipt_production_card | 0/0 | test/admin_receipt_cancel_card_test.dart |
| unattended_preparation_policy_sdk_and_card | 0/0 | test/admin_operating_policy_runtime_test.dart |
| feature_flag_runtime_ack_and_session | 0/0 | test/admin_feature_flag_runtime_test.dart |
| notification_preference_sdk_and_session | 0/0 | test/shared/notification_preference_runtime_test.dart |
| notification_settings_production_recovery | 0/0 | test/features/notification_preferences_recovery_ui_test.dart |
| entity_history_enabled_links | 0/0 | test/admin_entity_audit_links_test.dart |
| exception_workflow_production_and_checkpoint | 0/0 | test/admin_exception_workflow_test.dart |
| exception_workflow_sdk_ack_and_session | 0/0 | test/admin_exception_workflow_sdk_test.dart |
| receipt_content_versioned_decoder | 0/0 | test/admin_receipt_content_v2_test.dart |
| receipt_deferral_sdk_and_evidence_dialog | 0/0 | test/admin_receipt_deferral_test.dart |
| receipt_worker_health_sdk_and_production_card | 0/0 | test/admin_receipt_worker_health_test.dart |
| receipt_operations_models | 0/0 | test/admin_receipt_operations_models_test.dart |
| receipt_operations_sdk_ack_and_session | 0/0 | test/admin_receipt_operations_sdk_test.dart |
| receipt_operations_controller_and_authority | 0/0 | test/admin_receipt_operations_runtime_test.dart |
| receipt_operations_production_card | 0/0 | test/admin_receipt_operations_card_test.dart |
| receipt_operations_checkpoint | 0/0 | test/admin_receipt_operations_checkpoint_test.dart |
| receipt_operations_actual_browser_checkpoint | 0/0 | test/admin_receipt_operations_checkpoint_browser_test.dart |

Admin /settings reads admin_list_settings. Admin feature-flag changes are in /feature-flags with reason/ACK/session tests. Member NotificationSettingsScreen uses the separately declared production preference-recovery cohort; no Admin preference editor is invented.

Source-bound finite SDK/provider/panel assertions; mock HTTP runs the locked SDK. TimeoutException is synthetic loss, not network retransmission proof. Dated Gateway DTO observations are decoder inputs, not current server installation. These cohorts do not certify every dialog/action or server state.

## Coverage associations and limits

Active endpoints: **0**. Endpoints with no named or reviewed alias passing case: **0**.

Operation aliases are reviewed against their declaring test source; source string references alone are not execution proof. Provider reference cohorts record direct references and reviewed indirect production consumers, with every state still independently bounded.

- Operation association gaps: 
- Provider association gaps: 
- Dated actual149 decoder passed: None
- Browser-only roster storage/reload scenarios are covered by their separate actual browser packet, not the VM gate.

## Remaining proof

- Current installed navigation/server identity is verified by root-owned packets; route fixtures do not prove current database installation.
- Independent financial step-up, platform-access and roster UI proof are in their named cases and separate packets; listed custom widget states are not a whole Admin visual claim.
- Root-owned server authorization races, exact execution and persisted audit per active action.
- Dated actual149 recovery decoder is a copied parser input when included; normal browser and current server recovery proof remain separately bound.
- Required Revolut comparator, interaction and visual evidence per surface.

Each case, exact test source hash, packet hash, active endpoint and source mismatch is retained in matrix.json. Endpoint names in test titles and source references do not certify every UI or server state.
