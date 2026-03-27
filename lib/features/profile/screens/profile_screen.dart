import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/rs_colors.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../auth/providers/auth_provider.dart';
import '../../partners/providers/rayon_sports_provider.dart';
import '../providers/profile_view_provider.dart';
import '../widgets/profile_dialogs.dart';

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

    final mem = membership.valueOrNull ?? rayon.valueOrNull?.membership;
    final memberId = profile.userId;
    final tier = mem != null
        ? mem.tier.name.toUpperCase()
        : 'GUEST';
    final tokens = mem?.points ?? 0;
    final progress = mem?.progressToNextTier ?? 0.0;

    return Scaffold(
      backgroundColor: colors.appBackground,
      body: CoolScreenBackground(
        child: CustomScrollView(
        slivers: [
          // ── Header ───────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                CoolSpace.x4, topPad + CoolSpace.x3, CoolSpace.x4, 0,
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
              CoolSpace.x5, CoolSpace.x5, CoolSpace.x5,
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
                        onTap: () =>
                            context.push(AppRoutes.profileOrders),
                      ),
                      _SettingsDivider(),
                      _SettingsRow(
                        icon: Icons.confirmation_number_outlined,
                        title: 'MY TICKETS',
                        subtitle: '2 UPCOMING MATCHES',
                        onTap: () =>
                            context.push(AppRoutes.rayonMyTickets),
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
                        onTap: () =>
                            context.push(AppRoutes.profileAccount),
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
                        onTap: () =>
                            context.push(AppRoutes.profilePrivacy),
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
                        onTap: () =>
                            context.push(AppRoutes.profileHelp),
                      ),
                      _SettingsDivider(),
                      _SettingsRow(
                        icon: Icons.info_outline_rounded,
                        title: 'ABOUT RAYON APP',
                        subtitle: 'VERSION 2.4.0',
                        onTap: () =>
                            context.push(AppRoutes.profileAbout),
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

// ═════════════════════════════════════════════════════════════════════
// BLUE MEMBERSHIP CARD
// ═════════════════════════════════════════════════════════════════════

class _BlueMembershipCard extends StatelessWidget {
  const _BlueMembershipCard({
    required this.memberId,
    required this.tier,
    required this.tokens,
    required this.progress,
  });

  final String memberId;
  final String tier;
  final int tokens;
  final double progress;

  @override
  Widget build(BuildContext context) {
    const targetTokens = 3000;
    const rewardLabel = 'EARN 1 MATCH TICKET';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CoolSpace.x6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1565C0),
            RsColors.rsBlue,
            Color(0xFF42A5F5),
          ],
        ),
        borderRadius: BorderRadius.circular(CoolRadii.xl),
        boxShadow: [
          BoxShadow(
            color: RsColors.rsBlue.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: OFFICIAL MEMBER + GOLD TIER tag
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'OFFICIAL\nMEMBER',
                  style: context.coolText.mono(
                    Theme.of(context).textTheme.labelMedium,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.7),
                    letterSpacing: 1.5,
                    height: 1.4,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(CoolRadii.pill),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  '${tier.toUpperCase()}\nTIER',
                  textAlign: TextAlign.center,
                  style: context.coolText.mono(
                    Theme.of(context).textTheme.labelSmall,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.8,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x3),

          // Member ID
          Text(
            memberId.isNotEmpty ? memberId : '------',
            style: context.coolText.rayonCondensed(
              Theme.of(context).textTheme.displayLarge,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: CoolSpace.x5),

          // FAN TOKENS label
          Text(
            'FAN TOKENS',
            style: context.coolText.mono(
              Theme.of(context).textTheme.labelSmall,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.7),
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: CoolSpace.x2),

          // Token count + target + reward
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _fmtAmt(tokens),
                style: context.coolText.rayonCondensed(
                  Theme.of(context).textTheme.displayMedium,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _fmtAmt(targetTokens),
                    style: context.coolText.mono(
                      Theme.of(context).textTheme.titleMedium,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    rewardLabel,
                    style: context.coolText.mono(
                      Theme.of(context).textTheme.labelSmall,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.6),
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x4),

          // White progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(CoolRadii.pill),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: progress.clamp(0, 1),
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// SECTION LABEL  (e.g. "FAN IDENTITY", "APP SETTINGS", "SUPPORT")
// ═════════════════════════════════════════════════════════════════════

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

// ═════════════════════════════════════════════════════════════════════
// SETTINGS ROW  (icon circle + title + subtitle + chevron)
// ═════════════════════════════════════════════════════════════════════

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
            // Icon circle
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(CoolRadii.md),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.10),
                ),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: CoolSpace.x4),

            // Title + subtitle
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

            // Chevron
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

// ═════════════════════════════════════════════════════════════════════
// SETTINGS DIVIDER
// ═════════════════════════════════════════════════════════════════════

class _SettingsDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      color: Colors.white.withValues(alpha: 0.06),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// GLASS CARD
// ═════════════════════════════════════════════════════════════════════

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CoolSpace.x5,
        vertical: CoolSpace.x2,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(CoolRadii.xl),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
        ),
      ),
      child: child,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Helpers
// ═════════════════════════════════════════════════════════════════════

String _fmtAmt(int v) {
  final s = v.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}
