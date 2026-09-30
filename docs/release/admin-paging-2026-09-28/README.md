# D07 Admin paging review — 2026-09-28

## Implemented locally

- `loadAdminListPage` requests 25 server rows per page, retains the fetched offset and total, and re-requests the last valid page when a nonzero total shows a deletion moved it. It now verifies page zero before accepting `total: 0` from an expired nonzero offset. This is needed because several older list RPCs calculate `total` from `count(*) over ()` inside a paged CTE; an empty page therefore loses the real total.
- `AdminRepository.list` rejects limits outside the backend's 1–100 range before the RPC, validates the exact returned window and unique IDs, and rejects Rwanda-scoped rows without an explicit `country_code: RW`. The scoped endpoint remains mandatory; permission or missing-function errors do not fall back to unscoped lists.
- Added 25/26/50/51 row boundary cases, expired-offset `total: 0` recovery, and repository country-response tests. Existing search/status/sort forwarding, permission-failure, malformed-window, duplicate-ID and overview tests also pass.

## Source findings requiring database verification or further SQL work

1. **Live role and country scope:** `admin_list_country_scoped` restricts its RPC names and calls the underlying Admin list functions, which assert permissions. Its final country filter runs before its requested page window. This was source-reviewed, not exercised against a deployed Supabase instance. Run each enabled queue as an authorized Admin and an authenticated non-Admin; verify 25/26/50/51/101 rows, both sorts, search/status filters, zero results, cross-country rows, and revoked access. Compare each response's IDs and exact total to a privileged snapshot. The source-only repository validation is an additional safeguard, not an authorization substitute.
2. **Ordering and duplicate boundaries:** Six latest active five-argument RPC definitions choose a page using `p_sort` but build its JSON array with a fixed `order by created_at desc`. Their page order lacks an ID tie breaker for equal timestamps. They are:

   | RPC | Latest definition | Paged selection | JSON order |
   | --- | --- | --- | --- |
   | `admin_list_collect_payees` | `20260901160000_collect_admin_payee_management.sql:46` | `:101-107` | `:110-119` |
   | `admin_list_collect_transactions` | `20260901183000_admin_operations_tables.sql:8` | `:122-130` | `:133-137` |
   | `admin_list_collect_reconciliations` | `20260831095454_collect_admin_operations_model.sql:373` | `:507-513` | `:516-520` |
   | `admin_list_collect_ledgers` | `20260903084000_hybrid_direct_ussd_financial_core.sql:2243` | `:2336-2342` | `:2345-2352` |
   | `admin_list_collections` | `20260901183000_admin_operations_tables.sql:145` | `:228-234` | `:237-245` |
   | `admin_list_users` | `20260901183000_admin_operations_tables.sql:272` | `:335-341` | `:344-352` |

   For each, `created_at_asc` can display the selected 25 rows in reverse order, and equal timestamps at a page boundary can overlap or omit IDs across requests. The source-side `count(*) over ()` also loses the total when the selected offset has no rows; the local Dart recovery now handles this display case. The country wrapper at `20260901220000_admin_country_scope_contract.sql:129` concatenates the underlying 100-row batches in their returned order, filters by country, then applies its own offset. Correcting the wrapper alone cannot restore IDs lost at an unstable source batch boundary. An additive SQL replacement must update all six source RPCs to use a single deterministic rank for page selection and JSON aggregation, derive the total independently of the selected page, and preserve their distinct permission assertions and search/status predicates. The transaction and reconciliation sources also contain multirow joins that require duplicate-ID fixtures. A client cannot reconstruct missing rows from an unstable server window.

   The remaining active sources already carry a consistent rank through JSON aggregation: `admin_list_members` and `_admin_list_people_by_membership` in `20260903200322_hybrid_directory_presentation.sql`, and `admin_list_notifications` in `20260815062536_complete_admin_operations_control_plane.sql`. Their deployed behavior still needs readback.
3. **Scale:** `admin_list_country_scoped` walks every 100-row source batch, accumulates all rows in one JSONB value, resolves country row by row, then applies the caller's 25-row offset. Its memory, latency and query plan require representative-volume measurement. Move filtering into indexed relational SQL before pagination if the staging plan exceeds the release budget.
4. **Historical populations:** The active product is Rwanda MoMo only, but historical bank/diaspora rows remain for controlled audit retention. Confirm the country's authoritative resolution and every enabled Admin queue's access policy against those historical records before production release.

## Verification

`flutter test --no-pub test/admin_list_paging_test.dart test/admin_list_models_test.dart test/admin_repository_paging_test.dart test/admin_data_sync_test.dart test/admin_overview_totals_test.dart` — **75 passed**.

No migration was applied or production Admin system queried. D07 remains **partial** until deployed role, country, filter, ordering and representative-volume checks pass.

**SQL implementation decision:** No new SQL migration was staged in this pass. The correction spans six different security-definer functions, two overloaded public RPC names, and the country wrapper. A wrapper-only migration would silently retain source-boundary loss. Replacing all definitions without a full-schema staging replay and role/fixture tests could change access or filtered totals. The matrix above is the bounded migration scope for the database rehearsal.
