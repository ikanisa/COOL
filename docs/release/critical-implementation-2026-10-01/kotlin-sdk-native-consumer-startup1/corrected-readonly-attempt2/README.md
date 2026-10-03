# Corrected read-only evidence collection

This subtree retains the exact source and outputs of the successful second
read-only collector. It executed at the original packet's `collect_startup.py`
path before these source/receipt bytes were moved here for distinct attempt
retention. Its source is an inert exact execution snapshot; its relative paths
reflect the original location. Do not rerun it from this subtree.

The first collector failed an extra before/after inode equality assertion.
Its exact original source, actual error observation and partial copied receipts
remain in the parent packet. The successful corrected collector verifies all
byte/mode/CRC/source boundaries and records precisely one owned inode
replacement: `bin/cache/engine.stamp`, 41 identical bytes, CRC 3138191385,
SHA-256 `244f6cdbfc0fbba9c7a913c5cfcba4ffd92dfae5f57d3aee527461775cec2066`,
mode 420, nlink 1, same device, inode 58771407 to 58897783.

The authenticated publisher updater at the pinned commit uses a temporary
stamp and atomic `mv`; its exact current source hash and source lines 67, 69 and
71 are bound in `actual-publisher-stamp-inode-replacement.json`. Both full
source validators and the original startup controller passed before either
collector ran. No source or binary exception, SDK modification, stamp/mtime
override, controller change, SDK retry or later stage was introduced.
