# Admin observed client matrix

Observed exported-source SDK and widget tests. SQL receipts are retained parser inputs; no SQL, hosted provider, live navigation or persisted audit was executed by this gate.

Aggregate client gate passed: **True**. Full Admin acceptance: **false**.

Protected route state cases: **182/182** observed passes.

| Route | Allowed | Loading | Empty | Revoked | Signed out | Non Admin | No capability | Retry |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| /admin | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| /admin/groups | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| /admin/groups/:id | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| /admin/users | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| /admin/users/:id | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| /admin/members | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| /admin/members/:id | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| /admin/payees | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| /admin/transactions | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| /admin/transactions/:id | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| /admin/reconciliations | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| /admin/ledgers | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| /admin/sms-receipts | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| /admin/sms-receipts/:id | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| /admin/notifications | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| /admin/notifications/:id | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| /admin/audit-logs | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| /admin/settings | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| /admin/feature-flags | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| /admin/system-health | PASS | PASS | N/A | PASS | PASS | PASS | PASS | PASS |
| /admin/automations | PASS | PASS | N/A | PASS | PASS | PASS | PASS | PASS |
| /admin/admin-users | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| /admin/admin-users/:id | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |

## Observed custom action states

**143/143** observed passes using actual production widgets and the locked SDK against synthetic HTTP.

| UI action | Operation | Passing states |
| --- | --- | --- |
| createGroup | admin_create_platform_public_group | 11/11 |
| createPayee | admin_create_collect_payee | 11/11 |
| editPayee | admin_update_collect_payee | 11/11 |
| deactivatePayee | admin_set_collect_payee_status | 11/11 |
| activatePayee | admin_set_collect_payee_status | 11/11 |
| deactivateGroup | admin_set_group_active | 11/11 |
| activateGroup | admin_set_group_active | 11/11 |
| approveGroup | admin_update_collection_support_status | 11/11 |
| rejectGroup | admin_update_collection_support_status | 11/11 |
| metadata | admin_update_platform_public_group_metadata | 11/11 |
| note | admin_record_operator_note | 11/11 |
| profileNote | admin_record_operator_note | 11/11 |
| featureFlag | admin_set_feature_flag_v2 | 11/11 |

## Coverage associations and limits

Active endpoints: **62**. Endpoints with no named or reviewed alias passing case: **13**.

Operation aliases are reviewed against their declaring test source; source string references alone are not execution proof. Provider reference cohorts record direct references and reviewed indirect production consumers, with every state still independently bounded.

- Operation association gaps: admin_commit_roster_import, admin_execute_roster_import_intent, admin_get_interrupted_roster_commit_status, admin_get_roster_import, admin_get_roster_transfer_status, admin_inspect_interrupted_roster_import, admin_list_interrupted_roster_imports, admin_recover_roster_import, admin_review_roster_import, admin_save_roster_import_draft, admin_stage_roster_import_intent, admin_transfer_interrupted_roster_import, prepare-roster-import
- Provider association gaps: adminAuthStateProvider, adminSmsQueueHealthProvider, adminAutomationHealthProvider, adminDetailRecordProvider, adminRealtimeSubscriptionProvider
- Dated actual149 decoder passed: None
- Browser-only roster storage/reload scenarios are covered by their separate actual browser packet, not the VM gate.

## Remaining proof

- Current installed navigation/server identity is verified by root-owned packets; route fixtures do not prove current database installation.
- Independent financial step-up, platform-access and roster UI proof are in their named cases and separate packets; listed custom widget states are not a whole Admin visual claim.
- Root-owned server authorization races, exact execution and persisted audit per active action.
- Dated actual149 recovery decoder is a copied parser input when included; normal browser and current server recovery proof remain separately bound.
- Required Revolut comparator, interaction and visual evidence per surface.

Each case, exact test source hash, packet hash, active endpoint and source mismatch is retained in matrix.json. Endpoint names in test titles and source references do not certify every UI or server state.
