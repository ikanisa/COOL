import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/services/whatsapp_contact_service.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/rs_colors.dart';
import '../../../core/utils/icon_mapper.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/partners/models/partner.dart';
import '../../../features/partners/providers/partner_provider.dart';
import '../../../features/partners/providers/rayon_sports_provider.dart';
import '../../../features/partners/rayon/models/rs_models.dart';
import '../../../features/partners/widgets/partner_brand_mark.dart';
import '../../../features/partners/widgets/partner_navigation.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_bottom_sheet.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/core_detail_scaffold.dart';
import '../../../shared/widgets/cool_state_view.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/rs_membership_card.dart';
import '../../../shared/widgets/section_title.dart';
import '../../../shared/widgets/tab_pill.dart';
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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final tabs = _tabLabels(context);

    return CoreDetailScaffold(
      onBack: () => popOrGo(context, AppRoutes.home),
      showHomeButton: true,
      onHome: () => context.go(AppRoutes.home),
      homeTooltip: context.l10n.partnersHomeTooltip,
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
                  return Expanded(
                    child: TabPill(
                      key: ValueKey('partners_tab_$index'),
                      label: tabs[index],
                      isActive: isActive,
                      onTap: () => setState(() => _activeTab = index),
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
    );
  }
}
