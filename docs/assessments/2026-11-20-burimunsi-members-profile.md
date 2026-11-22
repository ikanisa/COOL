# BuriMunsi and React Admin Members query profile

20 November 2026. The native first page for active members matching `Élise` took **74 ms at p95** on the 100,000-member fixture, down from **8,447 ms** before the query change. The first React Admin page on the same fixture took **139 ms at p95** for ordinary browsing and **235 ms** with an active-account and name filter. The records, timings and complete PostgreSQL plans for both runs are available in the [compressed measurements](2026-11-20-burimunsi-members-profile.json.gz).

## Selective names and deep pages on 21 November

The profile now checks a name shared by 99 eligible members and the final two Admin pages of a 99,001-person directory. For a small text result, BuriMunsi filters members before sorting and seeking the next row. React Admin selects the page IDs before calculating balances and group counts for those people. Sorts and filters that depend on those amounts still use them when selecting the IDs.

Both revisions ran against the same 100,000-member local PostgreSQL database in alternating order. Each row below uses 25 measured reads per revision after warm-up. The comparison checked the full response for every pair, including signed cursors with a shared fixture clock.

| Read | Before p50 | Before p95 | After p50 | After p95 |
| --- | ---: | ---: | ---: | ---: |
| BuriMunsi, next 25 name matches | 1,056.79 ms | 1,084.73 ms | 42.18 ms | 45.15 ms |
| React Admin, offset 98,975 (25 rows) | 302.54 ms | 314.12 ms | 64.00 ms | 77.34 ms |
| React Admin, offset 99,000 (one row) | 301.41 ms | 313.65 ms | 64.49 ms | 68.52 ms |
| React Admin, offset 25 (25 rows) | 83.48 ms | 85.46 ms | 46.75 ms | 47.23 ms |

For the final Admin row, the page query touched 608,542 PostgreSQL shared buffers before the change and 4,552 afterward. The count is measured separately. Across 1,000, 10,000 and 100,000 members, 244 comparisons preserved complete Admin responses. The fixtures exercised all 11 Admin sort columns in both directions, empty and out-of-range pages, membership eligibility and grant revocation. Native reference SQL covered all eight sorts, including ties, nulls, balances and inclusive anchors.

The separate idle and concurrent-write runs include all 42 scenarios per revision and 84 query plans per revision. Their wall-clock times include machine-load variation. The tests used a local socket and synthetic data. Authenticated hosting latency and physical handset rendering remain open. [Measurements, plans and reproduction driver](2026-11-21-burimunsi-members-profile.json.gz)

## Changes supported by the measurements

The original native query normalized each candidate's phone twice while counting a broad name match. A single token containing a Unicode letter can match a member ID, display name or the original stored phone text. PostgreSQL now searches those three fields directly. A search containing spaces still uses the complete phrase in its original field order. Numeric searches still include the international phone, local phone and recorded balance. Explicit balance filters and balance ordering still calculate the recorded amounts. [Native query](../../supabase/functions/_shared/domain/burimunsi/postgres-member-listing.js)

| Native active-name search, 100,000 members | First p50 / p95 before | First p50 / p95 after | Next p50 / p95 before | Next p50 / p95 after |
| --- | ---: | ---: | ---: | ---: |
| Idle writer | 4,986.94 / 8,447.14 | 59.69 / 74.30 | 17.82 / 33.43 | 9.29 / 16.00 |
| Open ledger write | 2,636.57 / 5,536.85 | 42.00 / 62.33 | 9.37 / 19.47 | 4.14 / 6.96 |

The same run exposed a separate recovery bug. Revoking a native device made session reload return no actor. The PostgreSQL driver then rejected an undefined installation ID during the device-binding lookup. The service now returns the existing HTTP 401 `session_unavailable` before reading the binding or any Members data. The regression test records the denial and fails on any subsequent read. [Service](../../supabase/functions/_shared/domain/burimunsi/records-service.js) · [Regression](../../supabase/functions/_shared/tests/burimunsi/records-http.test.mjs)

## First and next pages after the change

Each cell gives **p50 / p95 in milliseconds** for 25 warm page pairs. Native browses one collection in newest order, including inactive memberships by default. React Admin browses its authorized Rwanda directory in creation order, including eligible people from other active groups. In the filtered cases, both search for `Élise`. Native filters membership activity and React Admin filters account status.

| Roster | View and filter | Idle first | Idle next | Open write first | Open write next |
| ---: | --- | ---: | ---: | ---: | ---: |
| 1,000 | Native browse | 3.85 / 9.46 | 4.47 / 14.23 | 7.32 / 12.00 | 9.00 / 16.64 |
| 1,000 | Native active and name | 8.40 / 15.67 | 7.83 / 16.80 | 7.85 / 19.36 | 8.84 / 19.10 |
| 1,000 | React Admin browse | 5.29 / 13.88 | 5.90 / 12.96 | 7.81 / 18.52 | 5.31 / 19.31 |
| 1,000 | React Admin active and name | 6.80 / 17.94 | 6.40 / 16.15 | 8.31 / 15.85 | 5.35 / 17.57 |
| 10,000 | Native browse | 9.58 / 19.76 | 7.14 / 18.19 | 9.07 / 15.53 | 5.87 / 13.33 |
| 10,000 | Native active and name | 17.21 / 35.70 | 10.80 / 24.58 | 20.53 / 42.42 | 12.01 / 27.95 |
| 10,000 | React Admin browse | 15.80 / 29.53 | 18.98 / 28.55 | 12.00 / 19.12 | 13.60 / 18.13 |
| 10,000 | React Admin active and name | 21.83 / 34.98 | 20.50 / 27.56 | 18.79 / 31.44 | 17.53 / 37.52 |
| 100,000 | Native browse | 28.40 / 34.78 | 7.92 / 17.63 | 30.54 / 39.38 | 7.25 / 13.83 |
| 100,000 | Native active and name | 59.69 / 74.30 | 9.29 / 16.00 | 42.00 / 62.33 | 4.14 / 6.96 |
| 100,000 | React Admin browse | 98.31 / 139.29 | 98.96 / 152.51 | 95.52 / 137.99 | 100.81 / 185.94 |
| 100,000 | React Admin active and name | 154.56 / 234.60 | 216.22 / 283.73 | 136.20 / 208.40 | 196.01 / 276.63 |

## Query plans and remaining cost

- At 100,000 members, the exact native filtered count took **2,397.50 ms before and 60.24 ms after** in `EXPLAIN ANALYZE`. Both counts scanned users and memberships. The filtered page took 2.07 ms after the change and produced 26 rows, including the continuation sentinel. The default browse page used `burimunsi_members_joined_newest`, the user primary key and indexed ledger lookups.
- The next native page resolved one pivot and reused the signed count. The default pivot took 0.10 ms and its page took 1.38 ms. The filtered pivot and page took 0.10 ms and 1.84 ms. The response returned 25 members.
- React Admin recounted eligible members on both pages. On the 100,000-member browse, the first count took 21.93 ms and the page took 75.91 ms. With the active/name filter the first count and page took 52.28 ms and 102.25 ms. The filtered next page query took 173.38 ms. Exact directory eligibility and ordering can still require work across the visible population.
- Broad substrings still require a full filtered count. The measured improvement comes from eliminating unnecessary computation during that scan. The 20 November run covered broad searches. The 21 November run adds selective searches and deep Admin offsets. Cold caches and sustained multi-writer traffic remain unmeasured.

## Scope and concurrency checks

Each scale used its own database with 1,000, 10,000 or 100,000 target memberships and one initial ledger entry per ten members. The fixture gave every target member the same join timestamp and a numbered accented name to exercise ties and a deliberately broad search. One percent of memberships were inactive and one in forty user accounts was suspended. Independent controls included an eligible member of another group, an archived-only member, an operator, a user in two groups and a contribution from a different group. The checks required the exact visible counts, disjoint pages, two active groups, the native collection balance and the separate Admin cross-group contribution total.

Every timed open-write pair read while another socket held the application mutation lock and an uncommitted same-group ledger insert. Each insert committed after its pair. Additional checks committed ledger entries during live native and Admin read snapshots, verified the previous snapshot and the next fresh amount, and rejected the obsolete signed native cursor with 409. A synthetic member registration committed during an Admin read and appeared on the next request. A conflicting grant update could not acquire its row lock during the guarded Admin read. Removing the grant denied the next request with 403. Revoking the native device denied the next request with 401. **Each scale committed 102 synthetic ledger writes and one registration per run.**

An independent SQL comparison exercised all eight native sorts and 21 query combinations using the original complete search expression. It checked every returned ID and balance, total, continuation and applicable anchor. Inputs covered accents, alphanumeric identifiers, an imported raw phone label, multi-field phrases, national and international phones, numeric amounts, active status, amount bounds and empty results. The existing correctness suite also covers the native legacy query. [PostgreSQL regression](../../scripts/supabase/cloud-release/burimunsi-member-listing.test.mjs)

## Reproduction and interpretation

Run from the checkout with the pinned dependencies in `scripts/supabase`, the locked Deno PostgreSQL package cached, and PostgreSQL 17 binaries available. The repository fixture accepts `COLLECT_SYNTHETIC_PG_BIN` for a local PG17 installation. The launcher creates and removes its own socket-only cluster. It accepts a sample count and an optional full-plan flag.

```sh
node scripts/supabase/cloud-release/burimunsi-members-profile.mjs
node scripts/supabase/cloud-release/burimunsi-members-profile.mjs --samples=25 --plans
node --test scripts/supabase/cloud-release/burimunsi-member-listing.test.mjs
```

The run used PostgreSQL 17.11, Node 24.19.0, Deno 2.9.6 and postgres.js 3.4.7 on a shared Apple M4 with 24 GiB RAM. Each observation included the service call, actual database statements, transaction setup, authority predicates and response projection. Native also signed or verified the cursor. The harness checked `collect_runtime` and repeatable-read isolation in both routes. It discarded the plan capture and warm-up requests before recording latencies, then computed nearest-rank percentiles. Per-query plans were collected separately. Other development processes shared the machine, so small timing differences between load cases have limited meaning.

The fixture supplies local session data and models the external application fence and Admin email context. Its writes exercise the ledger, registration and revocation database changes directly. Hosted authentication, the complete posting and registration command workflows, phone/PIN renewal, device UI rendering and network latency require their own evidence. [Launcher](../../scripts/supabase/cloud-release/burimunsi-members-profile.mjs) · [Service driver](../../scripts/supabase/cloud-release/fixtures/burimunsi-members-profile-driver.mjs)
