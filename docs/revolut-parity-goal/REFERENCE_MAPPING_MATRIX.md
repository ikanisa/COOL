# Revolut Reference Mapping Matrix

Date: 2026-07-24  
Scope: all 35 routes in the fail-closed mobile route matrix  
Authority: `DESIGN.md` and retained Revolut reference captures  
Method: Product Design route mapping plus normalized side-by-side visual review

## Evidence boundary

The original `/Users/jeanbosco/Downloads/Revolut10/` folder is no longer
present. This matrix therefore uses the retained, previously captured evidence
under:

- `.cache/revolut_full_audit/20260723T200000/`
- `.cache/revolut_full_audit/20260723T200000/revolut10/`
- `.cache/revolut_phase2_qa/20260724/`
- `.cache/revolut_parity_mapping/20260724/`

The retained direct captures are 316 by 696 pixels. The ten supplied
Drive-preview images are 1,898 by 798 pixels and contain the original
1170-by-2532 reference screens inside the preview frame. They are usable for
composition and lower-scroll pattern evidence, but not as pixel-perfect
full-screen comparators.

Every comparison in `.cache/revolut_parity_mapping/20260724/` places the
Revolut reference on the left and Collect on the right. Current-source Collect
goldens are used where a retained native screenshot predates a material visual
correction. Retained native screenshots are used only where the later source
changes do not affect the compared surface.

This evidence supports design-pattern mapping. It does not prove the missing
Revolut authentication, OTP, amount-entry, transfer-review, QR, deletion,
legal, or recovery states. Those gaps remain explicit rather than being filled
with invented references.

## Reference key

| Key | Retained source | Pattern available to Collect |
|---|---|---|
| R-HOME | `.cache/revolut_full_audit/20260723T200000/02-home-top.png` | Compact command chrome, dominant value, four quick actions, dense recent activity, floating navigation |
| R-MENU | `.cache/revolut_full_audit/20260723T200000/08-home-more.png` | Anchored secondary-action menu |
| R-THEME | `.cache/revolut_full_audit/20260723T200000/09-theme-sheet.png` | Large live screen preview followed by compact appearance controls |
| R-INVEST | `.cache/revolut_full_audit/20260723T200000/04-invest-top.png` | Focused empty/onboarding state with one statement, one action, and compact benefits |
| R-PAYMENTS | `.cache/revolut_full_audit/20260723T200000/05-payments-top.png` | Search-first dense person/object list and concise transaction metadata |
| R-CRYPTO | `.cache/revolut_full_audit/20260723T200000/06-crypto-top.png` | Value hero, four actions, one status panel, immediate activity |
| R-PROFILE | `.cache/revolut_full_audit/20260723T200000/10-profile-settings.png` | Identity-first profile, status card, and grouped settings rows |
| R-PROFILE-LOWER | `.cache/revolut_full_audit/20260723T200000/11-profile-lower.png` | Compact account, security, documents, and help hierarchy |
| R-SECURITY | `.cache/revolut_full_audit/20260723T200000/11-security.png` | Quiet security shell, emergency actions, one primary prompt, grouped controls |
| R-LONG | `.cache/revolut_full_audit/20260723T200000/revolut10/IMG_2750-drive-preview.png` through `IMG_2752-drive-preview.png` | Long-page section rhythm for discovery surfaces only |

## Complete 35-route mapping

| Route-matrix name | Route | Reference mapping | Disposition |
|---|---|---|---|
| root-redirect | `/` | No direct analogue | Entry routing is behavioral; it must not invent a visible Revolut splash or account state. |
| auth | `/auth` | R-INVEST for compact state geometry only | Direct phone-entry, OTP, error, retry, and review-login references are still missing under RT-002. |
| profile-edit | `/settings/profile` | R-PROFILE identity hierarchy | No verified Revolut profile-edit capture exists. Collect keeps its truthful phone, Collect ID, and MoMo fields. |
| home | `/home` | R-HOME | Direct archetype: command chrome, first-viewport total, four actions, dense activity, stable five-tab shell. |
| offline | `/offline` | R-INVEST | No direct offline reference. Use one clear state, one retry action, and one concise explanation panel. |
| sync | `/sync` | R-INVEST | No direct sync reference. Use designed progress/recovery without fabricating financial state. |
| groups | `/groups` | R-PAYMENTS | Direct list archetype: compact identities, metadata, trailing values, search and add/filter commands. |
| contribute-entry | `/contribute` | R-PAYMENTS for group selection | Direct Revolut amount-entry evidence is still missing under RT-001. |
| activity | `/activity` | R-PAYMENTS | Direct transaction-list archetype with truthful group, public ID, timestamp, status, and amount. |
| group-create | `/groups/create` | R-INVEST for progressive geometry | No direct group-creation analogue. Collect must preserve its own five-step owner setup and validation. |
| group-scan | `/groups/scan` | No direct analogue | Use platform QR-scanner conventions and explicit Camera permission education; do not invent a Revolut QR screen. |
| group-detail | `/groups/col-church` | R-CRYPTO | Direct structural archetype: value hero, group metrics, four actions, status when needed, then activity. |
| share | `/groups/col-church/share` | No direct analogue | Collect-owned QR/share surface with privacy-bounded public group data. |
| invite | `/groups/col-church/invite` | Same Collect share disposition | Compatibility route only; it resolves to the approved Collect QR/share screen. |
| shared-group-link | `/c/st-michel-building-fund` | No direct analogue | Deep-link behavior resolves into the approved group-detail archetype. |
| app-share-entry | `/app` | No direct analogue | Compatibility redirect; no independent visual screen is allowed. |
| app-invite-link | `/invite/038491` | No direct analogue | Compatibility redirect; no independent visual screen is allowed. |
| share-invalid | `/share/invalid` | R-INVEST recovery geometry | Redirects to Groups. It must not preserve an invalid or fabricated shared object. |
| share-expired | `/share/expired` | R-INVEST recovery geometry | Redirects to Groups with no stale access claim. |
| share-expired-request | `/share/expired/request` | R-INVEST recovery geometry | Redirects to Groups; no unsupported renewal flow is invented. |
| contribution | `/groups/col-church/contribute` | R-CRYPTO summary/status rhythm | Collect keeps receiver, amount, verification status, and explicit MoMo handoff. Direct amount-entry/review capture remains RT-001. |
| ledger | `/groups/col-church/ledger` | R-PAYMENTS plus R-CRYPTO | Dense confirmed records immediately follow the total; no status controls or fake transactions. |
| manage | `/groups/col-church/manage` | R-SECURITY grouped-control hierarchy | No direct group-management analogue. Collect uses a compact summary, grouped actions, and explicit destructive confirmation. |
| group-profile | `/groups/col-church/profile` | R-PROFILE identity grouping | No direct group-edit analogue. Collect retains truthful name, description, category, visibility, and recurrence controls. |
| members | `/groups/col-church/members` | R-PAYMENTS | Dense searchable roster with role and contribution metadata; private receiver data stays absent. |
| settings | `/settings` | R-PROFILE and R-PROFILE-LOWER | Direct profile/settings archetype: identity first, then one compact grouped list. |
| settings-notifications | `/settings/notifications` | R-PROFILE-LOWER grouped rows | No direct notification-detail capture. Collect uses compact switches and separately managed phone permission. |
| settings-appearance | `/settings/appearance` | R-THEME | Direct archetype. Collect now shows a live miniature Collect Home preview before compact Dark, Light, and System controls. |
| settings-security | `/settings/security` | R-SECURITY | Direct security archetype adapted to Collect account, MoMo approval, verification, receiver privacy, and deletion boundaries. |
| account | `/settings/account` | R-PROFILE-LOWER | Account-detail hierarchy only; Collect does not copy plan, card, or wallet products. |
| account-delete | `/settings/account/delete` | R-SECURITY destructive hierarchy | No verified Revolut deletion capture. Collect uses explicit reasons, disabled-until-selected submission, and an auditable request. |
| privacy-alias | `/settings/privacy` | No independent comparator | Alias redirects to the canonical Privacy Policy route. |
| help | `/settings/help` | R-PROFILE-LOWER | Direct placement/hierarchy pattern with Collect-owned WhatsApp support, privacy, and terms. |
| legal-privacy | `/settings/legal/privacy` | No direct analogue | Legal copy is governed by Collect policy and readability, not Revolut visual imitation. |
| legal-terms | `/settings/legal/terms` | No direct analogue | Legal copy is governed by Collect terms and readability, not Revolut visual imitation. |

## Normalized comparison review

### Group-management family

Evidence:

- `.cache/revolut_parity_mapping/20260724/group-mapping-contact.png`
- `.cache/revolut_parity_mapping/20260724/group-detail__crypto.png`
- `.cache/revolut_parity_mapping/20260724/manage__security.png`
- `.cache/revolut_parity_mapping/20260724/group-profile__profile.png`
- `.cache/revolut_parity_mapping/20260724/members__payments.png`
- `.cache/revolut_parity_mapping/20260724/ledger__payments.png`

Review:

- Group Detail now matches the reference hierarchy closely: compact command
  chrome, centered value, four actions, and immediate activity.
- Members and Ledger use the correct dense row rhythm and avoid large
  decorative cards.
- Manage follows the grouped-control hierarchy while keeping Collect-specific
  owner, QR, share, member, admin, ledger, archive, and transfer semantics.
- Group Profile correctly remains a form rather than copying a consumer
  profile page. Its visual grouping derives from R-PROFILE without borrowing
  user imagery, plan status, or Revolut labels.
- QR, share, archive, transfer, and owner confirmation remain approved
  no-direct-analogue mappings. They require Collect-owned device/backend UAT,
  not fabricated screenshots.

Verdict: route-pattern mapping for RT-003 is complete. Full native/reference
comparison closure remains under RT-005 because several Collect-owned states
have no direct Revolut comparator and Android/device evidence is still open.

### Profile and Settings family

Evidence:

- `.cache/revolut_parity_mapping/20260724/settings-mapping-contact.png`
- `.cache/revolut_parity_mapping/20260724/settings__profile.png`
- `.cache/revolut_parity_mapping/20260724/notifications__profile-lower.png`
- `.cache/revolut_parity_mapping/20260724/appearance__theme.png`
- `.cache/revolut_parity_mapping/20260724/security__security.png`
- `.cache/revolut_parity_mapping/20260724/account__profile-lower.png`
- `.cache/revolut_parity_mapping/20260724/account-delete__security.png`
- `.cache/revolut_parity_mapping/20260724/help__profile-lower.png`

Review:

- Settings uses the correct quiet black profile shell and one grouped row
  container instead of repeating the financial dashboard.
- Appearance now follows the observed preview-first interaction model while
  using the official Collect mark and Collect-owned Home content.
- Security follows the observed quiet hierarchy but replaces Revolut products
  with truthful Collect account, MoMo, contribution-verification, privacy, and
  deletion concerns.
- Notifications, Account, deletion, Help, Privacy, and Terms use the reference
  list rhythm where applicable. Missing direct detail references remain
  explicitly classified rather than inferred.

Verdict: route-pattern mapping for RT-004 is complete. Direct phone/OTP,
deletion, and lower-detail reference capture remains open only where needed
for RT-002 and RT-005.

## Current-source visual correction

The route comparison exposed two local defects and both are closed:

1. Appearance used three oversized abstract mode cards instead of showing the
   selected app result. It now includes a live, semantics-bounded miniature
   Collect Home preview and compact 48-dp mode choices.
2. Member top chrome could render a text initial such as `0` when no profile
   image existed. All default member top-chrome fallbacks now render the
   immutable official Collect PNG. Explicit route icons such as Back remain
   icon-library controls.

The approved before/after contact sheet is:

`.cache/revolut_parity_mapping/20260724/official-logo-and-appearance-before-after.png`

The final image SHA-256 is
`fe8453530d68cef192167f4de93b44e24b327aeb79ca8a5b4c373648a7023e00`.

## Remaining reference boundary

Still open:

- direct phone-entry, OTP, error/retry, and review-login reference states;
- direct amount-entry and transfer-review reference states;
- live phone-mirroring route capture after the device reconnects;
- complete route-by-route normalized comparisons under RT-005;
- browser-level public/Admin comparisons under RT-006 after permission.

No invented brand mark, reference screen, regulated product, or unsupported
flow may be used to close those gaps.
