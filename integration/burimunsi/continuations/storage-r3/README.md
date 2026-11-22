# BuriMunsi and M-Money — storage policies R3

Authenticated journal records and explicit evidence-preserving migration. **Local checks passed; Android adoption, native durability and service acceptance remain open.**

The complete source includes the retained R1/R2 policy work and two product source trees; it is not an independently consolidated Collect checkout. Product factories are present, but application entry points and real legacy decoders are not switched.

## Start here

Read `docs/IMPLEMENTATION_AND_VERIFICATION.md`, `docs/DURABLE_LIFECYCLE_CONTRACT.md` and `ACTION_REGISTER.json`. Code and test changes are traced in `patches/r3/CHANGE_LEDGER.json`. `evidence/current` is the R3 run; previous runs and documents remain in `evidence/previous-*` and `history`.

```sh
python3 tools/run_storage_checks.py --output ../storage-r3-verification
```

The output directory must not already exist. Prerequisites are Python 3, Java, Kotlin compiler, Node and Bash on PATH. The bundled logs identify versions actually used. Native acceptance is never inferred from an exit-0 host run. `--require-native-acceptance` returns nonzero until the separately required acceptance exists.

The generic Android factory looks up an **existing** dedicated Keystore alias; it never generates a missing key or creates a missing directory. The migration API preserves legacy evidence and refuses partial/conflicting bootstrap records. Do not automatically enable it in a running app.

All source files are included in this archive. Apply incremental patches only against the exact R2 source and preserve unknown edits. No production data, generated app binary or native test approval is supplied.
