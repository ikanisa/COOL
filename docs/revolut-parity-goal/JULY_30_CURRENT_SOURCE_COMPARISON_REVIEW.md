# July 30 Current-Source Comparison Review

Date: 2026-07-30  
Mode: combined UX and screenshot-visible accessibility review  
Product: Collect mobile member app  
Target: iPhone 17 Simulator, iOS 26.5  
Source state: commit `ad2d8e13` plus the inventoried current working tree

## Audit scope

This checkpoint reviews the July 30 Collect changes against:

- two accepted current-source 35-route iOS matrices;
- the eight `reference-safe` Revolut captures in
  `JULY_30_REFERENCE_INVENTORY.md`;
- the Collect language, privacy, ledger, and MoMo boundaries;
- focused automated regressions and the E-066 canonical suite.

It does not use, reproduce, or publish any of the 36
`personal-local-only` Revolut captures.

## Accepted current-source captures

| Variant | Result | Route screenshots | Distinct states | Evidence |
| --- | --- | ---: | ---: | --- |
| Dark | Pass | 35/35 | 26 | `.cache/ios_simulator_route_uat/20260730T115000Z-crp-dark-final/` |
| System on iOS Light | Pass | 35/35 | 26 | `.cache/ios_simulator_route_uat/20260730T120000Z-crp-system-light/` |

The first Dark attempt is rejected evidence:
`.cache/ios_simulator_route_uat/20260730T113000Z-crp-dark/`.
It resolved `/` to `/auth` but asserted before the timer-driven page transition
painted the visible Auth marker. The harness now waits only for the declared
marker within a bounded window; it still requires the exact resolved path,
35 route-pass markers, 35 screenshots, the compiled variant marker, and
minimum visual diversity.

## Normalized pattern comparisons

Each panel is normalized to 316 × 696. These are pattern comparisons, not
claims that Collect and Revolut offer equivalent products or states.

1. Value, actions, and activity:
   `.cache/revolut_parity_comparisons/20260730-crp-current/01-value-hierarchy.png`
2. Appearance preview and mode choice:
   `.cache/revolut_parity_comparisons/20260730-crp-current/02-appearance.png`
3. Security and trust hierarchy:
   `.cache/revolut_parity_comparisons/20260730-crp-current/03-security.png`
4. Public trust and privacy hierarchy:
   `.cache/revolut_parity_comparisons/20260730-crp-current/04-public-trust-pattern.png`
5. Admin operations density and activity:
   `.cache/revolut_parity_comparisons/20260730-crp-current/05-admin-operations-pattern.png`

The comparison generator is
`scripts/build_visual_comparison.swift`. It uses the real source and Collect
screenshots, labels every panel, and adds an explicit non-equivalence footer.
The public and Admin panels are deliberately pattern comparisons: Revolut does
not provide a Collect-equivalent public policy site or group-payment Admin
console, so the review compares hierarchy, density, action grouping, and trust
signals without implying feature parity.

## Numbered flow review

1. **Authentication — locally healthy; parity blocked.** The first viewport
   now presents the official Collect identity, one sign-in thesis, WhatsApp
   number entry, and the disabled primary action in one coherent task zone.
   Direct phone-entry, OTP, invalid, expired, and retry references are still
   absent under RT-002.
2. **Activity — locally healthy.** Group, date, compact reference, and amount
   remain readable in Dark and System/Light. The full reference remains
   available to assistive technology through its semantic label. Actual
   VoiceOver/TalkBack order remains RT-020/RT-021.
3. **Offline and Sync — locally healthy; controlled recovery verified.** Each
   screen now uses one state thesis, two supporting rows, one primary recovery
   action visible without scrolling on the standard phone, and a secondary
   privacy route. The E-073 controlled emulator radio harness proves the
   contribution screen can move from online to stale-cache offline and back to
   authoritative online state while preserving the pending intent and
   restoring the device's exact initial radio settings.
4. **Help — locally healthy; assistive traversal open.** Sign-in, contribution,
   QR/joining, membership/owner, and privacy/deletion categories are visible
   before the support and policy section. The configured WhatsApp support
   route retains no secret or customer-data payload.
5. **Contribution — controlled lifecycle and entry locally healthy.** Amount
   entry retains a single primary path and Collect-native wording. The review
   step now resets to its receiver/amount context instead of inheriting the
   prior scroll offset. E-073 adds a clean-reset local Supabase lifecycle for
   pending, confirmed, expired, duplicate, failed, and recovery states plus
   rollback-only privacy boundaries. It also closes the duplicate native amount
   edit node and proves focused numeric entry with TalkBack enabled. A
   state-matched Revolut amount/review reference remains RT-001.
6. **Appearance — locally healthy for the captured variants.** The live Collect
   preview and compact Dark/Light/System controls preserve the reference's
   preview-first hierarchy without copying its banking content. System visibly
   follows iOS Light in the accepted run.
7. **Security — locally healthy for screenshot-visible hierarchy.** Collect
   keeps one trust hero, two first actions, a clear MoMo credential warning,
   and grouped account/privacy controls. It does not copy Revolut card, wallet,
   crypto, or custody capabilities.
8. **Group Detail — locally healthy.** The screen retains a dominant confirmed
   total, four task actions, explicit member language, and immediate verified
   activity. Long title truncation in command chrome is intentional; the full
   group identity remains visible in the hero.

## Confirmed strengths

- Collect uses Revolut's compact hierarchy and grouped-control grammar without
  implying unsupported banking products.
- The product-language contract is consistently visible across the reviewed
  group, contribution, Help, and ledger surfaces.
- Disabled destructive styling is visibly quieter than enabled danger styling
  in the current Dark/System-Light route set and remains covered by numeric
  token tests.
- Recovery actions and floating navigation no longer compete in the standard
  first viewport.
- No personal Revolut evidence, receiver number, MoMo PIN, OTP, raw SMS body,
  key, token, or production customer data appears in the accepted evidence.

## Open UX and accessibility risks

- No current reference proves state-matched Auth/OTP or contribution
  entry/review parity.
- Screenshots cannot prove screen-reader speech, focus order, action
  completion, keyboard behavior, motion comfort, live-region timing, or
  end-to-end recovery.
- Physical iOS and complete spoken VoiceOver/TalkBack flows remain open.
- Controlled backend/network transitions and a ten-minute emulator reliability
  session now pass under E-073; physical/production soak and authorized Play
  reporting remain separate release gates.
- System/Light and Dark are accepted here; high contrast, large text, reduced
  motion, tablet, Android, and physical-device evidence retain their own
  existing records and limitations.
- The matrices were captured from an inventoried working tree, not one clean
  commit, so CRP-302's single-revision closeout condition remains open.

## Evidence hashes

| Artifact | SHA-256 |
| --- | --- |
| Dark summary | `9b88fd8d5e0d55f9eff4d44a04684fd83ad75cfb22616a6a3581ff76eba25ded` |
| Dark log | `864f5377009b2f22fc9b9470b7088fd9d1a2f58353eb4f75f0179eca4411ef3b` |
| Dark screenshot manifest | `6d96a2cecb0a09f563fe13427e0afe910a2c2ae8c32f188239ca60d26d2123d5` |
| System/Light summary | `5317005c5ff51836b39a0c7194994e59c8a04aacaa328dc3257d76dfdd972e2c` |
| System/Light log | `1e9c51e097bc5f7b2806fcb507739823cbfbfd0778b236d48908e3d87f693716` |
| System/Light screenshot manifest | `4afce1ad65a46310ba948099831bcdc489a0113b9613c699dbfdf81f5eea4474` |
| Value comparison | `b7f6005fcc37235c29f8f234864c97aa690b6714284c4c659f603afb08b7b82a` |
| Appearance comparison | `2714eba8f128de56859e699be7aec89b86d4e953a15821af659e74091ad227e0` |
| Security comparison | `903ceb8289c289c9372b03e683440905a683b43e4a95f3e6d55feb292e2a9243` |
| Public trust comparison | `ed7b9380826961e312a01c4cf0a3107c7e0a4690cb0396cb400d5cd84637920f` |
| Admin operations comparison | `1aa5e209fd2bff9e85a770a979cab5cd4dfcef3fa64b31adac3b68d76f395191` |

## Current disposition

CRP-101..CRP-105 and CRP-201..CRP-204 are implemented for the locally audited
scope. CRP-001 is closed for July 30 inventory governance. CRP-302 and CRP-304
advance through the accepted current-source matrices and safe pattern pack.
CRP-301 remains externally blocked, and the complete CRP-302/CRP-303/CRP-304
closeout remains open under RT-001..RT-007.

This checkpoint is not full Product Design acceptance and not release
readiness.
