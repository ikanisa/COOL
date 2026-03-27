import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/rs_colors.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/partners/models/partner.dart';
import '../../../features/partners/providers/partner_provider.dart';
import '../../../features/partners/providers/rayon_sports_provider.dart';
import '../../../features/partners/rayon/models/rs_models.dart';
import '../../../features/partners/widgets/partner_navigation.dart';
import '../../../shared/widgets/cool_bottom_sheet.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/core_detail_scaffold.dart';
import '../../../shared/widgets/rs_membership_card.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import 'package:url_launcher/url_launcher.dart';

part '../controllers/partners_screen_controller.dart';
part '../widgets/partners_screen_sections.dart';

/// Partners hub — flat list of all partners with search.
///
/// Screenshot layout:
/// "PARTNERS" / "OFFICIAL PARTNER NETWORK" title
/// Search bar
/// Flat list of partner rows (thumbnail + name + category + chevron)
/// "BECOME A PARTNER" CTA card
class PartnersScreen extends ConsumerStatefulWidget {
  const PartnersScreen({super.key});

  @override
  ConsumerState<PartnersScreen> createState() => _PartnersScreenState();
}

class _PartnersScreenState extends ConsumerState<PartnersScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);

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
            // ─── Title ──────────────────────────────────────────
            Text(
              'PARTNERS',
              style: text.rayonCondensed(
                theme.textTheme.displayLarge,
                color: colors.primaryText,
                fontWeight: FontWeight.w900,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'OFFICIAL PARTNER NETWORK',
              style: text.mono(
                theme.textTheme.labelSmall,
                fontWeight: FontWeight.w600,
                color: colors.secondaryText,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: CoolSpace.x5),

            // ─── Search bar ─────────────────────────────────────
            _SearchBar(
              query: _searchQuery,
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
            const SizedBox(height: CoolSpace.x5),

            // ─── Partner list ───────────────────────────────────
            _PartnerList(
              searchQuery: _searchQuery,
              onOpenRayonSports: _openRayonSports,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Search bar ─────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.query, required this.onChanged});

  final String query;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);

    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(CoolRadii.md),
        border: Border.all(color: colors.borderStrong),
      ),
      padding: const EdgeInsets.symmetric(horizontal: CoolSpace.x3),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: colors.secondaryText, size: 20),
          const SizedBox(width: CoolSpace.x2),
          Expanded(
            child: TextField(
              onChanged: onChanged,
              controller: TextEditingController(text: query)
                ..selection = TextSelection.collapsed(offset: query.length),
              style: text.rayon(
                theme.textTheme.bodyMedium,
                fontWeight: FontWeight.w600,
                color: colors.primaryText,
              ),
              cursorColor: colors.accent,
              decoration: InputDecoration(
                hintText: 'SEARCH PARTNERS...',
                hintStyle: text.rayon(
                  theme.textTheme.bodyMedium,
                  fontWeight: FontWeight.w600,
                  color: colors.tertiaryText,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (query.isNotEmpty)
            GestureDetector(
              onTap: () => onChanged(''),
              child: Icon(
                Icons.close_rounded,
                color: colors.secondaryText,
                size: 20,
              ),
            ),
        ],
      ),
    );
  }
}
