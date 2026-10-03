# Admin observed client matrix

Observed exported-source SDK and widget tests. SQL receipts are retained parser inputs; no SQL, hosted provider, live navigation or persisted audit was executed by this gate.

Aggregate client gate passed: **False**. Full Admin acceptance: **false**.

Protected route state cases: **0/190** observed passes.

| Route | Allowed | Loading | Empty | Revoked | Signed out | Non Admin | No capability | Retry |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| /admin | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| /admin/groups | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| /admin/groups/:id | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| /admin/users | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| /admin/users/:id | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| /admin/members | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| /admin/members/:id | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| /admin/payees | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| /admin/transactions | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| /admin/transactions/:id | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| /admin/reconciliations | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| /admin/ledgers | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| /admin/sms-receipts | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| /admin/sms-receipts/:id | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| /admin/notifications | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| /admin/notifications/:id | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| /admin/audit-logs | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| /admin/settings | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| /admin/feature-flags | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| /admin/system-health | PENDING | PENDING | N/A | PENDING | PENDING | PENDING | PENDING | PENDING |
| /admin/automations | PENDING | PENDING | N/A | PENDING | PENDING | PENDING | PENDING | PENDING |
| /admin/sms-gateway | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| /admin/admin-users | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| /admin/admin-users/:id | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |

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
| Gateway SDK and providers | 60/66 |
| Email approval SDK | 0/30 |
| Email approval production panel | 0/8 |

Source-bound finite SDK/provider/panel assertions; mock HTTP runs the locked SDK. TimeoutException is synthetic loss, not network retransmission proof. Dated Gateway DTO observations are decoder inputs, not current server installation. These cohorts do not certify every dialog/action or server state.

## Coverage associations and limits

Active endpoints: **71**. Endpoints with no named or reviewed alias passing case: **66**.

Operation aliases are reviewed against their declaring test source; source string references alone are not execution proof. Provider reference cohorts record direct references and reviewed indirect production consumers, with every state still independently bounded.

- Operation association gaps: admin_approve_email_operator_v1, admin_approve_whatsapp, admin_commit_roster_import, admin_create_collect_payee, admin_create_platform_public_group, admin_current_user, admin_execute_roster_import_intent, admin_get_admin_user, admin_get_collect_investigation_v1, admin_get_collect_transaction, admin_get_collection, admin_get_hybrid_sms_receipt, admin_get_interrupted_roster_commit_status, admin_get_member_record, admin_get_notification, admin_get_operator_approval_v1, admin_get_queue_sla, admin_get_roster_import, admin_get_roster_transfer_status, admin_get_user, admin_inspect_interrupted_roster_import, admin_list_admin_users, admin_list_audit_logs, admin_list_collect_ledgers, admin_list_collect_payees, admin_list_collect_reconciliations, admin_list_collect_transactions, admin_list_collections, admin_list_country_scoped, admin_list_feature_flags, admin_list_hybrid_sms_receipts, admin_list_interrupted_roster_imports, admin_list_members, admin_list_non_member_users, admin_list_notifications, admin_list_platform_payee_candidates, admin_list_settings, admin_overview, admin_receipt_overview_v1, admin_record_operator_note, admin_recover_roster_import, admin_retry_notification, admin_reveal_raw_sms, admin_review_roster_import, admin_revoke_email_operator_v1, admin_revoke_whatsapp_approval, admin_runtime_config, admin_save_roster_import_draft, admin_set_collect_payee_status, admin_set_feature_flag_v2, admin_set_group_active, admin_set_user_access, admin_stage_roster_import_intent, admin_system_health, admin_transfer_interrupted_roster_import, admin_update_collect_payee, admin_update_collection_support_status, admin_update_platform_public_group_metadata, approve_payment_reconciliation_v2, collect-notification-operator, get_payment_reconciliation_v2, list_collect_shadow_runs_v1, list_payment_reconciliations_v2, prepare-roster-import, propose_payment_reconciliation_v2, reconciliation-finalize
- Provider association gaps: adminRouterProvider, adminAuthStateProvider, adminAuthUserIdProvider, adminAuthGuardProvider, adminSmsQueueHealthProvider, adminAutomationHealthProvider, adminInvestigationProvider, _adminQueueViewStatesProvider, adminReceiptOverviewProvider, adminOverviewOperationalHealthProvider, adminOverviewSmsHealthProvider, _adminOverviewWorkspaceProvider, adminReconciliationSessionKeyProvider, adminReconciliationMfaTransportProvider, adminReconciliationStepUpProvider, _adminIdentityRevisionProvider, adminRealtimeTickProvider, adminLastSuccessfulRefreshProvider, adminCountryScopeProvider, adminRuntimeConfigProvider, adminDetailRecordProvider, adminRealtimeSubscriptionProvider, adminShadowRunsProvider
- Dated actual149 decoder passed: None
- Browser-only roster storage/reload scenarios are covered by their separate actual browser packet, not the VM gate.

## Remaining proof

- Current installed navigation/server identity is verified by root-owned packets; route fixtures do not prove current database installation.
- Independent financial step-up, platform-access and roster UI proof are in their named cases and separate packets; listed custom widget states are not a whole Admin visual claim.
- Root-owned server authorization races, exact execution and persisted audit per active action.
- Dated actual149 recovery decoder is a copied parser input when included; normal browser and current server recovery proof remain separately bound.
- Required Revolut comparator, interaction and visual evidence per surface.

Each case, exact test source hash, packet hash, active endpoint and source mismatch is retained in matrix.json. Endpoint names in test titles and source references do not certify every UI or server state.
