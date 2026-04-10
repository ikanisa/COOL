# Tactile Monolith — Screen Compliance Tracker

Date: 2026-04-10 (post-remediation)

Status key: ✅ Compliant | 🟡 Partial | ⚠️ Exception (documented) | ❌ Non-compliant

---

## Flutter Mobile Screens

| Screen | File | Status | Notes |
|--------|------|--------|-------|
| Splash | `lib/features/auth/screens/splash_screen.dart` | ✅ | Cinematic brand hero, correct typography |
| Home | `lib/features/home/screens/home_screen.dart` | ✅ | Reference implementation — glass nav, quick actions, premium hierarchy |
| Groups list | `lib/features/groups/screens/groups_screen.dart` | ✅ | Fixed: xl card radius, pill buttons, pill FAB, skeleton loading |
| Group create | `lib/features/groups/screens/group_create_screen.dart` | 🟡 | Input system now uses sunken shadows; verify form controls |
| Group detail | `lib/features/groups/screens/group_detail_screen.dart` | 🟡 | Reasonable hierarchy; verify card radii |
| Group statements | `lib/features/groups/screens/group_statements_screen.dart` | ✅ | Migrated onto shared detail shell with glass header and command-center framing |
| Referral | `lib/core/status/screens/referral_screen.dart` | ✅ | Migrated onto shared detail shell; referral cards now live inside the canonical route chrome |
| BioPay home | `lib/features/biopay/screens/biopay_home_screen.dart` | ✅ | xl tiles, correct blur, premium layout |
| BioPay register | `lib/features/biopay/screens/biopay_register_screen.dart` | ✅ | Branded scaffold (BiopayLightScaffold), correct headline scale |
| BioPay QR | `lib/features/biopay/screens/biopay_qr_screen.dart` | ✅ | Inherits upgraded BioPay glass header, segmented control, section cards, and CTA recipe |
| BioPay scan | `lib/features/biopay/screens/biopay_scan_screen.dart` | ⚠️ | **Documented exception**: camera-mode shell with reduced chrome |
| BioPay NFC | `lib/features/biopay/screens/biopay_nfc_screen.dart` | ✅ | Inherits upgraded BioPay shell and input/card/CTA recipes |
| BioPay success | `lib/features/biopay/screens/biopay_enrollment_success_screen.dart` | ✅ | Inherits upgraded BioPay shell and hero CTA styling |
| Profile | `lib/features/profile/screens/profile_screen.dart` | ✅ | Uses real GlassCard, no-line dividers, correct hierarchy |
| Profile wallet | `lib/features/profile/screens/profile_detail_screens.dart` | ✅ | Shared glass header detail scaffold is active |
| Account details | `lib/features/profile/screens/profile_sub_screens_account.dart` | ✅ | Migrated onto shared detail shell via `_ProfileSubScaffold` |
| QR Scanner | `lib/shared/widgets/qr_scanner_screen.dart` | ⚠️ | **Documented exception**: full-screen camera utility |

## Flutter Admin Screens

| Screen | File | Status | Notes |
|--------|------|--------|-------|
| Admin workspaces | `lib/features/admin/screens/admin_workspaces_screen.dart` | ✅ | Uses DenseAdminWorkspaceScaffold |
| Admin dashboard | `lib/features/admin/screens/admin_dashboard_screen.dart` | ✅ | Uses AdminDetailScaffold — best admin implementation |
| Manage users | `lib/features/admin/screens/manage_users_screen.dart` | ✅ | Uses DenseAdminWorkspaceScaffold |
| Manage app config | `lib/features/admin/screens/manage_app_config_screen.dart` | ✅ | Uses AdminDetailScaffold |
| Operational dashboard | `lib/features/admin/screens/operational_dashboard_screen.dart` | ✅ | Uses AdminDetailScaffold |
| Manage admin roles | `lib/features/admin/screens/manage_admin_roles_screen.dart` | ✅ | Uses AdminDetailScaffold |
| System analytics | `lib/features/admin/screens/system_analytics_screen.dart` | ✅ | Uses AdminDetailScaffold |
| Audit log | `lib/features/admin/screens/audit_log_screen.dart` | ✅ | Uses DenseAdminWorkspaceScaffold |
| Admin groups | `lib/features/admin/screens/admin_groups_screen.dart` | ✅ | Uses DenseAdminWorkspaceScaffold |
| Bank admin workspace | `lib/features/admin/screens/bank_admin_workspace_screen.dart` | ✅ | Uses AdminDetailScaffold |

## PWA / Admin Panel Pages

| Page | File | Status | Notes |
|------|------|--------|-------|
| Overview | `apps/cool-pwa/index.html` | ✅ | Token-aligned palette, local variable-font pipeline, borders normalized |
| Home | `apps/cool-pwa/home/index.html` | ✅ | Consistent with monolith system and local variable-font pipeline |
| Groups | `apps/cool-pwa/groups/index.html` | ✅ | Borders normalized to ghost level |
| MoMo | `apps/cool-pwa/momo/index.html` | ✅ | Operational page, correct tokens |
| Profile | `apps/cool-pwa/profile/index.html` | ✅ | Clean IA, aligned system |
| Notifications | `apps/cool-pwa/notifications/index.html` | ✅ | Structured well, correct tokens |
| Share | `apps/cool-pwa/share/index.html` | ✅ | Utility page, aligned |
| Install | `apps/cool-pwa/install/index.html` | ✅ | Correct system |
| Offline | `apps/cool-pwa/offline/index.html` | ✅ | Good fallback UX |
| Admin | `apps/cool-pwa/admin/index.html` | ✅ | Correct palette and typography |

## Documented Exceptions

### 1. Camera/Scanner Mode
- **Screens**: `biopay_scan_screen.dart`, `qr_scanner_screen.dart`
- **Rationale**: Full-screen camera surfaces require minimal chrome for viewfinder legibility
- **Rules**:
  - Reduced chrome is acceptable
  - Typography and accent colors must still use the system
  - Overlay controls should use branded tones, not generic white borders
  - Buttons/banners remain pill-shaped and tonal

### 2. Dense Admin Tables
- **Screens**: `audit_log_screen.dart`, `system_analytics_screen.dart`
- **Rationale**: High-density data surfaces require tighter spacing and smaller elements
- **Rules**:
  - Ghost borders at table/cell level are acceptable (not encouraged)
  - Headline authority and glass header must be maintained
  - Surface hierarchy via tonal layers preferred over lines
