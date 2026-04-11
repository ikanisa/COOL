# Font Weight Audit

Static audit of the Flutter frontend in `lib/`, focused on production screens and screen-specific helper files. This is a code audit, not a runtime text-render inspection.

## Global Inventory

- Unique weights used across the audited UI: `w500`, `w700`, `w800`.
- Production UI text now resolves to the 3-weight system above, with no retired weight tiers remaining in the audited frontend.
- Theme source of truth: `lib/core/theme/app_theme_text.dart` and `lib/core/theme/app_theme_components.dart`.

## Theme Role Map

| Theme role | Default weight | Primary family |
| --- | --- | --- |
| `displayLarge` | `w800` | `Space Grotesk` |
| `displayMedium` | `w800` | `Space Grotesk` |
| `displaySmall` | `w800` | `Space Grotesk` |
| `headlineLarge` | `w800` | `Space Grotesk` |
| `headlineMedium` | `w800` | `Space Grotesk` |
| `headlineSmall` | `w800` | `Space Grotesk` |
| `titleLarge` | `w700` | `Manrope` |
| `titleMedium` | `w700` | `Manrope` |
| `titleSmall` | `w500` | `Manrope` |
| `bodyLarge` | `w500` | `Manrope` |
| `bodyMedium` | `w500` | `Manrope` |
| `bodySmall` | `w500` | `Manrope` |
| `labelLarge` | `w700` | `Inter` |
| `labelMedium` | `w700` | `Inter` |
| `labelSmall` | `w700` | `Inter` |

## Helper / Component Weights

- `context.coolText.displayCondensed(...)` and `context.coolText.headline(...)` resolve to Space Grotesk `w800` unless explicitly overridden.
- `context.coolText.display(...)` uses Space Grotesk and is overridden in live screens at `w700` and `w800`.
- `context.coolText.mono(...)` uses DM Mono and appears at `w500`, `w700`, and `w800` in live screens.
- `context.coolText.manrope(...)` uses Manrope and appears at `w500` and `w700` in live screens.
- Navigation, tab, snackbar, tooltip, input helper, and other component themes introduce `w500` through `AppThemeText.medium`.

## Screen-by-Screen

### Auth

| Screen | Route / entry | Effective weights | Theme roles referenced | Text helpers referenced |
| --- | --- | --- | --- | --- |
| Splash | `/` | `w500, w700, w800` | bodySmall=w500, headlineMedium=w800, titleSmall=w500 | displayCondensed, mono |
| WhatsApp OTP | `modal flow` | `w500, w700, w800` | bodyLarge=w500, bodySmall=w500, headlineMedium=w800, headlineSmall=w800 | displayCondensed, mono |

### Shared Utility

| Screen | Route / entry | Effective weights | Theme roles referenced | Text helpers referenced |
| --- | --- | --- | --- | --- |
| QR Scanner | `/scanner` | `w500, w700` | bodySmall=w500, labelLarge=w700 | none |

### Home

| Screen | Route / entry | Effective weights | Theme roles referenced | Text helpers referenced |
| --- | --- | --- | --- | --- |
| Home | `/home` | `w700, w800` | displaySmall=w800, headlineMedium=w800, headlineSmall=w800, labelSmall=w700, titleLarge=w700, titleMedium=w700 | display, headline, mono |

### MoMo

| Screen | Route / entry | Effective weights | Theme roles referenced | Text helpers referenced |
| --- | --- | --- | --- | --- |
| MoMo Wallet | `/momo/wallet` | `w500, w700, w800` | bodyMedium=w500, bodySmall=w500, headlineSmall=w800, labelSmall=w700, titleLarge=w700, titleSmall=w500 | displayCondensed, mono |

### Groups

| Screen | Route / entry | Effective weights | Theme roles referenced | Text helpers referenced |
| --- | --- | --- | --- | --- |
| Groups Overview | `/contribution-circles` | `w500, w700, w800` | bodyMedium=w500, labelSmall=w700, titleLarge=w700 | none |
| Group Create | `/groups/create` | `w700, w800` | headlineSmall=w800, labelLarge=w700, labelSmall=w700 | displayCondensed, mono |
| Group Detail | `/contribution-circles/:groupId` | `w500, w700, w800` | bodyMedium=w500, bodySmall=w500, headlineSmall=w800, labelSmall=w700, titleLarge=w700, titleSmall=w500 | displayCondensed, mobiLabel |
| Group Settings | `/contribution-circles/:groupId/settings` | `w700, w800` | headlineSmall=w800, labelLarge=w700, labelSmall=w700 | displayCondensed, mono |
| Group Statements | `/contribution-circles/:groupId/statements` | `w500, w700, w800` | bodyMedium=w500, bodySmall=w500, headlineSmall=w800, labelSmall=w700, titleLarge=w700, titleSmall=w500 | displayCondensed, mobiLabel, mono |

### BioPay

| Screen | Route / entry | Effective weights | Theme roles referenced | Text helpers referenced |
| --- | --- | --- | --- | --- |
| BioPay Home | `/momo/biopay` | `w700, w800` | displayMedium=w800, headlineSmall=w800, labelLarge=w700, labelMedium=w700 | headline, mono |
| BioPay Register | `/momo/biopay/register` | `w500, w700, w800` | bodyMedium=w500, displayMedium=w800, displaySmall=w800, headlineSmall=w800, labelLarge=w700, labelMedium=w700 | headline, mobiLabel, mono |
| BioPay QR | `/momo/biopay/qr` | `w700, w800` | displaySmall=w800, headlineMedium=w800, headlineSmall=w800, labelLarge=w700, labelMedium=w700, titleLarge=w700, titleMedium=w700 | headline, mobiLabel, mono |
| BioPay Scan | `/momo/biopay/scan` | `w500, w700, w800` | bodyMedium=w500, bodySmall=w500, headlineMedium=w800, labelLarge=w700, labelSmall=w700, titleLarge=w700 | manrope |
| BioPay NFC | `/momo/biopay/nfc (+ tap flow)` | `w500, w700, w800` | bodyLarge=w500, bodyMedium=w500, displaySmall=w800, headlineMedium=w800, headlineSmall=w800, labelLarge=w700, labelMedium=w700, titleLarge=w700 | display, headline, manrope, mobiLabel, mono |
| BioPay Profile | `internal screen` | `w500, w700, w800` | bodyMedium=w500, displaySmall=w800, headlineMedium=w800, headlineSmall=w800, labelLarge=w700, labelMedium=w700, titleMedium=w700 | headline, mono |
| BioPay Enrollment Success | `/momo/biopay/success` | `w700, w800` | displaySmall=w800, headlineSmall=w800, labelLarge=w700, labelMedium=w700 | headline, mono |

### Profile

| Screen | Route / entry | Effective weights | Theme roles referenced | Text helpers referenced |
| --- | --- | --- | --- | --- |
| Profile Overview | `/profile` | `w500, w700, w800` | bodyMedium=w500, headlineSmall=w800, labelLarge=w700, labelSmall=w700, titleLarge=w700, titleSmall=w500 | displayCondensed, mono |
| Profile Wallet | `/profile/wallet` | `w500, w700, w800` | bodyMedium=w500, labelLarge=w700, titleLarge=w700 | display, manrope, mobiLabel |
| Profile Account Details | `/profile/account` | `w500, w700, w800` | headlineMedium=w800, headlineSmall=w800, labelSmall=w700, titleLarge=w700, titleSmall=w500 | displayCondensed, mono |

### Admin

| Screen | Route / entry | Effective weights | Theme roles referenced | Text helpers referenced |
| --- | --- | --- | --- | --- |
| Admin Workspaces | `/admin` | `w500, w700, w800` | bodyMedium=w500, bodySmall=w500, headlineMedium=w800, headlineSmall=w800, labelSmall=w700, titleLarge=w700, titleSmall=w500 | mono |
| Admin Dashboard | `/admin/platform` | `w500, w700, w800` | displayLarge=w800, labelMedium=w700, titleLarge=w700, titleSmall=w500 | display, headline, mobiLabel, mono |
| Bank Admin Workspace | `/admin/banks/:bankId` | `w500, w700, w800` | bodyMedium=w500, bodySmall=w500, headlineMedium=w800, labelLarge=w700, labelMedium=w700, titleLarge=w700, titleSmall=w500 | mobiLabel, mono |
| Manage Users | `/admin/users` | `w500, w700, w800` | bodyMedium=w500, bodySmall=w500, headlineMedium=w800, headlineSmall=w800, labelLarge=w700, labelMedium=w700, labelSmall=w700, titleMedium=w700, titleSmall=w500 | mobiLabel, mono |
| Manage App Config | `/admin/app-config` | `w500, w700, w800` | bodyMedium=w500, bodySmall=w500, displayLarge=w800, labelLarge=w700, labelMedium=w700, titleLarge=w700, titleMedium=w700, titleSmall=w500 | none |
| Operations Dashboard | `/admin/operations` | `w500, w700, w800` | bodyLarge=w500, bodyMedium=w500, bodySmall=w500, headlineMedium=w800, labelLarge=w700, labelMedium=w700, labelSmall=w700, titleLarge=w700, titleMedium=w700, titleSmall=w500 | mobiLabel |
| Manage Admin Roles | `/admin/roles` | `w500, w700, w800` | bodyMedium=w500, bodySmall=w500, headlineMedium=w800, labelLarge=w700, titleLarge=w700, titleSmall=w500 | mobiLabel, mono |
| System Analytics | `/admin/analytics` | `w500, w700, w800` | bodyMedium=w500, bodySmall=w500, headlineMedium=w800, titleLarge=w700 | none |
| Audit Log | `/admin/audit-log` | `w500, w700, w800` | bodySmall=w500, headlineMedium=w800, labelLarge=w700, labelSmall=w700, titleSmall=w500 | mono |
| Admin Groups | `/admin/groups` | `w500, w700, w800` | bodySmall=w500, headlineMedium=w800, labelLarge=w700, labelSmall=w700, titleLarge=w700, titleSmall=w500 | mono |

## Summary

- The frontend is intentionally constrained to a 3-weight system: base `w500`, semibold `w700`, and bold `w800`.
- Most high-visibility screens use `w800` for hero/headline text and `w700` for labels and action text.
- `w500` appears only when screens rely on theme roles such as `titleSmall` or `bodyMedium`, or on component themes using `AppThemeText.medium`.
- The broadest weight coverage appears in admin, profile, MoMo wallet, BioPay NFC/Profile/Scan, and detailed group flows; simpler hero screens stay on `w700`/`w800` only.
