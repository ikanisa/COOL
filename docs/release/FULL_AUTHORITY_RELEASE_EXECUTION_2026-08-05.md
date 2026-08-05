# Collect Full-Authority Release Execution

Recorded: 2026-08-05
Release: `1.2.2+10`
Release owner: Jean Bosco

## Owner decision

The release owner authorized the complete Android and iOS release workflow,
including provider/store inspection, signing, upload, submission, and acceptance
of explicitly recorded residual risk. The approval and all ten persona waivers
are machine-validated. A waiver is not represented as an executed human,
physical-device, provider, or store test.

## Current validated outcomes

- Release status, approval evidence, UAT evidence, and native accessibility
  responsibility gates: `pass`, decision `GO`.
- Google Play: authenticated production app inspected; live release is
  `1.2.1 (8)` at 100%; no unpublished changes; the Console exposes no crash or
  ANR value for the available period. A production draft exists for the next
  release.
- Android production AAB SHA-256:
  `441b7937d3be6ef11f32d948ad787cb60fa5d231240144a9813a5d62df8cef1d`.
- iOS archive: Xcode automatic signing and local store validation succeeded for
  `1.2.2 (10)`.
- iOS export: Apple Distribution signing and App Store IPA export succeeded.
  IPA SHA-256:
  `3d9172c453699126524892b9c826abb0759c69df5a67b43837bf1d64022f3a2c`.
- Apple upload: authenticated upload began and App Store Connect rejected only
  the duplicate bundle version because build `10` already exists remotely.
- Production backend: 60/60 migrations, 312/312 schema entries, 58/58 public
  tables with RLS, linked SMS/Admin rollback UAT pass, and zero error-level
  linked security/performance advisor findings.

## Honest residual execution state

- Google Play AAB transfer requires the ChatGPT Chrome extension's
  `Allow access to file URLs` setting before the prepared draft can receive the
  67.8 MB bundle.
- App Store Connect UI sign-in is waiting for the account holder's passkey
  confirmation so the existing build `10` can be inspected and submitted.
- APNs runtime delivery is not enabled because the four required token/config
  secret names are absent. No placeholder or invented credential was created.
- The fresh unlocked physical-iPhone staging install/launch succeeded, but the
  wireless Flutter driver attach timed out and produced 0/35 route markers. The
  attempt is rejected; prior accepted E-075 physical route evidence remains.
- Collect opens the provider-owned MoMo USSD surface and does not custody funds.
  Linked lifecycle/privacy/ledger UAT passes, but no live MoMo transaction is
  claimed.

## Secret and privacy handling

This record excludes Apple/Google credentials, passkeys, device identifiers,
signing key material, provider tokens, raw SMS, phone/MoMo receiver data, OTPs,
and production customer data.
