
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
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(sheetContext).viewPadding.bottom + 16,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.border2),
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
                      color: AppColors.border2,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  Text(
                    'Welcome to Rayon Sports',
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: AppColors.rsWhite,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Membership active Tickets clubs',
                    style: GoogleFonts.barlow(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text2,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  RsMembershipCard(
                    fanName: membership.displayName,
                    fanId: membership.membershipNumber,
                    tier: membership.tier,
                    chapter: membership.chapter,
                    year: membership.joinedAt.year,
                    perks: _membershipPerks(sheetContext, membership.tier),
                  ),
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