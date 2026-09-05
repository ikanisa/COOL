# Cleanup candidate verification — 5 September 2026

Status: **Fresh Android QA candidate built and installed. Distribution remains
blocked by MOBILE-DESIGN-100.**

The candidate includes the fixture-data removal. This continuation changed no
app source or database rows. Current source matches the previous 628-test
verification and clean analyzer result; those suites were not repeated.

## Build and native verification

The controlled Android wrapper completed version **1.2.4+23** at
`2026-09-05T06:52:14Z`, with production Supabase configuration and fixture mode
disabled. Signing preflight passed against the Google Play upload certificate.
Source fingerprints before and after the build match.

| Artifact | SHA-256 |
| --- | --- |
| Source | `f5d4db3bfc9f7665b23e2b908c61355fef3b89443a62640d05f6265c6792d4b5` |
| APK | `023725ad1feea64b240a10174ffb544b818b7ce6b73f6bffce2960e2e02ff042` |
| AAB | `773af3881b693c1424a0e75e757be7806dc144e9104492f67b9e4831abf8c25e` |

The APK installed on the isolated Android 16 emulator. Hashing the installed
package matched the local build. Every packaged native app binary (three
architectures in each archive) was scanned for the retired group name/ID and
synthetic QA group identity, in UTF-8 and UTF-16LE. No matches were found.
This is a targeted fixture-identity check, not a claim that every app constant
is managed by the backend.

Native smoke passed cold start, country-search label, native activation action,
Rwanda search using the Android keyboard, country selection and disabled Send
for an incomplete number. Five screenshots were visually reviewed. The captured
current-process log contains zero Flutter or fatal errors. No real OTP was sent.
The physical Pixel and its signed-in data were untouched.

## Live data and Admin readback

The COOL project is `lhbowpbcpwoiparwnwgt`. A read-only query found five stored
groups and zero retired-group matches. Function and view definitions in the
public and hybrid schemas also have zero matching hardcoded identities.
The anonymous public REST directory returns Buri Munsi and Gikundiro and matches
the active approved base records exactly.

The live Admin JavaScript still has SHA-256
`e241614f6cd25444a975e2f826aaba2ec6fed9590dbcec6ea4a3cee2723abc79`.
It contains the correct Supabase project URL and no retired-group name/ID.
This is a current asset readback; authenticated Admin navigation was previously
verified and was not repeated in this continuation.

The connector's account did not expose COOL. The existing authorized Management
API route was used. Its read-only role cannot execute the view's payment helper,
so the inspection queried permitted base records and checked the view through
the normal public REST API. Access controls were not changed. The named Supabase
Sheet and its Sheet7 tab were re-grounded; no credentials were printed or saved
in this report. API shape was checked against the official
[Management API reference](https://supabase.com/docs/reference/api/v1-run-a-query).

## Remaining release work

`make mobile-design-gate` remains **BLOCKED**, exit 2. The fresh artifact
provenance is present; the approval record still has no accepted cases or bound
approval hashes. The 134-case matrix, 22 annotation closures, full native
accessibility/keyboard/recovery coverage and original-reference review remain
required. Five signed-out smoke captures cannot close the signed-in matrix.
The previously removed store screenshot sets also need fresh capture and review.

The next dependency is an authorized QA phone number for normal WhatsApp sign-in
on the installed candidate. No production group was inserted or deleted, no
payment or OTP was sent, and no binary or store asset was uploaded.

Evidence root: `.cache/cleanup-candidate-20260905/`. Key records are
`build.txt`, `build-provenance.json`, `artifact-fixture-scan.json`,
`installed-candidate.json`, `native-smoke.json`, `visual-review.json`,
`supabase-data-readback.json`, `public-directory-readback.json`,
`live-admin-asset-check.json`, and `mobile-design-gate.txt`.
