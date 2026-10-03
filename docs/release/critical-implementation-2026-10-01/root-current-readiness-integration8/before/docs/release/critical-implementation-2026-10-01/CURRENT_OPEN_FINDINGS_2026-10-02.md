# Current open critical findings

As of 2026-10-02T12:23:31.024197+00:00: **34 of 40 original findings remain open in full. Production NO-GO; implementation goal active.**

The previous 37 count included ARC-01, ARC-02 and BE-10. Those now meet their original local criteria. ARC-04, PD-02 and PD-14 retain their earlier closure scopes. Original 102 production rows and 24 local rows are unchanged.

[Full implementation register](IMPLEMENTATION_REGISTER.md) records original titles, acceptance criteria, current local results and bound evidence.

| ID | Remaining work or evidence |
| --- | --- |
| BE-01 | Fresh deployed migration, function, grants/RLS and configuration parity; authorized runtime denial tests. Linked-project read access was refused. |
| BE-02 | Implement retained, authenticated payment evidence through reconciliation, correction and reversal. Concrete route-neutral proposal reviewed; evidence route decision pending. |
| BE-03 | Current13 endpoint manifest is wired locally; verify deployed bundle identities, JWT/custom authority and missing/retired endpoints. |
| BE-04 | Local originating-session race/provenance checks pass; finish candidate/legacy capability disposition and actual deployed confirmation/send-start behavior. |
| BE-05 | Complete approved retention/erasure schedule, legal holds, derivative/export/backup deletion, restart/duplicate handling and truthful completion. |
| BE-06 | Verify actual Auth, MFA, OTP, CAPTCHA, provider/recovery, abuse protection and rotation configuration. |
| BE-07 | Verify real Google Play Integrity admission, quota/budget, outage behavior and operational alarms. |
| BE-08 | Resolve ownership and history across the 209 migrations domain ownership/history/provenance: 127 function mappings, 74 classifications, 58 callers and 84 lineage uncertainties remain; all 36 application body gaps now have identified transformation candidates, with resolution still unproved. |
| BE-09 | Restore the whole current DB, Storage, Auth, configuration and revocation state with accepted RPO/RTO; 27 local DB recovery checks are narrower. |
| BE-11 | Treat phone hashes as pseudonymous identifiers; approve/enforce retention, access and key migration. |
| BE-12 | Prove deployed SLOs, alert routing, duty ownership, runbooks and fault recovery. |
| BE-13 | Approve AI processor/vendor/project/region/retention/spend/accuracy/deletion controls; source tests do not supply that approval. |
| ARC-03 | Verify canonical endpoint deployment/readiness/scheduler inventory against actual deployed staging state. |
| ARC-05 | Exercise source/artifact approval-bound deployment, partial failure handling and recovery. |
| ARC-06 | Prove protected iOS environments/reviewers and a current signed IPA publication path. |
| ARC-07 | Exercise two actual hosted Admin builds: warm update, multiple tabs, offline/interruption and rollback. |
| ARC-08 | Accept the shipping client/server/archive admission and real restore path; 39 local Linux adapter tests pass, earlier macOS failures remain recorded. |
| ARC-09 | Complete dependency/fork licenses, publisher/frozen-resolution/advisory review and artifact-bound AAB/IPA/web SBOM; native checks pass (12 JVM cases, 20 Release classes); unsigned package assembly pending. |
| ARC-10 | Prove encrypted evidence archive, key recovery, independent restore and clean consumers before removing unique evidence. |
| ARC-11 | Accept full financial/object/history/Auth/revocation recovery and RPO/RTO; local committed DB recovery is insufficient. |
| ARC-12 | Verify real alert ownership, backpressure/capacity, device floors, long sessions and incident/support handling. |
| ARC-13 | Prove signed native permissions/entitlements, SMS/SIM, APNS/FCM and store/device policies. |
| PD-01 | Complete installed mobile, Admin and website Revolut comparisons/interactions and owner acceptance for material routes/states. |
| PD-03 | Establish selected font distribution rights and accept fallback layouts if required. |
| PD-04 | Exercise a real account-deletion channel without the app, including acknowledgement, status, duplicates and failures. |
| PD-05 | Publish/verify legal destinations, retained-data anchor and truthful privacy outcomes; live readback found 404s and differing HTML. |
| PD-06 | Prove users can follow installed deletion instructions without assistance. |
| PD-07 | Accept actual availability/provider claims, conversion and support behavior. |
| PD-08 | Exercise real TalkBack/VoiceOver transitions, error states and recovery. |
| PD-09 | Verify compact/large screens, enlarged text/amounts and keyboard boundaries on installed targets. |
| PD-10 | Prove generated and installed PWA identity, scope and deep links. |
| PD-11 | Complete current route/role/state browser and visual evidence; current 29-route inventory and affected tests are corrected. |
| PD-12 | Complete the current source/dependency/artifact/result evidence index, with superseded results clearly identified. |
| PD-13 | Align received/pending/reconciled/confirmed/ambiguous/corrected/reversed wording with the approved actual financial evidence level. |

The new app refactor proof passes all 1,114 unskipped cases across 41 suites, the hard size gate, strict analysis and source readbacks. The canonical backend and new SQL CI recipe pass in their recorded scopes. Native checks pass in 1,858.452 seconds within the original 2,700-second bound: 12 unskipped JVM cases, 20 current Release classes, unchanged source/protected inputs, and observed owned Gradle groups absent. The unsigned AAB and artifact-bound SBOM review is prepared; no package acceptance is claimed yet.

Cloudflare/browser and hosted-project readback limits remain recorded. No production deployment, signing, provider configuration, payment, external message or Git publication occurred in this work.

Prepared remediation: [payment evidence proposal](be02-evidence-admission-preparation1/README.md) and [36-function provenance review](be08-app-provenance-gap-review1/README.md). Both remain proposed and uninstalled. [Native success readback](root-native8-success-readback1/readback.json) records the completed local scope.
