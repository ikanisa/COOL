# Frontend Hardcoded UI Audit

Date: 2026-04-11

## Scope

This audit covers frontend UI surfaces in:

- Flutter app UI under `lib/bootstrap`, `lib/features`, and `lib/shared/widgets`
- PWA and web UI under `apps/pwa` and `web`

The audit focuses on:

- Hardcoded user-facing copy in screens, widgets, dialogs, sheets, toasts, labels, titles, tooltips, and accessibility labels
- Hardcoded visual literals in frontend UI assets, especially web/PWA CSS and inline HTML styles

It does not attempt to classify every hardcoded non-UI string such as analytics event keys, route constants, SQL/RPC names, or backend-only code paths.

## Summary

- Flutter/mobile UI copy matches: `997` across `122` files
- PWA/web UI copy matches: `509` across `31` files
- Visual literal matches: `266` across `27` files

Raw inventories generated for this audit:

- [frontend-mobile-ui-hardcoded-copy.txt](./frontend-mobile-ui-hardcoded-copy.txt)
- [frontend-mobile-ui-hardcoded-copy-counts.txt](./frontend-mobile-ui-hardcoded-copy-counts.txt)
- [frontend-pwa-ui-hardcoded-copy.txt](./frontend-pwa-ui-hardcoded-copy.txt)
- [frontend-pwa-ui-hardcoded-copy-counts.txt](./frontend-pwa-ui-hardcoded-copy-counts.txt)
- [frontend-ui-visual-literals.txt](./frontend-ui-visual-literals.txt)
- [frontend-ui-visual-literals-counts.txt](./frontend-ui-visual-literals-counts.txt)

## Findings

### 1. Localization bypass is systemic in core product flows

Hardcoded UI copy is not isolated to admin tooling. It appears directly in major end-user journeys:

- Profile settings in `lib/features/profile/screens/profile_screen.dart`
- Groups browse, join, detail, and create flows in `lib/features/groups/screens/*`
- BioPay home, profile, register, QR, NFC, enrollment success, and payee confirmation flows in `lib/features/biopay/*`
- WhatsApp OTP auth in `lib/features/auth/screens/whatsapp_otp_screen.dart`
- Shared QR/contact/install/system-permission surfaces under `lib/shared/widgets/*`

Impact:

- Localization coverage is inconsistent
- Copy changes require code edits instead of content updates
- Shared wording becomes fragmented across screens and widgets

### 2. Shared widgets contain product copy, so reuse propagates hardcoded text

Several reusable widgets carry user-facing strings internally instead of receiving localized copy from callers:

- `lib/shared/widgets/qr_scanner_screen.dart`
- `lib/shared/widgets/contact_picker_sheet.dart`
- `lib/shared/widgets/qr_share_sheet.dart`
- `lib/shared/widgets/pwa_experience_overlay.dart`
- `lib/shared/widgets/ios_install_prompt.dart`
- `lib/shared/widgets/status_badge.dart`
- `lib/shared/widgets/transaction_status_chip.dart`
- `lib/shared/widgets/cool_toast.dart`

Impact:

- Multiple features inherit hardcoded English copy by composition
- UI text becomes harder to standardize
- Accessibility labels and helper text also bypass localization

### 3. The PWA is largely static hardcoded content

Most `apps/pwa/*.html` routes are written as static marketing or product pages with inline copy in markup. That includes:

- Overview shell
- Home
- Groups
- MoMo
- Profile
- Notifications
- Install
- Admin
- Landing
- Privacy
- Terms
- Account deletion

Impact:

- Content is easy to ship quickly, but not centrally managed
- Rebrand, localization, and product wording changes require direct template edits
- Product claims and legal wording are duplicated across static pages

### 4. Visual literals are hardcoded directly in web/PWA assets

The web/PWA layer contains direct values for colors, sizing, spacing, and typography:

- `apps/pwa/assets/css/app.css`
- `apps/pwa/styles.css`
- `apps/pwa/landing/index.html`
- `web/offline.html`

Impact:

- The web/PWA design language is not fully tokenized
- Brand updates require touching multiple files
- Some web styling diverges from the Flutter design system

## Core Mobile Inventory

These are the highest-impact end-user Flutter surfaces with hardcoded UI copy.

| Area | File | Count | Examples |
| --- | --- | ---: | --- |
| Profile | `lib/features/profile/screens/profile_screen.dart` | 20 | `APP SETTINGS`, `ACCOUNT DETAILS`, `HELP`, `CHAT ON WHATSAPP` |
| Groups | `lib/features/groups/screens/group_detail_screen.dart` | 27 | join/contribute state labels, group action copy, empty-state copy |
| Groups | `lib/features/groups/screens/groups_screen.dart` | 19 | join/invite flow copy, floating action copy, payment-route messages |
| Groups | `lib/features/groups/screens/group_create_screen.dart` | 13 | form titles, section labels, validation copy |
| Auth | `lib/features/auth/screens/whatsapp_otp_screen.dart` | 13 | `Enter WhatsApp Number`, `Verify OTP`, `SEND CODE`, `VERIFY` |
| BioPay | `lib/features/biopay/screens/biopay_profile_screen.dart` | 11 | `Profile`, `Merchant Code`, `MoMo Number`, `Face ID` |
| BioPay | `lib/features/biopay/screens/biopay_qr_screen.dart` | 9 | `Get QR Code`, `Amount (Optional)`, `Generate QR Code` |
| BioPay | `lib/features/biopay/screens/biopay_nfc_screen.dart` | 9 | `NFC Payment`, `Activate NFC`, `Stop NFC` |
| BioPay | `lib/features/biopay/screens/biopay_home_screen.dart` | 6 | `Pay & Get Paid Instantly`, `Face Scan`, `NFC Tap`, `Get QR`, `Scan QR` |
| BioPay | `lib/features/biopay/screens/biopay_register_screen.dart` | 5 | `Face ID Setup`, `Start Enrollment`, `Update Enrollment` |
| BioPay | `lib/features/biopay/screens/biopay_enrollment_success_screen.dart` | 5 | `ENROLLMENT SUCCESS`, `Face ID Ready`, `Done`, `Go to Profile` |

Concrete examples:

- [profile_screen.dart](/Volumes/PRO-G40/COOL/lib/features/profile/screens/profile_screen.dart:163)
- [biopay_home_screen.dart](/Volumes/PRO-G40/COOL/lib/features/biopay/screens/biopay_home_screen.dart:42)

## Shared Flutter Widget Inventory

These reusable widgets contain hardcoded UI copy that affects multiple flows.

| Widget | File | Count | Examples |
| --- | --- | ---: | --- |
| QR scanner | `lib/shared/widgets/qr_scanner_screen.dart` | 13 | `Camera is off`, `Allow camera access`, `Scan MoMo QR`, `Close scanner` |
| Contact picker | `lib/shared/widgets/contact_picker_sheet.dart` | 12 | `Contacts access denied`, `Enable Contacts`, `Retry`, `No contacts with phone numbers found.` |
| Share sheet | `lib/shared/widgets/qr_share_sheet.dart` | 7 | `Scan QR or share the link`, `Join $groupName on Cool: ...`, `WhatsApp is not available`, `Link copied!` |
| Install/update overlay | `lib/shared/widgets/pwa_experience_overlay.dart` | 7 | `Install COOL`, `How to install`, `Update ready`, `Refresh`, `Later` |
| iOS install prompt | `lib/shared/widgets/ios_install_prompt.dart` | 6 | `Install COOL`, `Tap the Share button in Safari`, `Got it` |
| Status badge | `lib/shared/widgets/status_badge.dart` | 11 | `Saving`, `Community`, `Public`, `Private`, `Online`, `Offline` |
| Toasts | `lib/shared/widgets/cool_toast.dart` | 9 | generic success/error/info surfaces are code-driven rather than localized |

Concrete examples:

- [qr_scanner_screen.dart](/Volumes/PRO-G40/COOL/lib/shared/widgets/qr_scanner_screen.dart:103)
- [contact_picker_sheet.dart](/Volumes/PRO-G40/COOL/lib/shared/widgets/contact_picker_sheet.dart:418)
- [qr_share_sheet.dart](/Volumes/PRO-G40/COOL/lib/shared/widgets/qr_share_sheet.dart:20)
- [bootstrap_ui.dart](/Volumes/PRO-G40/COOL/lib/bootstrap/bootstrap_ui.dart:70)

## Admin and Support Inventory

Admin surfaces are the heaviest concentration of hardcoded UI copy on the Flutter side.

Top files by count:

- `33` `lib/features/admin/screens/bank_admin_workspace_screen.dart`
- `28` `lib/features/admin/screens/operational_dashboard_cards.dart`
- `26` `lib/features/admin/widgets/manage_app_config_sheets.dart`
- `24` `lib/features/admin/screens/operational_dashboard_release_cards.dart`
- `23` `lib/features/admin/screens/admin_groups_screen.dart`
- `22` `lib/features/profile/widgets/profile_app_access_sheet_support.dart`
- `18` `lib/features/admin/widgets/manage_app_config_edit_sheets.dart`
- `18` `lib/features/admin/screens/admin_workspaces_screen.dart`

These should be treated as a separate migration batch if you decide to move product UI to `l10n` first.

## PWA and Web Inventory

Top files by hardcoded copy count:

| Surface | File | Count | Notes |
| --- | --- | ---: | --- |
| PWA overview shell | `apps/pwa/index.html` | 77 | Main PWA product narrative, route labels, CTAs, install/update banners |
| Privacy page | `apps/pwa/privacy/index.html` | 42 | Static legal copy |
| Landing page | `apps/pwa/landing/index.html` | 38 | Marketing hero, features, download CTA |
| PWA home | `apps/pwa/home/index.html` | 37 | Dashboard route labels, metrics, queued form copy |
| PWA notifications | `apps/pwa/notifications/index.html` | 29 | Notification permission and feed copy |
| PWA install | `apps/pwa/install/index.html` | 28 | Browser-specific install guidance |
| PWA groups | `apps/pwa/groups/index.html` | 27 | Group workflow copy |
| PWA MoMo | `apps/pwa/momo/index.html` | 27 | Payment request and statement copy |
| Notifications JS | `apps/pwa/assets/js/app_notifications.js` | 27 | Notification titles, actions, and in-app notices |
| PWA profile | `apps/pwa/profile/index.html` | 25 | Settings, passkeys, install prompts |

Concrete examples:

- [apps/pwa/index.html](/Volumes/PRO-G40/COOL/apps/pwa/index.html:155)
- [apps/pwa/landing/index.html](/Volumes/PRO-G40/COOL/apps/pwa/landing/index.html:338)
- [apps/pwa/home/index.html](/Volumes/PRO-G40/COOL/apps/pwa/home/index.html:53)
- [apps/pwa/momo/index.html](/Volumes/PRO-G40/COOL/apps/pwa/momo/index.html:45)
- [apps/pwa/profile/index.html](/Volumes/PRO-G40/COOL/apps/pwa/profile/index.html:45)
- [apps/pwa/assets/js/app_notifications.js](/Volumes/PRO-G40/COOL/apps/pwa/assets/js/app_notifications.js:40)

## Visual Literal Inventory

Top files by direct visual literal count:

| File | Count | Examples |
| --- | ---: | --- |
| `apps/pwa/assets/css/app.css` | 86 | hex colors, font weights, font sizes, spacing, radii |
| `apps/pwa/landing/index.html` | 44 | inline presentational values mixed with content markup |
| `web/offline.html` | 27 | inline colors, radii, spacing, font sizes |
| `apps/pwa/styles.css` | 26 | layout and style literals |
| `apps/pwa/index.html` | 16 | shell-level presentational values |

Concrete examples:

- [app.css](/Volumes/PRO-G40/COOL/apps/pwa/assets/css/app.css:36)
- [landing/index.html](/Volumes/PRO-G40/COOL/apps/pwa/landing/index.html:338)
- [web/offline.html](/Volumes/PRO-G40/COOL/web/offline.html:12)

## What Is Hardcoded Right Now

The current frontend has hardcoded:

- Screen titles
- CTA labels
- Section labels
- Empty states
- Permission prompts
- Error and toast copy
- Sheet/dialog titles
- Accessibility labels and hints
- PWA route labels and install/update banners
- Legal and marketing page copy
- Web/PWA color, spacing, radius, and typography values

## Recommended Fix Order

1. Move core mobile user-flow copy to `l10n` first:
   - Profile
   - Groups
   - BioPay
   - WhatsApp OTP
   - shared permission/scan/share widgets
2. Move shared widget copy behind explicit parameters or localized helpers:
   - QR scanner
   - contact picker
   - QR share sheet
   - install/update overlays
   - toasts and status badges
3. Decide whether the PWA is:
   - a static marketing/demo surface, or
   - a localizable product UI surface
4. Tokenize PWA visual literals into a shared design-token source instead of duplicating values across HTML/CSS files

## Bottom Line

This frontend is not free of hardcoded UI content. Hardcoded copy is present across both the Flutter app and the PWA, including major end-user flows. The problem is broad rather than isolated, and the raw inventories linked at the top of this report are the current full occurrence lists found by this audit.
