import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/cool_foundations.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../providers/quick_action_provider.dart';

class QuickActionSection extends ConsumerWidget {
  const QuickActionSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionsAsync = ref.watch(currentCountryQuickActionsProvider);
    final l10n = context.l10n;

    return actionsAsync.when(
      data: (actions) => QuickActionListCard(
        items: actions
            .take(4)
            .map(
              (action) => QuickActionData(
                title: action.title,
                subtitle: action.subtitle ?? '',
                route: action.route,
              ),
            )
            .toList(),
      ),
      loading: () => QuickActionListCard(items: _fallbackQuickActions(l10n)),
      error: (_, _) => QuickActionListCard(items: _fallbackQuickActions(l10n)),
    );
  }
}

class QuickActionListCard extends StatelessWidget {
  const QuickActionListCard({super.key, required this.items});

  final List<QuickActionData> items;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final visibleItems = items.take(4).toList(growable: false);
    return CoolCard(
      useGradient: false,
      backgroundColor: colors.cardSurfaceStrong,
      borderRadius: CoolRadii.lg,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          for (var index = 0; index < visibleItems.length; index++) ...[
            QuickActionRow(
              title: visibleItems[index].title,
              subtitle: visibleItems[index].subtitle,
              route: visibleItems[index].route,
            ),
            if (index != visibleItems.length - 1)
              Divider(
                color: colors.border,
                height: 1,
                indent: 20,
                endIndent: 20,
              ),
          ],
        ],
      ),
    );
  }
}

class QuickActionRow extends StatelessWidget {
  const QuickActionRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final String title;
  final String subtitle;
  final String route;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final compactTitle = _shortActionTitle(context, title, route);
    final compactSubtitle = subtitle.trim();

    Widget leadingIcon() {
      return Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: colors.operationalSurface,
          borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.md)),
          border: Border.all(color: colors.border),
        ),
        alignment: Alignment.center,
        child: Icon(_iconForRoute(route), size: 24, color: colors.accent),
      );
    }

    final trailingIcon = Icon(
      Icons.arrow_forward_rounded,
      size: 20,
      color: colors.secondaryText,
    );

    return Semantics(
      button: true,
      label: compactSubtitle.isEmpty
          ? 'Quick action $compactTitle'
          : 'Quick action $compactTitle. $compactSubtitle',
      hint: 'Double tap to open',
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.md)),
          onTap: () => openQuickActionRoute(context, route),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 76),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                children: [
                  leadingIcon(),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          compactTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: colors.primaryText,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (compactSubtitle.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            compactSubtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colors.secondaryText,
                              fontWeight: FontWeight.w700,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  trailingIcon,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static IconData _iconForRoute(String route) {
    if (route.startsWith(AppRoutes.groups)) {
      return Icons.people_alt_outlined;
    }
    if (route.startsWith(AppRoutes.momo)) {
      return Icons.account_balance_wallet_outlined;
    }
    if (route.startsWith(AppRoutes.mobility)) {
      return Icons.directions_car_outlined;
    }
    if (route.startsWith(AppRoutes.partners)) {
      return Icons.storefront_outlined;
    }
    if (route.startsWith(AppRoutes.credit)) {
      return Icons.insights_outlined;
    }
    return Icons.arrow_outward_rounded;
  }

  static String _shortActionTitle(
    BuildContext context,
    String title,
    String route,
  ) {
    final l10n = context.l10n;
    final normalized = title.trim();
    if (normalized.isEmpty) {
      return l10n.openAction;
    }
    if (route.startsWith(AppRoutes.momo)) {
      return l10n.homeActionPay;
    }
    if (route.startsWith(AppRoutes.mobility)) {
      return l10n.homeActionTrips;
    }
    return normalized;
  }
}

class QuickActionData {
  const QuickActionData({
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final String title;
  final String subtitle;
  final String route;
}

List<QuickActionData> _fallbackQuickActions(AppLocalizations l10n) {
  return <QuickActionData>[
    QuickActionData(
      title: l10n.navGroups,
      subtitle: l10n.homeFallbackGroupsSubtitle,
      route: AppRoutes.groups,
    ),
    const QuickActionData(
      title: 'Momo Pay',
      subtitle: 'Pay At Shops And',
      route: AppRoutes.momo,
    ),
    QuickActionData(
      title: l10n.partners,
      subtitle: l10n.homeFallbackPartnersSubtitle,
      route: AppRoutes.partners,
    ),
    QuickActionData(
      title: l10n.navMobility,
      subtitle: l10n.homeFallbackTripsSubtitle,
      route: AppRoutes.mobility,
    ),
  ];
}
