# Root technical review refinements

Root accepted the additive successor contract for staged implementation with these requirements:

- Keep one physical Android sender and the existing at-most-once invocation seam.
- Keep one quota truth. Actual `collect_receipt_operations.reservations` has FKs to run, collection and optional device; no primary-outbox FK. `reserve_budget` sums every reservation row for all eight primary/successor caps. Successor attempts must reference this same table, with no separate quota fold.
- Successor configuration remains inactive by default. Append successor-only policy evidence; retain the original v2 decision and every original payload/proof.
- Closure permanently fences assisted and automatic claim/grant/arm races, including ordinary grants already issued before closure. Prove actual callers.
- Final arm must rederive the unchanged approved financial, recipient, consent, language and content evidence after waits, with fresh authority and expiry checks.
- New native route/proof state must survive complete hot/cold retention, export and inactive recovery. Rebase against root's promoted Android operator implementation; never replace its framing, pause or recovery code.
- Build usable slices and send actual backend results before broad Admin work. Root remains sole canonical promoter; no live sends or canonical writes by this worker.

Root owns current canonical `20261002020000_receipt_source_busy_deferral.sql`; telemetry worker reserves `20261002030000`. Successor slice starts at staged `20261002040000_receipt_unarmed_closure.sql`.

The first bounded backend slice introduces inspection, irreversible closure and exact owner request recovery. It authorizes no retry job or SMS. Later queue, sender and Admin slices remain pending until their exact contracts and actual results are accepted.
