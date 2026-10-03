# Independent transaction observations — 30 September 2026

The Transactions workspace now shows verification, allocation, ledger and
notification separately. An allocated SMS does not imply provider verification,
balanced posting or delivery. Older backend responses without the complete
contract display unavailable evidence; malformed/partial contracts fail
validation. The raw SMS origin is labelled Receipt sender, rather than being
represented as the payer's MoMo account number.

Implemented in `admin_transaction_lifecycle.dart`, narrow model/table/status
chip changes, and `20260930230300_admin_transaction_lifecycle.sql`. The RPC
preserves approved current platform-owner authority and `payments.read`, and
locks the additional `notifications.read` proof before exposing receipt state.
Missing notification permission hides both receipt existence and status.
The projection contains masked source/payer evidence and opaque linkage IDs;
it contains no raw SMS, receipt body, full destination or operator credential.

Ledger observations require actual canonical two-line journal and posting
snapshot evidence, including matching group/member/amount. Reversal is
separate compensating evidence. A stored confirmation is expressly not
external settlement proof. Unknown send outcome and Operator observed sent
retain their actual evidence meaning. Independent status colours no longer
infer successful posting from the substring in Not posted.

The same read RPC also preserves total count beyond the last page, deterministic
tie-breaks and requested amount/date ordering. Invalid limits, offsets, filters
and sorts fail closed.

Validation retained here:

- **10/10** DTO and actual registered transaction-page widget tests passed at
  320, 1440 and 2048 pixels, including older-contract unavailable states and
  meaningful visible headings. `widget-tests-final.log` records the latest
  label correction and immutable model projection.
- Five-file Flutter analysis reported no issues; sole Revolut design-authority
  hygiene passed. These checks do not certify visual fidelity or accessibility
  across every authenticated route/state.
- **26/26** isolated SQL UAT cases passed in
  `uat-attempt2-posted/result.json`, using the then-guarded schema150 source,
  reconstructed API grants and synthetic Auth-context fixtures. The real
  installed confirmation RPC produced a balanced synthetic posting; the Admin
  read reported its independent states without modifying the populated
  financial evidence. Anonymous/service calls, revoked authority, missing
  sessions and independent notification denial were exercised.

The successful SQL run used the earlier `20260930250000` filename. Its SQL
bytes were subsequently preserved under the valid, unique `20260930230300`
timestamp; the runner points to that corrected filename. The retained old
run is not relabelled as a new execution against today's source. A combined
schema153 subset-upgrade rehearsal is being prepared separately.

No hosted migration, provider confirmation, carrier send, approved operator
sign-in or production acceptance is established. Complete investigation,
conflict recovery, joined audit evidence and final route/comparator acceptance
remain separate tasks.
