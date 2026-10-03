# Published history optimization — two-volume local acceptance

The additive migration `20261001095000_member_history_global_keyset_indexes.sql` now has actual public-API acceptance at both 1,000 and 10,000 genuinely posted payments: **292 checks, zero failures in these accepted volume sections**. The original combined run remains failed because its second clone reused a session ID; the 10,000-only retry fixes the fixture reset and retains its independent cleanup proof.

Each volume checks 108 history windows across four sorts, nine authorization/filter scopes and three depths. Twelve global windows per volume scan less than half the baseline payment rows and use strictly fewer buffers. All fields, totals, masked private titles, deterministic ties, revisions and cursor semantics are independently checked against actual generated rows. Concurrent cursor cases cover all four sorts. Four invalid foreign-key configurations must refuse migration and roll back.

Recent intents preserve exact pending counts while returning bounded owned rows; notification sorts/page depths retain exact totals and deterministic rows. A rollback-only queue deletion verifies known zero and restores all data. Full exact-summary scans remain necessary; no latency SLO or provider performance is inferred from these local runs.

The frozen execution set contains 177 migrations. A later peer receipt-policy edit is expressly dated and unaccepted by this packet. Shared 154/153-table source/catalog/cron data was preserved; each task-owned clone was removed. The JSON manifest records every evidence hash and individual scan/buffer comparison. This is query-specific acceptance, not whole repository or production acceptance.
