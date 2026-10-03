# Exception escalation SDK fixture correction

All **39 cases passed**, with zero failures or skips. `cases-acceptance.json` binds the exact JSON execution and test SHA; `validation.json` preserves the original overall gate failure due solely to one missing brace. That brace is corrected separately and is included in the current principal affected derivative.

All six original case bodies remain byte-identical. Thirteen fullVM failures and their error events remain in `retained-original13.json`. Changes affect only the owned test: match the synchronous malformed-ID refusal, accept the correct permission-denial type, assert withheld data during unresolved identity loading before resolving denial, and unmount/dispose the real provider container before Flutter timer invariants. No timeout was broadened and no production behavior was changed.

The production Supabase/Postgrest/GoTrue SDK, repository, provider and Inbox widgets execute with real Auth events. HTTP `MockClient` supplies synthetic responses only. The ten Inbox cases include good ACK, six contradictory ACKs, response loss without replay, session replacement and A→B→A. This is no fresh SQL, hosted email delivery or whole live Admin claim.

The immutable derivative and copied SDK remained unchanged. New peer principal runtime added after the fullVM snapshot is explicitly excluded here and is tested in the separate affected derivative. Original harness/format failures remain preserved.
