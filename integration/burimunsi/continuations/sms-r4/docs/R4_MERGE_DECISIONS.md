# R3 to R4 merge decisions

Baseline: `SMS_Policies_R3_Source_2026-11-09.zip`, SHA-256 `706857f6d08c006d83caad1aa3d71e839207371362650497580d6509fc8c0e69`.

All baseline `src/`, `host/`, `vendor/`, `fixtures/`, and Kotlin policy/persistence tests are preserved. Three new shared Kotlin files implement authenticated storage and checkpoint coordination. No old class is replaced. The R3 plaintext host port stays outside the mobile overlay.

`tests/python/test_persistence_delivery.py`: expand the explicit expected additive-file set from three R3 additions to include three R4 additions. All safety assertions stay enabled. Add `test_protected_delivery.py` to independently verify R3 preservation and installation of exactly the three R4 files.

`scripts/verify.py`: add the separately named `protected_r4` suite, update scope text and external-blocker wording to distinguish implemented controller/crypto from unimplemented production ports. Retain all older suites and input hash binding. `scripts/install_overlay.py` is unchanged and discovers new shared files automatically.

`README.md`, `VERIFICATION.md`, `TASK_STATUS.json`, `SOURCE_MANIFEST.json`, and `SHA256SUMS.txt` become R4 records. Copies of baseline metadata remain under `provenance/R3_*`; baseline hashes are in `provenance/R3_BASELINE.json`. Current evidence is freshly generated rather than copied from R3. Existing R2/R3 documentation remains for provenance; R4 integration instructions are separate.

No Android worker, key material, native encrypted database, deployment configuration, financial authority or live-upload gate is edited. Full A03/A04 application merge and external acceptance remain separate tasks.
