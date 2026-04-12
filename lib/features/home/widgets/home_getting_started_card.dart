import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_icon_box.dart';
import '../../../shared/widgets/cool_list_tile.dart';
import '../../../shared/widgets/cool_section_card.dart';
import '../../auth/providers/auth_provider.dart';
import '../../groups/providers/groups_provider.dart';

// ─────────────────────────────────────────────────────────────────────
// HomeGettingStartedCard
//
// Shown to first-time users who have:
//   - zero groups AND no MoMo linked
// Dismissible — once dismissed, stays hidden for the session.
// Guides the user toward their first meaningful action.
// ─────────────────────────────────────────────────────────────────────

/// Provider to track whether the card has been dismissed this session.
final homeGettingStartedDismissedProvider = StateProvider<bool>((ref) => false);

class HomeGettingStartedCard extends ConsumerWidget {
  const HomeGettingStartedCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dismissed = ref.watch(homeGettingStartedDismissedProvider);
    if (dismissed) {
      return const SizedBox.shrink();
    }

    final user = ref.watch(currentUserProvider);
    final groups = ref.watch(myGroupsProvider).valueOrNull ?? const [];
    final hasMomo = user?.hasMomoRecipient ?? false;
    final hasGroups = groups.isNotEmpty;

    // Only show when the user is genuinely new — no groups and no MoMo.
    if (hasMomo && hasGroups) {
      return const SizedBox.shrink();
    }

    final l10n = context.l10n;
    final colors = context.coolSemanticColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.homeGettingStartedTitle,
                style: context.coolText.headline(
                  Theme.of(context).textTheme.titleLarge,
                  color: colors.primaryText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () =>
                    ref
                            .read(homeGettingStartedDismissedProvider.notifier)
                            .state =
                        true,
                borderRadius: BorderRadius.circular(CoolRadii.pill),
                child: Padding(
                  padding: const EdgeInsets.all(CoolSpace.x2),
                  child: Icon(
                    CoolIcons.close,
                    size: 18,
                    color: colors.tertiaryText,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: CoolSpace.x3),
        CoolSectionCard.glass(
          children: [
            if (!hasMomo)
              CoolListTile(
                leading: const CoolIconBox(
                  icon: CoolIcons.wallet,
                  variant: CoolIconBoxVariant.solid,
                ),
                title: l10n.homeGettingStartedLinkMomo,
                subtitle: l10n.homeGettingStartedLinkMomoSub,
                onTap: () => context.push(AppRoutes.settingsWallet),
              ),
            if (!hasGroups) ...[
              CoolListTile(
                leading: const CoolIconBox(
                  icon: CoolIcons.members,
                  variant: CoolIconBoxVariant.solid,
                ),
                title: l10n.homeGettingStartedCreateGroup,
                subtitle: l10n.homeGettingStartedCreateGroupSub,
                onTap: () => context.push(AppRoutes.groupCreate),
              ),
              CoolListTile(
                leading: const CoolIconBox(
                  icon: CoolIcons.search,
                  variant: CoolIconBoxVariant.solid,
                ),
                title: l10n.homeGettingStartedExploreGroups,
                subtitle: l10n.homeGettingStartedExploreGroupsSub,
                onTap: () => context.push(AppRoutes.groups),
              ),
            ],
          ],
        ),
        const SizedBox(height: CoolSpace.x4),
        // ── M6: How it works — minimal contextual help ─────────
        Text(
          l10n.homeHowItWorksTitle,
          style: context.coolText.headline(
            Theme.of(context).textTheme.titleSmall,
            color: colors.secondaryText,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: CoolSpace.x2),
        _HowItWorksStep(number: '1', text: l10n.homeHowItWorksStep1),
        _HowItWorksStep(number: '2', text: l10n.homeHowItWorksStep2),
        _HowItWorksStep(number: '3', text: l10n.homeHowItWorksStep3),
      ],
    );
  }
}

class _HowItWorksStep extends StatelessWidget {
  const _HowItWorksStep({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: CoolSpace.x2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(CoolRadii.sm),
            ),
            child: Text(
              number,
              style: context.coolText.mobiLabel(color: colors.accent),
            ),
          ),
          const SizedBox(width: CoolSpace.x3),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.secondaryText),
            ),
          ),
        ],
      ),
    );
  }
}
