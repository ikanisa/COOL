# Admin observed client matrix

Observed exported-source SDK and widget tests. SQL receipts are retained parser inputs; no SQL, hosted provider, live navigation or persisted audit was executed by this gate.

Aggregate client gate passed: **False**. Full Admin acceptance: **false**.

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

## Remaining proof

- Source-only151 navigation installation and actual runtime navigation data.
- Each active custom action UI invalid/cancelled/reason/role and revocation states.
- Root-owned server authorization races, exact execution and persisted audit per active action.
- Typed roster149 recovery and real browser evidence in its separate packet.
- Required Revolut comparator, interaction and visual evidence per surface.

Each case, exact test source hash, packet hash, active endpoint and source mismatch is retained in matrix.json. Endpoint names in test titles and source references do not certify every UI or server state.
