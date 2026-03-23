# Screen LOC Budgets

Current lines-of-code per screen. This file is auto-maintained and referenced by `ROUTE_INVENTORY.md`, `qa_release_readiness.md`, `RELEASE_PROCESS.md`, and `UI_AUDIT.md`.

> [!IMPORTANT]
> The **ideal budget** per screen file is **≤ 400 LOC**. Files that exceed this should be split using a `_parts.dart` pattern (private widget extraction). Combined main + parts should target **≤ 800 LOC**.

---

## Tab Root Screens (CoreTabRootScaffold)

| Screen | LOC | Budget Status |
|--------|-----|---------------|
| `home_screen.dart` | 270 | ✅ Under budget |
| `groups_screen.dart` | 563 | ⚠️ Over budget — split candidate |
| `mobility_home_screen.dart` | 375 | ✅ Under budget |

## Detail Screens (CoreDetailScaffold)

| Screen | LOC | Budget Status |
|--------|-----|---------------|
| `momo_screen.dart` | 402 | ✅ Under budget (with 357 LOC parts file = 759 combined ✅) |
| `partners_screen.dart` | 117 | ✅ Under budget |
| `otp_screen.dart` | 301 | ✅ Under budget |
| `otp_verify_screen.dart` | 392 | ✅ Under budget |

## Admin Screens (AdminDetailScaffold / DenseAdminWorkspaceScaffold)

| Screen | LOC | Budget Status |
|--------|-----|---------------|
| `admin_dashboard_screen.dart` | 674 | ⚠️ Over budget — split candidate |
| `operational_dashboard_screen.dart` | 804 | ⚠️ Over budget (with 913 LOC parts file = 1717 combined ❌) |
| `manage_missions_screen.dart` | 712 | ⚠️ Over budget — split candidate |
| `manage_special_products_screen.dart` | 690 | ⚠️ Over budget — split candidate |
| `manage_quick_actions_screen.dart` | 439 | ⚠️ Over budget — split candidate |

## Partner Screens (RayonScreenScaffold)

| Screen | LOC | Budget Status |
|--------|-----|---------------|
| `rayon_home_screen.dart` + parts | ~1076 parts | ⚠️ Over combined budget — refactor target |
| `rs_admin_initiatives_screen.dart` | 819 | ⚠️ Over budget — split candidate |
| `club_shop_screen.dart` | 755 | ⚠️ Over budget — split candidate |
| `fan_club_detail_screen.dart` | 600 | ⚠️ Over budget — split candidate |
| `fan_clubs_screen.dart` | 560 | ⚠️ Over budget — split candidate |
| `tickets_screen.dart` | 438 | ⚠️ Over budget — split candidate |

## Shared Widgets (Oversized)

| Widget | LOC | Budget Status |
|--------|-----|---------------|
| `qr_scanner_screen.dart` | 969 | ⚠️ Over budget — split candidate |
| `rs_match_card.dart` | 803 | ⚠️ Over budget — split candidate |
| `contact_picker_sheet.dart` | 723 | ⚠️ Over budget — split candidate |

---

## Budget Enforcement Rules

1. **New screens** MUST stay ≤ 400 LOC.
2. **Existing screens** > 400 LOC should be split in the next refactor cycle.
3. **Combined** (main + parts) MUST stay ≤ 800 LOC. Files above this require an architectural review.
4. **Golden tests** are required for any new scaffold archetype or form kit widget.
