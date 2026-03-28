import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/rs_colors.dart';
import '../../../core/providers/engagement_providers.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../auth/providers/auth_provider.dart';
import '../../biopay/providers/biopay_providers.dart';
import '../../partners/providers/rayon_sports_provider.dart';
import '../providers/profile_view_provider.dart';
import '../widgets/profile_dialogs.dart';

part 'profile_screen_parts.dart';

// ─────────────────────────────────────────────────────────────────────
// ProfileScreen — faithful replica of the React reference screenshots
// Sections: Header → Blue Membership Card → FAN IDENTITY →
//   APP SETTINGS → SUPPORT (with LOGOUT in red)
// ─────────────────────────────────────────────────────────────────────

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  // ── Sign out ──────────────────────────────────────────────────────

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const ProfileSignOutDialog(),
    );

    if (confirmed != true || !mounted) return;

    await ref.read(authProvider.notifier).signOut();
    if (!mounted) return;

    final error = ref.read(authProvider).error;
    if (error != null && error.isNotEmpty) {
      CoolToast.error(context, error);
      return;
    }

    context.go(AppRoutes.splash);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final topPad = MediaQuery.viewPaddingOf(context).top;
    final bottomPad = MediaQuery.viewPaddingOf(context).bottom;

    final membership = ref.watch(rayonMembershipProvider);
    final rayon = ref.watch(rayonSportsDataProvider);
    final profile = ref.watch(profileViewProvider);
    final authState = ref.watch(authProvider);
    final featureFlags = ref.watch(featureFlagsStateProvider);
    final biopayProfile = ref.watch(biopayProfileProvider);

    final mem = membership.valueOrNull ?? rayon.valueOrNull?.membership;
    final memberId = profile.userId;
    final tier = mem != null ? mem.tier.name.toUpperCase() : 'GUEST';
    final tokens = mem?.points ?? 0;
    final progress = mem?.progressToNextTier ?? 0.0;
    final faceIdEnabled = featureFlags.isBiopayEnabled(
      isAdmin: authState.user?.isAdmin ?? false,
    );
    final faceIdSubtitle = !faceIdEnabled
        ? 'TEMPORARILY UNAVAILABLE'
        : biopayProfile.when(
            data: (profile) {
              if (profile?.active ?? false) {
                return 'REGISTERED - ${profile!.maskedRecipientValue}';
              }
              return 'SCAN YOUR FACE TO PAY';
            },
            loading: () => 'CHECKING FACE ID STATUS',
            error: (err, st) => 'SCAN YOUR FACE TO PAY',
          );

    return Scaffold(
      backgroundColor: colors.appBackground,
      body: CoolScreenBackground(
        child: CustomScrollView(
          slivers: [
            // ── Header ───────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  CoolSpace.x4,
                  topPad + CoolSpace.x3,
                  CoolSpace.x4,
                  0,
                ),
                child: Row(
                  children: [
                    // Back button
                    InkWell(
                      borderRadius: BorderRadius.circular(CoolRadii.pill),
                      onTap: () {
                        if (context.canPop()) {
                          context.pop();
                        }
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.10),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.arrow_back_rounded,
                          color: colors.primaryText,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: CoolSpace.x3),
                    // Title
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SETTINGS',
                            style: context.coolText.rayonCondensed(
                              Theme.of(context).textTheme.headlineSmall,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            'FAN IDENTITY',
                            style: context.coolText.mono(
                              Theme.of(context).textTheme.labelSmall,
                              fontWeight: FontWeight.w700,
                              color: colors.secondaryText,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Shield icon
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: RsColors.rsBlue.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.verified_user_rounded,
                        color: RsColors.rsBlue,
                        size: 22,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Content ──────────────────────────────────────────────
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                CoolSpace.x5,
                CoolSpace.x5,
                CoolSpace.x5,
                CoolSpace.x8 + bottomPad + 80,
              ),
              sliver: SliverList.list(
                children: [
                  // ── 1. Blue Membership Card ───────────────────────
                  _BlueMembershipCard(
                    memberId: memberId,
                    tier: tier,
                    tokens: tokens,
                    progress: progress,
                  ),
                  const SizedBox(height: CoolSpace.x6),

                  // ── 2. FAN IDENTITY section ───────────────────────
                  const _SectionLabel(label: 'FAN IDENTITY'),
                  const SizedBox(height: CoolSpace.x3),
                  _GlassCard(
                    child: Column(
                      children: [
                        _SettingsRow(
                          icon: Icons.emoji_events_outlined,
                          title: 'ACHIEVEMENTS',
                          subtitle: '12 UNLOCKED',
                          onTap: () => context.push(AppRoutes.missions),
                        ),
                        _SettingsDivider(),
                        _SettingsRow(
                          icon: Icons.receipt_long_outlined,
                          title: 'ORDER HISTORY',
                          subtitle: '3 RECENT ORDERS',
                          onTap: () => context.push(AppRoutes.profileOrders),
                        ),
                        _SettingsDivider(),
                        _SettingsRow(
                          icon: Icons.confirmation_number_outlined,
                          title: 'MY TICKETS',
                          subtitle: '2 UPCOMING MATCHES',
                          onTap: () => context.push(AppRoutes.rayonMyTickets),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: CoolSpace.x6),

                  // ── 3. APP SETTINGS section ───────────────────────
                  const _SectionLabel(label: 'APP SETTINGS'),
                  const SizedBox(height: CoolSpace.x3),
                  _GlassCard(
                    child: Column(
                      children: [
                        _SettingsRow(
                          icon: Icons.person_outline_rounded,
                          title: 'ACCOUNT DETAILS',
                          subtitle: 'PERSONAL INFORMATION',
                          onTap: () => context.push(AppRoutes.profileAccount),
                        ),
                        _SettingsDivider(),
                        _SettingsRow(
                          icon: Icons.face_retouching_natural_rounded,
                          title: 'FACE ID REGISTER',
                          subtitle: faceIdSubtitle,
                          onTap: () => context.push(AppRoutes.biopayRegister),
                        ),
                        _SettingsDivider(),
                        _SettingsRow(
                          icon: Icons.notifications_none_rounded,
                          title: 'NOTIFICATIONS',
                          subtitle: 'MATCH ALERTS & NEWS',
                          onTap: () =>
                              context.push(AppRoutes.profileNotifications),
                        ),
                        _SettingsDivider(),
                        _SettingsRow(
                          icon: Icons.lock_outline_rounded,
                          title: 'PRIVACY & SECURITY',
                          subtitle: 'BIOMETRICS & PIN',
                          onTap: () => context.push(AppRoutes.profilePrivacy),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: CoolSpace.x6),

                  // ── 4. SUPPORT section ────────────────────────────
                  const _SectionLabel(label: 'SUPPORT'),
                  const SizedBox(height: CoolSpace.x3),
                  _GlassCard(
                    child: Column(
                      children: [
                        _SettingsRow(
                          icon: Icons.help_outline_rounded,
                          title: 'HELP CENTER',
                          onTap: () => context.push(AppRoutes.profileHelp),
                        ),
                        _SettingsDivider(),
                        _SettingsRow(
                          icon: Icons.info_outline_rounded,
                          title: 'ABOUT RAYON APP',
                          subtitle: 'VERSION 2.4.0',
                          onTap: () => context.push(AppRoutes.profileAbout),
                        ),
                        _SettingsDivider(),
                        _SettingsRow(
                          icon: Icons.logout_rounded,
                          title: 'LOGOUT',
                          isDestructive: true,
                          onTap: _confirmSignOut,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
