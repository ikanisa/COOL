# External review evidence archive

On 28 September 2026, historical Drive comparison tables, raw source manifests,
prior review JSON, and an ignored recovered checkout snapshot were moved out
of the active repository. Their original bytes were preserved and read back
against SHA-256 hashes. No current release command reads this archive.

- Archive: `/Volumes/PRO-G40/COOL_Design_Gate_Removal_Backup_2026-09-28/retired-evidence/`
- Manifest: `manifest.json` in that directory
- Manifest SHA-256: `cd94ef881a0d93915e5571d2f5bd555e148b3f7a6c9afdb8bd562ec2e57811b6`
- Contents verified: 380 files, 244,259,662 bytes (24 tables/JSON/CSV, 355 recovered snapshot files and one superseded report)
- Pre-edit backup: `affected-files-before.tar.gz` and `affected-files-before.json`
  in `/Volumes/PRO-G40/COOL_Design_Gate_Removal_Backup_2026-09-28/`

The archive is historical source evidence, not a current design or release
authority. The owner-selected `revolut-design` skill governs UI/UX. Current
production readiness remains subject to product, security, provider, device,
artifact, deployment and owner acceptance evidence.
