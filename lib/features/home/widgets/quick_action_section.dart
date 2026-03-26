import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/cool_card.dart';
import '../providers/quick_action_provider.dart';

class QuickActionSection extends ConsumerWidget {
  const QuickActionSection({this.useCard = true, this.maxItems = 4, super.key});

  final bool useCard;
  final int maxItems;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionsAsync = ref.watch(currentCountryQuickActionsProvider);
    final l10n = context.l10n;

    return actionsAsync.when(
      data: (actions) => QuickActionListCard(
        items: actions
            .take(maxItems)
            .map(
              (action) => QuickActionData(
                title: action.title,
                subtitle: action.subtitle ?? '',
                route: action.route,
              ),
            )
            .toList(),
        useCard: useCard,
      ),
      loading: () => QuickActionListCard(
        items: _fallbackQuickActions(l10n).take(maxItems).toList(),
        useCard: useCard,
      ),
      error: (_, _) => QuickActionListCard(
        items: _fallbackQuickActions(l10n).take(maxItems).toList(),
        useCard: useCard,
      ),
    );
  }
}

class QuickActionListCard extends StatelessWidget {
  const QuickActionListCard({
    required this.items,
    this.useCard = true,
    super.key,
  });

  final List<QuickActionData> items;
  final bool useCard;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final visibleItems = items.take(4).toList(growable: false);
    final list = Column(
      children: [
        for (var index = 0; index < visibleItems.length; index++) ...[
          QuickActionRow(
            title: visibleItems[index].title,
            subtitle: visibleItems[index].subtitle,
            route: visibleItems[index].route,
          ),
          if (index != visibleItems.length - 1)
            SizedBox(height: useCard ? CoolSpace.x2 : CoolSpace.x3),
        ],
      ],
    );

    if (!useCard) {
      return list;
    }

    return CoolCard(
      useGradient: false,
      backgroundColor: colors.cardSurfaceStrong,
      borderRadius: CoolRadii.lg,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: list,
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
      return SizedBox(
        width: 56,
        height: 56,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.operationalSurface.withValues(alpha: 0.92),
            borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.md)),
            boxShadow: CoolShadows.floating(
              Theme.of(context).brightness,
              strength: 0.2,
            ),
          ),
          child: Center(
            child: Icon(_iconForRoute(route), size: 24, color: colors.accent),
          ),
        ),
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
            constraints: const BoxConstraints(minHeight: 84),
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
                          const SizedBox(height: CoolSpace.x1),
                          Text(
                            compactSubtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colors.secondaryText,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
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
    if (route.startsWith(AppRoutes.partners)) {
      return Icons.storefront_outlined;
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
      subtitle: 'Pay fast',
      route: AppRoutes.momo,
    ),
    QuickActionData(
      title: l10n.partners,
      subtitle: l10n.homeFallbackPartnersSubtitle,
      route: AppRoutes.partners,
    ),
    QuickActionData(
      title: l10n.navProfile,
      subtitle: 'Open settings',
      route: AppRoutes.profile,
    ),
  ];
}
