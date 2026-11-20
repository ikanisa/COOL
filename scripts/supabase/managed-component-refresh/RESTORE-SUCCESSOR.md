# Refreshed Auth and Storage metadata inert restore selector

This successor selects newly captured component evidence without editing the
historical supervisor or its fixed historical selections. It runs the exact
source-pinned historical supervisor in-process after checking a separate source
manifest. The historical supervisor still creates its own AES-256 sparse image,
verifies image/mount and PostgreSQL identities, limits PostgreSQL to an owned
loopback cluster, authenticates the selected encrypted bundle and tests native
cells in inert local tables. Its cleanup and uncertain-outcome behavior are
retained; no production database or provider service is targeted.

The selector must run under the physical interpreter
`/Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework/Versions/3.9/bin/python3.9 -I`
with a clean environment and the separately recorded
`RESTORE-SOURCE-PINS.json` SHA-256. The manifest pins that interpreter,
this selector, tests and notes and the unchanged historical supervisor, child
and component manifests. The historical component manifests separately pin
its full source, dependencies, Node binary and PostgreSQL executables. Python,
system tools, operating system, dynamic libraries and host integrity remain
trusted; a process cannot attest code executed before its own checks.

Real mode accepts only a private mode-0600 metadata selection with an
independently recorded SHA-256. It checks the pinned offline plan, original
count result and count file, exclusive live count claim, completed live
outcome, component RESULT, snapshot digest, and a distinct verified T7
ciphertext copy. It rejects duplicate JSON keys, missing evidence, changed
bytes, path/ownership/mode problems, wrong project or component, non-live
claims, uncertain outcomes, and ciphertext size or digest mismatch. No key
bytes or database password are accepted as arguments, logs or environment
variables; the historical child reads the separately held key only for the
authenticated in-image restore. A selection is evidence-binding metadata, not
an authorization to restore production or a substitute for independent review.

On uncertain cleanup the historical supervisor preserves its owned scratch
root and sanitized `RECOVERY.json`; the selector retains the recovery path if its
own postcheck is uncertain. Never blindly delete a preserved root or detach a
device. A successful synthetic or real run establishes an inert per-component
native-cell roundtrip only. It does not activate Auth or Storage, restore
Storage object bytes, establish quiescence, make independent key custody, or
prove a coordinated whole-system recovery point or production cutover.

Synthetic mode uses generated data and the same encrypted-image/loopback
machinery, with explicitly labeled fixture results. Use a clean launch with
`PATH=/usr/bin:/bin:/usr/sbin:/sbin` and `LC_ALL=C`; the only optional synthetic
environment settings are the historical test pause/tamper controls. Real mode
never accepts those controls. The separately recorded source and selection
hashes must be supplied with `--source-pins-sha256` and
`--selection-sha256`; `--component` is `auth` or `storage`, followed by either
`--synthetic` or `--real-capture --selection <private path>`. Do not execute a
real restore until the exact current source, selection and custody inputs have
been independently reviewed.
