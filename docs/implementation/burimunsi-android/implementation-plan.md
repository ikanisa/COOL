# Current BuriMunsi implementation plan

Scope: native Android for Collect staff and admins, including an authorized receiving-handset flavor. Both roles use the existing Collect Admin and the same local Supabase/Auth/business ledger. Reviewed on 9 November 2026 against the imported 36-action engineering register and the actual retained local instance.

The original action register is retained unchanged under `drive-handover/registers/`. Its inherited statuses describe the source handover. The following records the current repository integration and the next dependent work.

| Original actions | Current observed result | Remaining work |
| --- | --- | --- |
| A01, A04, A05 | Shared-backend/native-only boundary recorded; A04.3 imported into `codex/burimunsi-android-integration-20261109`; Recovery.3, API r3 and presentation.3 merged with A04 identity and financial-recovery fixes retained. | Review/commit the final source candidate. The branch has no published PR or server-side protection claim. |
| A02, A26-A28, A31-A36 | Nine archive hashes verified; original source bytes and registers retained; import/merge inventories and scoped host verification recorded. | Bind later deployment, device and signed-release evidence to the accepted source commit. Release provenance cannot execute with this Mac's fixed system LibreSSL; one guard fixture also assumes a case-sensitive filesystem. |
| A06, A08 | Existing local instance resumed and inspected read-only. Collect native route hook added; unconfigured routes return 503. | Rehearse additive Collect schema/functions plus Buri extensions, existing Admin admission and runtime grants. Implement the genuine Android `ManagedSessionHost` broker; preserve existing Supabase identities. |
| A10, A14 | Canonical bridge and posting adapter source imported; local domain tests pass with explicit reduced/synthetic boundaries. | Supply actual shared transaction/fence/source/gateway/custody ports; qualify real PostgreSQL concurrency and ledger reconciliation before activation. The imported posting proposal has not replaced the active writer. |
| A11, A12, A20 | Common Collect function prefix and shared-origin validation configured in source; real group and public HTTPS profile remain blank. | Bind the existing Admin operational grants/surfaces, group/receiving custody, canonical nine-field deployment identity and phone-accessible HTTPS routes for this same instance. |
| A15, A30 | Delivered dependency/tooling and device-discovered contrast/fixture defects corrected. Final clean build-007 and all eight APK inspections passed; API36 staff23/23 and receiver30/30 passed, with all sandbox packages removed. | Commit the accepted source, complete API26/physical-device and independent release qualification, then bind production artifacts to that commit. |
| A16-A19, A22, A29, A33 | SMS R4 and Storage R3 source plus scoped policy/encryption/restart checks retained separately; Android source/UI contracts and role isolation checks pass. | Adopt reviewed real checkpoint/encrypted-store ports into the active writer, qualify API 26 and physical handset/SIM/carrier corpus, accessibility/language/export behavior, independent security and distribution requirements. |
| A21, A23-A25 | Operational, recovery, pilot and signed-release requirements preserved in the handover. | Commission monitoring/support and encrypted recovery, exercise restore/stop/rollback, run an authorized bounded pilot, then accept one signed attributable candidate. |

## Next dependent sequence

1. Accept and commit the reconciled source after the current build/device results are recorded.
2. Prepare and rehearse the additive deployment into the retained local Supabase installation; preserve Auth identities, volumes, recovery custody and a single financial writer.
3. Connect the real shared managed login, Admin grants and canonical command ports; commission the real group/receiver binding and common HTTPS deployment profile.
4. Deploy only that accepted shared candidate, then qualify hosted database/HTTP behavior, physical-device receipt-to-ledger recovery and operational rollback.
5. Close independent release evidence and sign/distribute the accepted Android staff/admin candidate.

No schema migration, new backend instance, production signing, provider activation, live SMS upload or financial write was performed during this source integration.
