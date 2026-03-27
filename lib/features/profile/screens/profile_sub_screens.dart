import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/providers/notification_settings_provider.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/rs_colors.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../providers/profile_view_provider.dart';

// ═════════════════════════════════════════════════════════════════════
// REUSABLE SCAFFOLD (shared across all profile sub-screens)
// ═════════════════════════════════════════════════════════════════════

class _ProfileSubScaffold extends StatelessWidget {
  const _ProfileSubScaffold({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.slivers,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> slivers;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final topPad = MediaQuery.viewPaddingOf(context).top;
    final bottomPad = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      backgroundColor: colors.appBackground,
      body: CoolScreenBackground(
        child: CustomScrollView(
          slivers: [
            // ── Header ───────────────────────────────────────────
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
                    InkWell(
                      borderRadius: BorderRadius.circular(CoolRadii.pill),
                      onTap: () {
                        if (context.canPop()) context.pop();
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: context.coolText.rayonCondensed(
                              Theme.of(context).textTheme.headlineSmall,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            subtitle,
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
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: RsColors.rsBlue.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(icon, color: RsColors.rsBlue, size: 22),
                    ),
                  ],
                ),
              ),
            ),

            // ── Body ─────────────────────────────────────────────
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                CoolSpace.x5,
                CoolSpace.x5,
                CoolSpace.x5,
                CoolSpace.x8 + bottomPad + 80,
              ),
              sliver: SliverList.list(children: slivers),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// SHARED BUILDING BLOCKS
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

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: CoolSpace.x5,
        vertical: CoolSpace.x4,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(CoolRadii.xl),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: child,
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String title;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CoolSpace.x3),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(CoolRadii.md),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: colors.primaryText, size: 20),
          ),
          const SizedBox(width: CoolSpace.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.coolText.mono(
                    Theme.of(context).textTheme.labelSmall,
                    fontWeight: FontWeight.w600,
                    color: colors.secondaryText,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: context.coolText.mono(
                    Theme.of(context).textTheme.titleSmall,
                    fontWeight: FontWeight.w800,
                    color: valueColor ?? colors.primaryText,
                    letterSpacing: 0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, color: Colors.white.withValues(alpha: 0.06));
  }
}

// ═════════════════════════════════════════════════════════════════════
// 1. ACCOUNT DETAILS SCREEN
// ═════════════════════════════════════════════════════════════════════

class AccountDetailsScreen extends ConsumerWidget {
  const AccountDetailsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileViewProvider);
    final colors = context.coolSemanticColors;

    final memberSince = profile.createdAt != null
        ? '${profile.createdAt!.day}/${profile.createdAt!.month}/${profile.createdAt!.year}'
        : 'UNKNOWN';

    return _ProfileSubScaffold(
      title: 'ACCOUNT',
      subtitle: 'PERSONAL INFORMATION',
      icon: Icons.person_outline_rounded,
      slivers: [
        // ── IDENTITY section ────────────────────────────────
        const _SectionLabel(label: 'IDENTITY'),
        const SizedBox(height: CoolSpace.x3),
        _GlassCard(
          child: Column(
            children: [
              // Avatar + Name
              Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [RsColors.rsBlueLight, RsColors.rsBlue],
                      ),
                      borderRadius: BorderRadius.circular(CoolRadii.lg),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      profile.initials,
                      style: context.coolText.rayonCondensed(
                        Theme.of(context).textTheme.headlineMedium,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: CoolSpace.x4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.name.isNotEmpty
                              ? profile.name.toUpperCase()
                              : 'ANONYMOUS FAN',
                          style: context.coolText.rayonCondensed(
                            Theme.of(context).textTheme.titleLarge,
                            fontWeight: FontWeight.w900,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'MEMBER SINCE $memberSince',
                          style: context.coolText.mono(
                            Theme.of(context).textTheme.labelSmall,
                            fontWeight: FontWeight.w600,
                            color: colors.secondaryText,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: CoolSpace.x4),
              const _RowDivider(),
              _InfoRow(
                icon: Icons.badge_outlined,
                title: 'MEMBER ID',
                value: profile.userId.isNotEmpty ? profile.userId : '------',
              ),
              const _RowDivider(),
              _InfoRow(
                icon: Icons.phone_outlined,
                title: 'PHONE',
                value: profile.phone.isNotEmpty ? profile.phone : 'NOT SET',
              ),
              const _RowDivider(),
              _InfoRow(
                icon: Icons.flag_outlined,
                title: 'COUNTRY',
                value: profile.country.toUpperCase(),
              ),
            ],
          ),
        ),
        const SizedBox(height: CoolSpace.x6),

        // ── MOBILE MONEY section ────────────────────────────
        const _SectionLabel(label: 'MOBILE MONEY'),
        const SizedBox(height: CoolSpace.x3),
        _GlassCard(
          child: Column(
            children: [
              _InfoRow(
                icon: Icons.account_balance_wallet_outlined,
                title: 'MOMO STATUS',
                value: profile.momoLinked ? 'LINKED' : 'NOT LINKED',
                valueColor: profile.momoLinked
                    ? colors.success
                    : colors.secondaryText,
              ),
              if (profile.momoLinked) ...[
                const _RowDivider(),
                _InfoRow(
                  icon: Icons.phone_android_outlined,
                  title: 'MOMO NUMBER',
                  value: profile.momoDisplayLabel,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// 2. NOTIFICATIONS SETTINGS SCREEN
// ═════════════════════════════════════════════════════════════════════

class NotificationsSettingsScreen extends ConsumerWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifState = ref.watch(notificationSettingsProvider);
    final profile = ref.watch(profileViewProvider);
    final colors = context.coolSemanticColors;

    return _ProfileSubScaffold(
      title: 'NOTIFICATIONS',
      subtitle: 'ALERTS & UPDATES',
      icon: Icons.notifications_none_rounded,
      slivers: [
        // ── PUSH NOTIFICATIONS ──────────────────────────────
        const _SectionLabel(label: 'PUSH NOTIFICATIONS'),
        const SizedBox(height: CoolSpace.x3),
        _GlassCard(
          child: Column(
            children: [
              _ToggleRow(
                icon: Icons.notifications_active_outlined,
                title: 'ALL NOTIFICATIONS',
                subtitle: 'MASTER TOGGLE',
                value: profile.notificationsEnabled,
                isLoading: notifState.isLoading,
                onChanged: (v) => ref
                    .read(notificationSettingsProvider.notifier)
                    .setEnabled(v),
              ),
              const _RowDivider(),
              _ToggleRow(
                icon: Icons.sports_soccer_outlined,
                title: 'MATCH ALERTS',
                subtitle: 'KICKOFF & RESULTS',
                value: profile.notificationsEnabled,
                isLoading: false,
                onChanged: profile.notificationsEnabled
                    ? (v) => ref
                          .read(notificationSettingsProvider.notifier)
                          .setEnabled(v)
                    : null,
              ),
              const _RowDivider(),
              _ToggleRow(
                icon: Icons.local_offer_outlined,
                title: 'PROMOTIONS',
                subtitle: 'SHOP & MEMBERSHIP',
                value: profile.notificationsEnabled,
                isLoading: false,
                onChanged: profile.notificationsEnabled
                    ? (v) => ref
                          .read(notificationSettingsProvider.notifier)
                          .setEnabled(v)
                    : null,
              ),
              const _RowDivider(),
              _ToggleRow(
                icon: Icons.groups_outlined,
                title: 'GROUP UPDATES',
                subtitle: 'CONTRIBUTIONS & INVITES',
                value: profile.notificationsEnabled,
                isLoading: false,
                onChanged: profile.notificationsEnabled
                    ? (v) => ref
                          .read(notificationSettingsProvider.notifier)
                          .setEnabled(v)
                    : null,
              ),
            ],
          ),
        ),

        if (notifState.error != null) ...[
          const SizedBox(height: CoolSpace.x3),
          Container(
            padding: const EdgeInsets.all(CoolSpace.x4),
            decoration: BoxDecoration(
              color: colors.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(CoolRadii.lg),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: colors.danger,
                  size: 20,
                ),
                const SizedBox(width: CoolSpace.x3),
                Expanded(
                  child: Text(
                    notifState.error!,
                    style: context.coolText.mono(
                      Theme.of(context).textTheme.labelSmall,
                      fontWeight: FontWeight.w600,
                      color: colors.danger,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// 3. PRIVACY & SECURITY SCREEN
// ═════════════════════════════════════════════════════════════════════

class PrivacySecurityScreen extends StatelessWidget {
  const PrivacySecurityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _ProfileSubScaffold(
      title: 'PRIVACY',
      subtitle: 'SECURITY SETTINGS',
      icon: Icons.lock_outline_rounded,
      slivers: [
        // ── AUTHENTICATION ──────────────────────────────────
        const _SectionLabel(label: 'AUTHENTICATION'),
        const SizedBox(height: CoolSpace.x3),
        _GlassCard(
          child: Column(
            children: [
              _ToggleRow(
                icon: Icons.fingerprint_rounded,
                title: 'BIOMETRIC LOGIN',
                subtitle: 'FACE ID / FINGERPRINT',
                value: false,
                isLoading: false,
                onChanged: (v) => CoolToast.info(
                  context,
                  'Biometrics disabled on this device',
                ),
              ),
              const _RowDivider(),
              _ToggleRow(
                icon: Icons.pin_outlined,
                title: 'TRANSACTION PIN',
                subtitle: 'PAYMENT SECURITY',
                value: true,
                isLoading: false,
                onChanged: (v) =>
                    CoolToast.info(context, 'PIN required for payments'),
              ),
            ],
          ),
        ),
        const SizedBox(height: CoolSpace.x6),

        // ── DATA & PRIVACY ──────────────────────────────────
        const _SectionLabel(label: 'DATA & PRIVACY'),
        const SizedBox(height: CoolSpace.x3),
        _GlassCard(
          child: Column(
            children: [
              _ToggleRow(
                icon: Icons.visibility_off_outlined,
                title: 'HIDE BALANCES',
                subtitle: 'PRIVACY MODE',
                value: false,
                isLoading: false,
                onChanged: (v) => CoolToast.info(context, 'Balances visible'),
              ),
              const _RowDivider(),
              _SettingsActionRow(
                icon: Icons.delete_sweep_outlined,
                title: 'CLEAR CACHE',
                subtitle: 'FREE UP STORAGE',
                onTap: () {
                  CoolToast.success(context, 'Cache cleared');
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// 4. ORDER HISTORY SCREEN
// ═════════════════════════════════════════════════════════════════════

class OrderHistoryScreen extends StatelessWidget {
  const OrderHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;

    return _ProfileSubScaffold(
      title: 'ORDERS',
      subtitle: 'PURCHASE HISTORY',
      icon: Icons.receipt_long_outlined,
      slivers: [
        const _SectionLabel(label: 'RECENT ORDERS'),
        const SizedBox(height: CoolSpace.x3),

        // ── Empty state ─────────────────────────────────────
        _GlassCard(
          child: Column(
            children: [
              const SizedBox(height: CoolSpace.x4),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: RsColors.rsBlue.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.shopping_bag_outlined,
                  color: RsColors.rsBlue,
                  size: 32,
                ),
              ),
              const SizedBox(height: CoolSpace.x4),
              Text(
                'NO ORDERS YET',
                style: context.coolText.rayonCondensed(
                  Theme.of(context).textTheme.titleLarge,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: CoolSpace.x2),
              Text(
                'Your purchase history will appear here after your first order from the Rayon Sports shop.',
                textAlign: TextAlign.center,
                style: context.coolText.mono(
                  Theme.of(context).textTheme.bodySmall,
                  fontWeight: FontWeight.w600,
                  color: colors.secondaryText,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: CoolSpace.x5),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => context.push('/partners/rayon-sports/shop'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: RsColors.rsBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(CoolRadii.lg),
                    ),
                  ),
                  child: Text(
                    'VISIT SHOP',
                    style: context.coolText.mono(
                      Theme.of(context).textTheme.labelLarge,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: CoolSpace.x3),
            ],
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// 5. HELP CENTER SCREEN
// ═════════════════════════════════════════════════════════════════════

class HelpCenterScreen extends StatelessWidget {
  const HelpCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _ProfileSubScaffold(
      title: 'HELP',
      subtitle: 'SUPPORT CENTER',
      icon: Icons.help_outline_rounded,
      slivers: [
        // ── FAQ ─────────────────────────────────────────────
        const _SectionLabel(label: 'FAQ'),
        const SizedBox(height: CoolSpace.x3),
        const _GlassCard(
          child: Column(
            children: [
              _FaqItem(
                question: 'HOW DO I BUY TICKETS?',
                answer:
                    'Go to Tickets from the home screen, select a match, and choose your seat category. Payment is handled via MoMo USSD.',
              ),
              _RowDivider(),
              _FaqItem(
                question: 'HOW DO I EARN TOKENS?',
                answer:
                    'Attend matches, complete missions, purchase from the shop, and refer friends to earn fan tokens.',
              ),
              _RowDivider(),
              _FaqItem(
                question: 'WHAT IS BIOPAY?',
                answer:
                    'BioPay lets you authorize MoMo payments with facial recognition or QR codes — no PIN entry needed.',
              ),
              _RowDivider(),
              _FaqItem(
                question: 'HOW DO I JOIN A GROUP?',
                answer:
                    'Ask a group admin for an invite link or code. Open the link to automatically join the savings group.',
              ),
            ],
          ),
        ),
        const SizedBox(height: CoolSpace.x6),

        // ── CONTACT ─────────────────────────────────────────
        const _SectionLabel(label: 'CONTACT US'),
        const SizedBox(height: CoolSpace.x3),
        _GlassCard(
          child: Column(
            children: [
              _SettingsActionRow(
                icon: Icons.email_outlined,
                title: 'EMAIL SUPPORT',
                subtitle: 'support@rayonsports.rw',
                onTap: () async {
                  final uri = Uri.parse('mailto:support@rayonsports.rw');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } else {
                    if (context.mounted) {
                      CoolToast.info(context, 'No email app found');
                    }
                  }
                },
              ),
              const _RowDivider(),
              _SettingsActionRow(
                icon: Icons.chat_rounded,
                title: 'WHATSAPP SUPPORT',
                subtitle: '+250 795 588 248',
                onTap: () async {
                  final uri = Uri.parse('https://wa.me/250795588248');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } else {
                    if (context.mounted) {
                      CoolToast.error(context, 'Could not open WhatsApp');
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// 6. ABOUT SCREEN
// ═════════════════════════════════════════════════════════════════════

class AboutAppScreen extends StatelessWidget {
  const AboutAppScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;

    return _ProfileSubScaffold(
      title: 'ABOUT',
      subtitle: 'RAYON SPORTS APP',
      icon: Icons.info_outline_rounded,
      slivers: [
        // ── App branding card ───────────────────────────────
        Center(
          child: Column(
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [RsColors.rsBlueLight, RsColors.rsBlue],
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
                alignment: Alignment.center,
                child: Text(
                  'RS',
                  style: context.coolText.rayonCondensed(
                    Theme.of(context).textTheme.headlineLarge,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: CoolSpace.x4),
              Text(
                'RAYON SPORTS',
                style: context.coolText.rayonCondensed(
                  Theme.of(context).textTheme.headlineMedium,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: CoolSpace.x1),
              Text(
                'VERSION 2.4.0',
                style: context.coolText.mono(
                  Theme.of(context).textTheme.labelSmall,
                  fontWeight: FontWeight.w700,
                  color: colors.secondaryText,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: CoolSpace.x6),

        // ── APP INFO ────────────────────────────────────────
        const _SectionLabel(label: 'APP INFO'),
        const SizedBox(height: CoolSpace.x3),
        const _GlassCard(
          child: Column(
            children: [
              _InfoRow(
                icon: Icons.code_rounded,
                title: 'BUILD',
                value: '2026.03.27',
              ),
              _RowDivider(),
              _InfoRow(
                icon: Icons.flutter_dash_rounded,
                title: 'FRAMEWORK',
                value: 'FLUTTER',
              ),
              _RowDivider(),
              _InfoRow(
                icon: Icons.cloud_outlined,
                title: 'BACKEND',
                value: 'SUPABASE',
              ),
            ],
          ),
        ),
        const SizedBox(height: CoolSpace.x6),

        // ── LEGAL ───────────────────────────────────────────
        const _SectionLabel(label: 'LEGAL'),
        const SizedBox(height: CoolSpace.x3),
        _GlassCard(
          child: Column(
            children: [
              _SettingsActionRow(
                icon: Icons.description_outlined,
                title: 'TERMS OF SERVICE',
                onTap: () async {
                  final uri = Uri.parse('https://rayonsports.rw/terms');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
              const _RowDivider(),
              _SettingsActionRow(
                icon: Icons.privacy_tip_outlined,
                title: 'PRIVACY POLICY',
                onTap: () async {
                  final uri = Uri.parse('https://rayonsports.rw/privacy');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
              const _RowDivider(),
              _SettingsActionRow(
                icon: Icons.gavel_rounded,
                title: 'OPEN SOURCE',
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'Rayon Sports',
                  applicationVersion: '2.4.0',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// HELPER WIDGETS
// ═════════════════════════════════════════════════════════════════════

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.isLoading,
    this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool isLoading;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CoolSpace.x3),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(CoolRadii.md),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: colors.primaryText, size: 20),
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
                    color: colors.primaryText,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: context.coolText.mono(
                    Theme.of(context).textTheme.labelSmall,
                    fontWeight: FontWeight.w600,
                    color: colors.secondaryText,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          if (isLoading)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeTrackColor: RsColors.rsBlue,
            ),
        ],
      ),
    );
  }
}

class _SettingsActionRow extends StatelessWidget {
  const _SettingsActionRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: CoolSpace.x3),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(CoolRadii.md),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: colors.primaryText, size: 20),
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
                      color: colors.primaryText,
                      letterSpacing: 0.8,
                    ),
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
                    ),
                  ],
                ],
              ),
            ),
            if (onTap != null)
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

class _FaqItem extends StatefulWidget {
  const _FaqItem({required this.question, required this.answer});

  final String question;
  final String answer;

  @override
  State<_FaqItem> createState() => _FaqItemState();
}

class _FaqItemState extends State<_FaqItem> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;

    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: CoolSpace.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(CoolRadii.md),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.help_outline_rounded,
                    color: RsColors.rsBlue,
                    size: 20,
                  ),
                ),
                const SizedBox(width: CoolSpace.x4),
                Expanded(
                  child: Text(
                    widget.question,
                    style: context.coolText.mono(
                      Theme.of(context).textTheme.titleSmall,
                      fontWeight: FontWeight.w800,
                      color: colors.primaryText,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: colors.secondaryText,
                  size: 22,
                ),
              ],
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.only(left: 60, top: CoolSpace.x3),
                child: Text(
                  widget.answer,
                  style: context.coolText.mono(
                    Theme.of(context).textTheme.bodySmall,
                    fontWeight: FontWeight.w600,
                    color: colors.secondaryText,
                    height: 1.6,
                  ),
                ),
              ),
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
          ],
        ),
      ),
    );
  }
}
