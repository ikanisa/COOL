import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/services/whatsapp_contact_service.dart';
import '../../../core/theme/app_colors.dart';
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
    final tabs = _tabLabels(context);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: buildPartnerBackButton(
          context,
          fallbackLocation: AppRoutes.home,
        ),
        title: Text(
          context.l10n.partnersTitle,
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
        actions: buildPartnerAppBarActions(context, homeColor: AppColors.text),
      ),
      body: CoolScreenBackground(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 96),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: List.generate(tabs.length, (index) {
                    final isActive = _activeTab == index;
                    final disableAnimations =
                        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
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
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: isActive
                                ? AppColors.accent
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            tabs[index],
                            style: GoogleFonts.dmSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isActive ? Colors.black : AppColors.text2,
                            ),
                          ),
                        ),
                      ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 18),
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
