# C33 narrow source-access preflight

The configured HTTPS origin is github.com/ikanisa/COOL and standard gh 2.96.0
access works. Seven bounded GET requests used only the normal configured CLI
authentication. No tokens, collaborator names, raw API responses/headers/errors,
secret alert contents or private credential configuration are retained.

GitHub reports a private, active repository, viewer admin permission and default
branch main. Main reports protected:false. Its recorded remote SHA
`df1150ea118aa5dcc9ecb880c71873423081bffe` equals source06's observed base HEAD.
This compares the commit reference; the export also includes modified/untracked
local code and no exported-file parity or reviewed provenance follows.

The main protection and ruleset endpoints return HTTP403 with a classified
plan/visibility restriction. Code-scanning default setup returns HTTP403 with
Advanced Security required. Repository security_and_analysis metadata is absent;
secret-scanning status and complete ruleset/security capability inventory remain
unverified. No disabled state is inferred from these unavailable reads.
Dependabot alerts return 204 (enabled); automated security fixes return 200 with
enabled:true and paused:false. These settings do not attest alert review,
vulnerability remediation or scan coverage. No setting or permission changed.

Source06's exact manifest and captured exporter hash are associated with its
screening/origin fields. It records 1,905 selected files, 154,222,431 bytes,
tracked/nonignored selection, zero observed capture-window drift and every
approval/trust/freeze flag false. Screening checks recognized credential patterns
only, with explicit synthetic/public-anon allowances. It excludes ignored/private
material, caches/builds/payload dumps, Git history and 40 upstream QA/auth fixtures.
The 40 fixture source hashes are retained in the existing manifest; full fork
regression coverage remains open. No new scan or blanket secret/privacy/source
trust claim is made. Per-file hash/readback is integrity evidence, not approval.

The earlier local Python parse failure occurred before its capability requests;
its safe receipt is retained. Corrected requests are represented by their actual
HTTP status and strict metadata projections. Files in this leaf are dated
read-only observations. No browser/direct Keychain access, login, feature enable,
rotation, push, deployment, external message or production mutation occurred.
C33 source/security acceptance remains open; verification.json records limits.
