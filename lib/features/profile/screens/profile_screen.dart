import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/config/app_config_provider.dart';
import '../../../core/providers/engagement_providers.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../admin/providers/admin_workspace_access_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../biopay/providers/biopay_providers.dart';
import '../providers/profile_view_provider.dart';
import '../widgets/profile_dialogs.dart';

// ─────────────────────────────────────────────────────────────────────
// ProfileScreen (Settings tab root)
// Sections: Header → APP SETTINGS → SUPPORT
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

    context.go(AppRoutes.home);
  }

  // ── Delete account (Play Store Data Deletion compliance) ──────────

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const ProfileDeleteAccountDialog(),
    );

    if (confirmed != true || !mounted) return;

    // Show a blocking progress indicator.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProfileBlockingProgressDialog(
        message: context.l10n.deleteAccountAction,
      ),
    );

    await ref.read(authProvider.notifier).deleteAccount();
    if (!mounted) return;

    // Dismiss the progress dialog.
    Navigator.of(context, rootNavigator: true).pop();

    final error = ref.read(authProvider).error;
    if (error != null && error.isNotEmpty) {
      CoolToast.error(context, error);
      return;
    }

    CoolToast.success(context, context.l10n.deleteAccountAction);
    context.go(AppRoutes.home);
  }

  Future<void> _launchWhatsApp() async {
    final whatsapp = await ref
        .read(appConfigRepositoryProvider)
        .getSupportWhatsApp();
    final uri = Uri.parse('https://wa.me/$whatsapp');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      CoolToast.error(context, context.l10n.profileWhatsAppLaunchError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.coolSemanticColors;
    final topPad = MediaQuery.viewPaddingOf(context).top;
    final bottomPad = MediaQuery.viewPaddingOf(context).bottom;

    final profile = ref.watch(profileViewProvider);
    final featureFlags = ref.watch(featureFlagsStateProvider);
    final biopayProfile = ref.watch(biopayProfileProvider);

    final adminAccess = ref.watch(adminWorkspaceAccessProvider);

    final faceIdEnabled = featureFlags.isBiopayEnabled(
      isAdmin: adminAccess.hasPlatformAccess,
    );
    final faceIdSubtitle = !faceIdEnabled
        ? l10n.profileFaceIdComingSoon
        : biopayProfile.when(
            data: (profile) {
              if (profile?.active ?? false) {
                return l10n.profileFaceIdRegistered(
                  profile!.maskedRecipientValue,
                );
              }
              return l10n.profileFaceIdScanToPay;
            },
            loading: () => l10n.profileFaceIdCheckingStatus,
            error: (err, st) => l10n.profileFaceIdScanToPay,
          );

    return CoolScreenBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: CustomScrollView(
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
                    // Title (no back button — this is a shell tab root)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.settings.toUpperCase(),
                            style: context.coolText.displayCondensed(
                              Theme.of(context).textTheme.headlineSmall,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            l10n.profileIdentityTitle,
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

                  // ── APP SETTINGS section ─────────────────────────
                  _SectionLabel(label: l10n.profileAppSettingsSection),
                  const SizedBox(height: CoolSpace.x3),
                  _GlassCard(
                    child: Column(
                      children: [
                        _SettingsRow(
                          icon: Icons.person_outline_rounded,
                          title: l10n.profileAccountDetailsTitle,
                          subtitle: l10n.profilePersonalInformationSubtitle,
                          onTap: () => context.push(AppRoutes.profileAccount),
                        ),
                        _SettingsDivider(),
                        _SettingsRow(
                          icon: Icons.account_balance_wallet_outlined,
                          title: l10n.profileWalletMomoTitle,
                          subtitle: profile.momoLinked
                              ? profile.momoDisplayLabel
                              : l10n.profileSetupDefaultMomoSubtitle,
                          onTap: () => context.push(AppRoutes.settingsWallet),
                        ),
                        _SettingsDivider(),
                        _SettingsRow(
                          icon: Icons.receipt_long_rounded,
                          title: l10n.profileTransactionHistoryTitle,
                          subtitle: l10n.profileStatementsLedgerSubtitle,
                          onTap: () => context.push(AppRoutes.momoWallet),
                        ),
                        _SettingsDivider(),
                        _SettingsRow(
                          icon: Icons.face_retouching_natural_rounded,
                          title: l10n.profileFaceIdRegisterTitle,
                          subtitle: faceIdSubtitle,
                          onTap: () => context.push(AppRoutes.biopayRegister),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: CoolSpace.x6),

                  // ── SUPPORT section ──────────────────────────────
                  _SectionLabel(label: l10n.profileSupportSection),
                  const SizedBox(height: CoolSpace.x3),
                  _GlassCard(
                    child: Column(
                      children: [
                        if (adminAccess.hasAnyAdminAccess) ...[
                          _SettingsRow(
                            icon: Icons.admin_panel_settings_rounded,
                            title: l10n.profileAdminWorkspaceTitle,
                            subtitle: l10n.profileSystemManagementSubtitle,
                            onTap: () => context.push(AppRoutes.admin),
                          ),
                          _SettingsDivider(),
                        ],
                        _SettingsRow(
                          icon: Icons.chat_rounded,
                          title: l10n.profileHelpTitle,
                          subtitle: l10n.profileChatOnWhatsAppSubtitle,
                          onTap: _launchWhatsApp,
                        ),
                        _SettingsDivider(),
                        _SettingsRow(
                          icon: Icons.logout_rounded,
                          title: l10n.profileLogoutTitle,
                          isDestructive: true,
                          onTap: _confirmSignOut,
                        ),
                        _SettingsDivider(),
                        _SettingsRow(
                          icon: Icons.delete_outline_rounded,
                          title: l10n.deleteAccountAction,
                          isDestructive: true,
                          onTap: _confirmDeleteAccount,
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
    final textColor = isDestructive ? colors.danger : colors.primaryText;
    final iconColor = isDestructive ? colors.danger : colors.primaryText;

    return Semantics(
      button: true,
      label: subtitle != null ? '$title. $subtitle' : title,
      child: InkWell(
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
                  boxShadow: CoolShadows.ambientFloat(strength: 0.3),
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
                          fontWeight: FontWeight.w500,
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
      ),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // No-Line Rule: use whitespace instead of visible dividers
    return const SizedBox(height: CoolSpace.x1);
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(
        horizontal: CoolSpace.x5,
        vertical: CoolSpace.x2,
      ),
      child: child,
    );
  }
}
