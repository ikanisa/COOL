# Combined schema153 subset upgrade

**162/162 checks passed.** The final attempt2 disposable database was removed.
The retained schema153 catalog was restored locally, seeded with an existing
50RWF primary receipt and 250RWF paused historical payment, then upgraded with
backlog230100, Overview230200 and transaction lifecycle230300 in that order.
Every install preserved all nonempty business fingerprints. No hosted or
shared QA database was mutated; no provider, carrier, OTP or device was called.

This is a **three-migration schema153 subset upgrade**. It is not a clean
installation or the required hosted124-to157 upgrade. The source readback
still reports hosted124. Group-share230000 and later investigation/sensitive
authority work are deliberately outside this rehearsal.

All three SQL files and the unchanged foundation/shadow helper bytes match
retained snapshot02, manifest SHA256
`4d49758c617893d96740bebc7ec9f34beac783c4d6019daadf754ed6e851a4fc`.
That snapshot is explicitly unaccepted as a current/reviewed/frozen production
release. `snapshot02-prerequisite-parity.json` additionally compares the
recorded 149 authority function and 151–153 normalized source bytes with the
original baseline parity record. These narrow checks do not attest every
deployed body or the whole concurrently changing checkout.

The captured schema dump SHA256 is
`77262947961ac1a724195ea77bdb98088cebd30caecc625ded1d4a93ccbf6d3d`;
API ACL SHA256 is
`b430b8a2fb061f4422e8a53029a530a3d59f82f162507c8ae97e28541f52b577`.
The original capture's metadata was153 before and after dumping. The runner
restores these exact retained bytes and never re-dumps the moving shared QA
database. Source owners are normalized and captured API privileges rebuilt.
Network/cron/GraphQL/statistics extensions are excluded, with empty cron
catalog stand-ins; no extension integration acceptance is claimed.

Coverage includes the full foundation adversarial matrix; nonempty actual
Overview posted RWF totals and paused queued/awaiting/failed/uncertain/started
counts; independent notification denial; approval/grant/Auth expiry and
revocation; bounded query/schema/country behavior; Kigali day start and future
cutoffs; deterministic paging/sorts; actual raw/parsed/payment observations;
canonical posting and reversal evidence independent from allocation and
notification status; denied API/private-helper/private-table access; rollback
faults for a missing journal line and conflicting confirmation; and a real
read-authority-versus-session-expiry lock race. Sixteen tables are fingerprinted,
including nonempty provider confirmation and raw/parsed observation evidence.
The original primary receipt remains byte-for-byte unchanged, every journal
retains two balanced canonical lines, and the final group balance matches
currently posted payments.

`result.json`, `queries.sql`, `queries.log`, `concurrency.log`, stage install and
restore logs, and observed JSON fixtures retain the actual local evidence.
All financial/provider/phone/body records in these files are synthetic; none
comes from source/shared/hosted business tables. Synthetic database claim
settings are not signed GoTrue/PostgREST sessions or authentic provider proof.
Pre-send/outcome records are local fixtures with no carrier invocation.
Day-end exclusion is also a future-time cutoff at execution; the actual
midnight-crossing refresh branch was not wall-clock tested. Production volume,
latency/SLO, extension integration, deployed body/ACL parity, provider/device
and live approved operator acceptance remain open.

`hosted-upgrade-inventory.json` lists all 33 snapshot prerequisites after
hosted124, exact file hashes, subset membership and later workspace drift.
`UPGRADE-PREREQUISITES.md` describes the separate full compatibility rehearsal.
Human event observations are not unattended durable business handling;
historical catch-up remains `CATCHUP_POLICY_PENDING`.

Reproduce with `python3 scripts/tests/collect_admin_combined_upgrade_uat.py
--report-dir .cache/combined-upgrade-new-attempt` while the pinned capture and
snapshot bytes remain available. The runner accepts no remote URL and requires
the exact local project/container/port with cron/net execution disabled.
Attempt1's earlier pass remains in `.cache` as a diagnostic; attempt2 expands
the business fingerprints to provider evidence and observation tables.
