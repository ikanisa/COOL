# Runtime-control authority review

**Installed150 acceptance: FAIL. Correction: staged and locally rehearsed.**

The six-case actual race probe reproduced one unsafe result: a transaction
with an established Repeatable Read snapshot returned a feature-flag control
after its platform-owner grant had been revoked. Advisory locking serialized
the transactions but did not refresh the old role snapshot. The other five
cases denied revoked authority or correctly serialized the authorized read.
All149 table/catalog/cron fingerprints were restored, with no worker left.

`20260930220000_runtime_control_authority.sql` uses the installed149 authority
helper to lock the actual approval, grant, role and permission proof rows.
It applies that check to governed Admin reads/writes and audit-event history,
while preserving the ordinary member-owned preference boundary.

The second actual probe applies the correction only inside each reader
transaction. All six overlapping revocation cases pass and every patch/read
transaction rolls back; all149 tables/catalog/cron are restored. This proves
the reviewed correction under those races without misreporting an installation.

The source has153 migrations while the local registry has150. Navigation,
shadow monitoring and this authority correction remain staged. Sequential
installation, audit-event race coverage, current26-family consumer/write
acceptance and final integration remain open.

The read-only inventory now includes all26 advertised control families,
checks their actual field types against installed147 specifications, and
captures33 routines including the governance helpers. No setting values,
customer data, hosted access or provider calls were exported.

See `authority-review150.json` for exact source and packet hashes.
