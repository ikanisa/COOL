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
import '../../../shared/widgets/cool_icon_box.dart';
import '../../../shared/widgets/cool_list_tile.dart';
import '../../../shared/widgets/cool_section_card.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../admin/providers/admin_workspace_access_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../biopay/providers/biopay_providers.dart';
import '../providers/profile_view_provider.dart';
import '../widgets/profile_dialogs.dart';

// ─────────────────────────────────────────────────────────────────────
// ProfileScreen (Settings tab root)
// Widget-first minimalist redesign:
// - CoolSectionCard replaces manual _GlassCard + Column + _SettingsDivider
// - CoolListTile replaces _SettingsRow
// - Subtitles removed unless they show data (MoMo number, Face ID status)
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

    CoolToast.success(context, context.l10n.deleteAccountSuccess);
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
    final topPad = MediaQuery.viewPaddingOf(context).top;
    final bottomPad = MediaQuery.viewPaddingOf(context).bottom;

    final profile = ref.watch(profileViewProvider);
    final featureFlags = ref.watch(featureFlagsStateProvider);
    final biopayProfile = ref.watch(biopayProfileProvider);

    final adminAccess = ref.watch(adminWorkspaceAccessProvider);

    final faceIdEnabled = featureFlags.isBiopayEnabled(
      isAdmin: adminAccess.hasPlatformAccess,
    );
    // Only show subtitle when it carries data — not a description.
    final faceIdSubtitle = !faceIdEnabled
        ? l10n.profileFaceIdComingSoon
        : biopayProfile.when(
            data: (profile) {
              if (profile?.active ?? false) {
                return profile!.maskedRecipientValue;
              }
              return null; // No subtitle — icon is self-explanatory
            },
            loading: () => null,
            error: (err, st) => null,
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
                    Expanded(
                      child: Text(
                        l10n.settings,
                        style: context.coolText.headline(
                          Theme.of(context).textTheme.titleLarge,
                          fontWeight: FontWeight.w600,
                        ),
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
                  const SizedBox(height: CoolSpace.x4),

                  // ── APP SETTINGS ────────────────────────────────
                  CoolSectionCard.glass(
                    sectionLabel: l10n.profileAppSettingsSection,
                    children: [
                      CoolListTile(
                        leading: const CoolIconBox(icon: CoolIcons.profile),
                        title: l10n.profileAccountDetailsTitle,
                        onTap: () => context.push(AppRoutes.profileAccount),
                      ),
                      CoolListTile(
                        leading: const CoolIconBox(icon: CoolIcons.wallet),
                        title: l10n.profileWalletMomoTitle,
                        subtitle: profile.momoLinked
                            ? profile.momoDisplayLabel
                            : null,
                        onTap: () => context.push(AppRoutes.settingsWallet),
                      ),
                      CoolListTile(
                        leading: const CoolIconBox(icon: CoolIcons.history),
                        title: l10n.profileTransactionHistoryTitle,
                        onTap: () => context.push(AppRoutes.momoWallet),
                      ),
                      CoolListTile(
                        leading: const CoolIconBox(icon: CoolIcons.faceId),
                        title: l10n.profileFaceIdRegisterTitle,
                        subtitle: faceIdSubtitle,
                        onTap: () => context.push(AppRoutes.biopayRegister),
                      ),
                    ],
                  ),
                  const SizedBox(height: CoolSpace.x6),

                  // ── SUPPORT ────────────────────────────────────
                  CoolSectionCard.glass(
                    sectionLabel: l10n.profileSupportSection,
                    children: [
                      if (adminAccess.hasAnyAdminAccess)
                        CoolListTile(
                          leading: const CoolIconBox(icon: CoolIcons.admin),
                          title: l10n.profileAdminWorkspaceTitle,
                          onTap: () => context.push(AppRoutes.admin),
                        ),
                      CoolListTile(
                        leading: const CoolIconBox(icon: CoolIcons.support),
                        title: l10n.profileHelpTitle,
                        onTap: _launchWhatsApp,
                      ),
                    ],
                  ),
                  const SizedBox(height: CoolSpace.x6),

                  // ── ACCOUNT (destructive) ──────────────────────
                  CoolSectionCard.glass(
                    sectionLabel: l10n.profileAccountDetailsTitle.toUpperCase(),
                    children: [
                      CoolListTile(
                        leading: const CoolIconBox(icon: CoolIcons.logout),
                        title: l10n.profileLogoutTitle,
                        isDestructive: true,
                        onTap: _confirmSignOut,
                      ),
                      CoolListTile(
                        leading: const CoolIconBox(icon: CoolIcons.delete),
                        title: l10n.deleteAccountAction,
                        isDestructive: true,
                        onTap: _confirmDeleteAccount,
                      ),
                    ],
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
