# Theme Mode Fixed-Color Exceptions

This inventory captures the remaining `Colors.black` / `Colors.white` usage in
`lib/` after the theme-mode blocker sweep. These are no longer functional
light-mode blockers; they are intentional fixed-color treatments or safe
on-primary/on-brand usages that can be normalized later if desired.

## QR And Scanner Reliability

- `lib/shared/widgets/qr_share_sheet.dart`
- `lib/shared/widgets/qr_scanner_screen.dart`
- `lib/features/momo/widgets/momo_qr_nfc_widgets.dart`

## PDF / Export Rendering

- `lib/features/momo/services/momo_statement_export_service.dart`

## Admin / On-Primary CTA Treatments

- `lib/core/theme/app_theme.dart`
- `lib/features/admin/widgets/manage_app_config_sheets.dart`
- `lib/features/admin/screens/manage_app_config_screen.dart`
- `lib/features/admin/screens/manage_services_screen.dart`
- `lib/features/admin/screens/manage_vehicle_types_screen.dart`
- `lib/features/admin/screens/manage_partners_screen.dart`
- `lib/features/admin/screens/manage_quick_actions_screen.dart`
- `lib/features/admin/screens/manage_users_screen.dart`
- `lib/features/mobility/widgets/mobility_driver_widgets.dart`
- `lib/features/profile/widgets/profile_dialogs.dart`
- `lib/features/profile/widgets/profile_header_widgets.dart`

## Rayon / Partner Brand Art And Controlled Hero Surfaces

- `lib/features/partners/widgets/partner_brand_mark.dart`
- `lib/features/partners/widgets/prisma_partner_widgets.dart`
- `lib/features/partners/widgets/partners_screen_sections.dart`
- `lib/features/partners/widgets/partner_shared_widgets.dart`
- `lib/features/partners/screens/radiant_partner_screen.dart`
- `lib/features/partners/screens/rayon/club_shop_screen.dart`
- `lib/features/partners/screens/rayon/member_registry_screen.dart`
- `lib/features/partners/screens/rayon/fan_clubs_screen.dart`
- `lib/features/partners/screens/rayon/tickets_screen.dart`
- `lib/features/partners/rayon/widgets/rs_admin_shell.dart`
- `lib/features/partners/rayon/widgets/rs_hero_banner.dart`
- `lib/features/partners/rayon/screens/rs_admin_tickets_screen.dart`
- `lib/features/partners/rayon/screens/rs_admin_initiatives_screen.dart`
- `lib/features/partners/rayon/screens/rs_admin_matches_screen.dart`
- `lib/features/partners/rayon/screens/rs_admin_members_screen.dart`
- `lib/features/partners/rayon/screens/rs_admin_shop_screen.dart`
- `lib/features/partners/rayon/screens/fan_profile_screen.dart`

## Shared Branded / Decorative Widgets

- `lib/shared/widgets/cool_button.dart`
- `lib/shared/widgets/cool_card.dart`
- `lib/shared/widgets/cool_status_card.dart`
- `lib/shared/widgets/contact_picker_sheet.dart`
- `lib/shared/widgets/rs_membership_card.dart`
- `lib/shared/widgets/rs_initiative_card.dart`
- `lib/shared/widgets/rs_progress_bar.dart`
- `lib/shared/widgets/rs_shop_item.dart`
- `lib/shared/widgets/rs_digital_ticket.dart`
- `lib/shared/widgets/rs_fan_club_card.dart`
- `lib/shared/widgets/rs_amount_selector.dart`
- `lib/shared/widgets/rs_achievement_badge.dart`
- `lib/shared/widgets/rs_match_card.dart`

## Notification / Service Presentation

- `lib/core/services/fcm_service.dart`
