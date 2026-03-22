import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/services/whatsapp_contact_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/cool_palette.dart';
import '../../../core/utils/icon_mapper.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/partners/models/partner.dart';
import '../../../features/partners/providers/partner_provider.dart';
import '../../../features/partners/providers/rayon_sports_provider.dart';
import '../../../features/partners/rayon/models/rs_models.dart';
import '../../../features/partners/rayon/widgets/rs_membership_card.dart';
import '../../../features/partners/widgets/partner_brand_mark.dart';
import '../../../features/partners/widgets/partner_navigation.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_bottom_sheet.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_state_view.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/section_title.dart';
import '../../../shared/widgets/whatsapp_hint_chip.dart';

part '../controllers/partners_screen_controller.dart';
part '../widgets/partners_screen_sections.dart';

/// Partners hub — football clubs, banks, and organizations.
///
/// All partners are loaded dynamically from Supabase for the fixed Rwanda
/// market.
class PartnersScreen extends ConsumerStatefulWidget {
  const PartnersScreen({super.key});

  @override
  ConsumerState<PartnersScreen> createState() => _PartnersScreenState();
}

class _PartnersScreenState extends ConsumerState<PartnersScreen> {
  int _activeTab = 0;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final tabs = _tabLabels(context);

    return Scaffold(
      backgroundColor: colors.appBackground,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: buildPartnerBackButton(
          context,
          fallbackLocation: AppRoutes.home,
          color: colors.primaryText,
        ),
        actions: buildPartnerAppBarActions(
          context,
          homeColor: colors.primaryText,
        ),
      ),
      body: CoolScreenBackground(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 96),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  context.l10n.partnersTitle,
                  semanticsLabel: context.l10n.partnersTitle,
                  style: theme.textTheme.displayLarge?.copyWith(
                    color: colors.primaryText,
                    height: 1.0,
                  ),
                ),
              ),
              const SizedBox(height: CoolSpace.x2),
              Text(
                'Official clubs, finance partners, and service operators in one trusted network.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.secondaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: CoolSpace.x6),
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: colors.cardSurfaceStrong,
                  borderRadius: BorderRadius.circular(CoolRadii.md),
                  border: Border.all(color: colors.border),
                ),
                child: Row(
                  children: List.generate(tabs.length, (index) {
                    final isActive = _activeTab == index;
                    final disableAnimations =
                        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
                    final onPrimary = Theme.of(context).colorScheme.onPrimary;
                    return Expanded(
                      child: Semantics(
                        selected: isActive,
                        label: '${tabs[index]} tab',
                        child: GestureDetector(
                          onTap: () => setState(() => _activeTab = index),
                          child: AnimatedContainer(
                            duration: disableAnimations
                                ? Duration.zero
                                : const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? colors.accent
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(CoolRadii.sm),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              tabs[index],
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: isActive
                                    ? FontWeight.w800
                                    : FontWeight.w700,
                                color: isActive
                                    ? onPrimary
                                    : colors.secondaryText,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: CoolSpace.x5),
              IndexedStack(
                index: _activeTab,
                children: [
                  _FootballTab(onOpenRayonSports: _openRayonSports),
                  const _BanksTab(),
                  const _OrgsTab(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
