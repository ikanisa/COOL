part of '../screens/partners_screen.dart';

extension _PartnersScreenController on _PartnersScreenState {
  List<String> _tabLabels(BuildContext context) => const <String>[
    'Football',
    'Finance',
    'Services',
  ];

  Future<void> _openRayonSports() async {
    try {
      final authState = ref.read(authProvider);
      final userId = authState.user?.id ?? authState.session?.user.id;

      if (userId == null || userId.isEmpty) {
        if (!mounted) {
          return;
        }
        context.push(AppRoutes.rayonHome);
        return;
      }

      final notifier = ref.read(rayonSportsProvider.notifier);
      final membershipResult = await notifier.ensureMembership();

      if (membershipResult.created) {
        if (!mounted) {
          return;
        }
        await _showRayonWelcomeSheet(membershipResult.membership);
      }

      if (!mounted) {
        return;
      }
      context.push(AppRoutes.rayonHome);
    } catch (error) {
      if (!mounted) {
        return;
      }
      CoolToast.error(context, error.toString());
    }
  }

  Future<void> _showRayonWelcomeSheet(RsFanMembership membership) {
    return showCoolBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final colors = context.coolSemanticColors;
        final text = context.coolText;
        final space = context.coolSpace;
        final theme = Theme.of(context);
        final perks = _membershipPerks(sheetContext, membership.tier);
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(sheetContext).viewPadding.bottom + 16,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.cardSurfaceStrong,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: colors.borderStrong),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: colors.borderStrong,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  Text(
                    'Welcome to Rayon Sports',
                    style: text.rayonCondensed(
                      theme.textTheme.headlineMedium,
                      fontWeight: FontWeight.w900,
                      color: colors.primaryText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Membership is active across tickets, clubs, and store access.',
                    style: text.rayon(
                      theme.textTheme.bodyMedium,
                      fontWeight: FontWeight.w600,
                      color: colors.secondaryText,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  RsMembershipCard(membership: membership),
                  if (perks.isNotEmpty) ...[
                    SizedBox(height: space.x4),
                    Wrap(
                      spacing: space.x2,
                      runSpacing: space.x2,
                      children: perks
                          .map((perk) => _MembershipPerkChip(label: perk))
                          .toList(growable: false),
                    ),
                  ],
                  const SizedBox(height: 18),
                  CoolButton(
                    label: context.l10n.openRayonSports,
                    onTap: () => Navigator.of(sheetContext).pop(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

List<String> _membershipPerks(BuildContext context, FanTier tier) {
  return switch (tier) {
    FanTier.blue => <String>[
      'Fan registry access',
      'Club updates',
      'Member queue access',
    ],
    FanTier.silver => <String>[
      'Priority ticket access',
      'Club updates',
      'Member queue access',
    ],
    FanTier.gold => <String>[
      'Priority ticket access',
      'Shop discount',
      'VIP fast lane',
    ],
    FanTier.platinum => <String>[
      'VIP access',
      'Shop discount',
      'Exclusive events',
    ],
  };
}

class _MembershipPerkChip extends StatelessWidget {
  const _MembershipPerkChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: colors.chipBackground,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        label,
        style: text.rayon(
          theme.textTheme.labelMedium,
          fontWeight: FontWeight.w700,
          color: colors.primaryText,
        ),
      ),
    );
  }
}
