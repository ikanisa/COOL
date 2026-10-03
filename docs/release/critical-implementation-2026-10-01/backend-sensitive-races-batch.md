# Originating-session acceptance at confirmation and send-start

The exact current191-migration SQL run passed46 phase assertions. It includes24 observed blocking cases against actual confirmation and send-start, covering logout, session expiry, user identity deletion, role/approval revocation and notification-manage permission loss in both orders. Two further cases expire the session by wall clock while each legacy operation waits on its real outbox row.

When revocation wins, the denied operation leaves job state, confirmations/attempts, private session evidence and scoped audit unchanged. When the allowed operation commits first, its original-session/body provenance survives revocation, and a later replay is denied without another mutation. All previously verified healthy APIs, fresh-session replacement denials, immutability and legacy evidence preservation run again; the original12 heartbeat ordering cases remain.

All203 captured inputs remain current, and the unique network-none target was removed. The effective catalog exports metadata/definitions only. No production body or permission was changed for these tests; jobs use the retained canonical synthetic financial fixture. Result, per-migration logs, actual concurrent query logs and exact input hashes are linked from `backend-sensitive-races-batch.json`.

This completes the additional local sensitive-operation race proof. Hosted installation/runtime/rollout remain open. Previously armed unbound legacy work is retained fail-closed and requires governed recovery; no carrier or hosted target was touched.
