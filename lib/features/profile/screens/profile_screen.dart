import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/providers/engagement_providers.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../auth/providers/auth_provider.dart';
import '../../biopay/providers/biopay_providers.dart';
import '../providers/profile_view_provider.dart';
import '../widgets/profile_dialogs.dart';

// ─────────────────────────────────────────────────────────────────────
// ProfileScreen
// Sections: Header → IDENTITY → APP SETTINGS → SUPPORT
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

    final profile = ref.watch(profileViewProvider);
    final authState = ref.watch(authProvider);
    final featureFlags = ref.watch(featureFlagsStateProvider);
    final biopayProfile = ref.watch(biopayProfileProvider);

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
                          color: colors.cardSurfaceStrong,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colors.border,
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
                            style: context.coolText.displayCondensed(
                              Theme.of(context).textTheme.headlineSmall,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            'IDENTITY',
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
                        color: colors.accent.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.verified_user_rounded,
                        color: colors.accent,
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
                  const SizedBox(height: CoolSpace.x6),

                  // ── 2. FAN IDENTITY section ───────────────────────
                  const _SectionLabel(label: 'IDENTITY'),
                  const SizedBox(height: CoolSpace.x3),
                  _GlassCard(
                    child: Column(
                      children: [

                        _SettingsRow(
                          icon: Icons.receipt_long_outlined,
                          title: 'ORDER HISTORY',
                          subtitle: '3 RECENT ORDERS',
                          onTap: () => context.push(AppRoutes.profileOrders),
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
                          icon: Icons.account_balance_wallet_outlined,
                          title: 'WALLET & MOMO',
                          subtitle: profile.momoLinked
                              ? profile.momoDisplayLabel
                              : 'SET UP YOUR DEFAULT MOMO',
                          onTap: () => context.push(AppRoutes.settingsWallet),
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
                          subtitle: 'ALERTS & NEWS',
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
                          title: 'ABOUT SUPER APP',
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Text(
      label,
      style: context.coolText.mono(
        Theme.of(context).textTheme.labelSmall,
        fontWeight: FontWeight.w700,
        color: colors.secondaryText,
        letterSpacing: 2.0,
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.isDestructive = false,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool isDestructive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final textColor = isDestructive
        ? const Color(0xFFEF5350)
        : colors.primaryText;
    final iconColor = isDestructive
        ? const Color(0xFFEF5350)
        : colors.primaryText;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: CoolSpace.x4),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colors.cardSurfaceStrong,
                borderRadius: BorderRadius.circular(CoolRadii.md),
                border: Border.all(color: colors.border),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: CoolSpace.x4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: context.coolText.mono(
                      Theme.of(context).textTheme.titleSmall,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                      letterSpacing: 0.8,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: context.coolText.mono(
                        Theme.of(context).textTheme.labelSmall,
                        fontWeight: FontWeight.w600,
                        color: colors.secondaryText,
                        letterSpacing: 0.8,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: colors.secondaryText,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, color: context.coolSemanticColors.divider);
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return CoolCard(
      backgroundColor: colors.cardSurfaceStrong,
      borderColor: colors.border,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CoolSpace.x5,
          vertical: CoolSpace.x2,
        ),
        child: child,
      ),
    );
  }
}
