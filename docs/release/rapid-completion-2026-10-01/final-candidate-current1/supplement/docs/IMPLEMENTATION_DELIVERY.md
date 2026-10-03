# COOL implementation delivery

All implementation artifacts for this workstream are filed under the owner's
COOL Google Drive folder, in `Implementation_Delivery_2026-09-26`.

Preserve the repository's relative source paths in each versioned delivery.
Deliver cumulative source overlays, incremental diffs, executable tests,
validation logs, and a manifest recording source and delivered hashes.
Download uploaded files again and compare their checksums. Record a blocked
write separately from a successful delivery of a revised copy. Never overwrite
an original source file through a create-only upload or hide a conflict by
creating another same-name source file in the original directory.

A partial source overlay is not a complete repository. Apply it to a complete
checkout only after the installer's hash checks pass. SDK-dependent application
and widget tests must run there; tooling or transfer success cannot substitute
for those results. Preserve original sharing and access controls.

`revolut-design` is the sole design authority. These delivery procedures are
operational instructions, not visual standards or acceptance criteria.
