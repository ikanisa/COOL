# BuriMunsi observation SQL drafts

These preserved source copies document the reviewed candidate bytes. Identical bytes are registered as three forward migrations in the testing source lock; this is not evidence of a deployed feature, an enabled capture path, an approved receiving account, a transaction, or a ledger entry. Keep the separately retained originals under the private qualification directory.

| Draft | SHA-256 | Current status |
| --- | --- | --- |
| `private-quarantine.draft.sql` | `df3e00ad7a5bc1f3f1f3c602989e7aa74f8da01d86f7c4d0c27cf04058d659e5` | Registered in testing source as `20261111121000_burimunsi_private_observations.sql`; synthetic chain, concurrency, native route and disposable Storage checks passed. |
| `private-quarantine-managed-admin.draft.sql` | `6bbc33f633c320b4c698db1e52a27ca707090e6d6857a6e99f25ffd60863413a` | Registered as `20261111121100_burimunsi_admin_observations.sql`; independent synthetic Admin HTTP/PostgreSQL checks passed. |
| `retention-inspection.draft.sql` | `e367539d6ff6548c05ea0b46cb4e216f8423c47b978fcfef530f2fefe6af7fa7` | Registered as `20261111121200_burimunsi_retention_inspection.sql`; inspection only: 33 BuriMunsi classes and affected object custody remain unknown/null and erasure stays blocked. |

Evidence is retained under `/Users/jeanbosco/Documents/Supabase/burimunsi-observation-synthetic-20261111/run-018` and `run-019`, and `/Users/jeanbosco/Documents/Supabase/burimunsi-admin-detection-profile-20261111-Tkxmbc`. These were synthetic environments; no live data, production services or live deployment were used. A separate count-only diagnostic independently observed the candidate sender on the Pixel, with ten inbox messages matching the candidate intake markers. That device observation does not establish their association with code 41258, provider authenticity or posting authority. Native-observation promotion to the canonical transaction and ledger remains unimplemented.
