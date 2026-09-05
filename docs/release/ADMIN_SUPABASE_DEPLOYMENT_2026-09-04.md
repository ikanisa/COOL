# Admin and Supabase deployment — 4 September 2026

**Admin and the pending database migration are deployed and verified. Mobile
distribution remains NO-GO under MOBILE-DESIGN-100.**

Jean Bosco explicitly requested deployment and verification of the credentials
in the Google Sheet named Supabase. The subsequent Home correction is implemented
and checked locally on an isolated Android emulator; it is not installed on the
physical phone or distributed as a release.

## Credentials and target

The existing [Supabase spreadsheet](https://docs.google.com/spreadsheets/d/1s6EKXqI1D6EgS83gDqBX8yViOHYWxTO71g2JBEe2wHw/edit),
tab Sheet7, identifies project `lhbowpbcpwoiparwnwgt` / COOL. Its Management access
token, project reference, URL and public anon key match the local configuration.
The token successfully returned the project as ACTIVE_HEALTHY, and the Sheet's
anon key matches the live project's key. No credential value is included here.

## Production database

- Applied only `20260903201326_geographic_member_profile_gates.sql`, SHA-256
  recorded in the private `deployment/migration-plan.json` evidence.
- A fresh preflight found exactly one pending migration. The migration and its
  history row were committed together through the HTTPS Management API.
- Production and local migration histories now match at **122 migrations**.
- Saved the five replaced function definitions, owners and ACLs before applying.
  All existing owners and ACLs match after deployment. The three new internal
  profile helpers deny EXECUTE to anon, authenticated and service_role.
- The isolated rollback UAT passed **29 checks** before production application.
- Counts before/after remain: 5 groups, 9 profiles, 3 memberships, 9 member
  records, 3 raw SMS, 3 parsed events, no posted payments and no ledger rows.
- Security advisors: 190 WARN and 46 INFO, unchanged; performance: 128 INFO,
  unchanged. **Zero new findings**, comparing substantive fields and excluding
  the refreshed `observed_at` timestamp. Existing findings are still open.

The migration adds backend profile-readiness checks to group joining/creation
and contribution intents. It does not enable rollout flags or post money.

## Production Admin

[Collect Admin](https://admin.collect.ikanisa.com) runs Worker version
`b97134af-032b-4e75-8c0c-4c217c97392e` at **100% traffic**, independently read back
from deployment `dce57c72-02e8-4e28-9936-48c159dd3d3e`.
Previous version `1b868d4f-1da5-4ecd-8d41-323616b87110` is the rollback target.

The production build and hosting gates passed. The custom-domain live gate
passed, and the four remote assets match the local production build byte for byte:

| Asset | SHA-256 |
| --- | --- |
| main.dart.js | `e241614f6cd25444a975e2f826aaba2ec6fed9590dbcec6ea4a3cee2723abc79` |
| custom-sw.js | `129c85811e2c6d59fb018684fee130c5049a68e611d6634cf42e1c1ef7265b17` |
| flutter_bootstrap.js | `5da85b9bfd2d01b22504d0de9e66e3d5c40ca8857d81dca41344c047446fd4cc` |
| manifest.json | `65ceb8861614591828d638d720df08496c8e250138d8c9b6ed149f2d18261eb9` |

The bundle contains the expected Supabase project and corrected labels; checked
fixture markers are absent. After the existing browser activated the updated
service worker, authenticated readback showed:

- `Oldest visible item`, and `Awaiting approvals: Not available`.
- 3 open reconciliations, 0 unallocated transactions, 0 balanced ledgers,
  2 active payees, matching database-backed metrics.
- Groups: **5 total, 2 public, 3 private, 0 archived**. Buri Munsi and Gikundiro
  both appear as platform-sponsored public groups.
- Ten observed Supabase RPC resources returned HTTP 200 from the expected
  project. No uncaught errors or unhandled promise rejections were observed
  during the instrumented Groups navigation.

Country filtering now retains server pagination and server totals beyond the
old 100-row cap. The current live database has only five groups; the beyond-100
case is covered by the reproducing regression test, not a fabricated live count.

## Home correction

The old Home discovery provider excluded a public group when the current user
joined or owned it. Home now renders **Featured groups** from active public
records regardless of membership, alongside **My groups**. Titles, IDs, images,
capabilities and amounts continue to come from repository/backend records; no
Buri Munsi/Gikundiro allowlist was added. The live public view, read with the
Sheet's anon key, independently returned those two current public groups.

Regression coverage verifies joined/discovery/mixed states, title changes and
removal from public visibility, empty/loading/error/offline states, compact and
tablet widths, 200% text, light mode and group navigation. **32 focused tests
passed** across Home, Admin data sync and repository contracts; analysis is clean.

The isolated `app.cool.mobile.dev` Android 16/API 36 run passed the joined Home
state at 393×851 dp. Three fresh images were opened and visually inspected:

- `.cache/admin-data-audit-20260904/home-native-dev/screenshots/mobile_state_home-joined.png`
- `.cache/admin-data-audit-20260904/home-native-dev/screenshots/detail_home-joined_featured.png`
- `.cache/admin-data-audit-20260904/home-native-dev/screenshots/detail_home-joined_featured_next.png`

The last image verifies the horizontal featured row reaches Buri Munsi. These
are fixture screenshots, not live-account balances or full native acceptance.
An initial runner used a nonexistent `development` flavor and failed before
installation; the successful rerun used the actual `dev` flavor.

## Remaining boundaries

`make mobile-design-gate` still reports BLOCKED: exact approved native artifact
provenance, complete case evidence, accessibility and final visual review remain
open. No score, baseline or owner approval was changed to bypass the gate.

The broader [Admin data audit](../admin/ADMIN_DATA_SYNC_AUDIT_2026-09-04.md) still
flags bundled runtime content/configuration fallbacks and stored test-labelled
records. This deployment does not establish a blanket absence of hardcoded
content, delete those records, or prove real-time event delivery through a live
mutation. No physical-phone data, payment execution or production rollout flags
were changed. The workspace remains uncommitted; this was a direct scoped
deployment, with no Git publication or public-landing redeployment.

Detailed, credential-free verification files and the private function backup are
under `.cache/admin-data-audit-20260904/deployment/`.
