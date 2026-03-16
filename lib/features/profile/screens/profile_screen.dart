import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config_provider.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';

import '../../../core/status/providers/cool_status_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_preference.dart';
import '../../../core/theme/theme_preference_provider.dart';
import '../../../shared/widgets/cool_screen_background.dart';

import '../../../shared/widgets/cool_toast.dart';
import '../../admin/providers/admin_workspace_access_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../credit/providers/credit_provider.dart';
import '../../mobility/providers/driver_provider.dart';
import '../../partners/rayon/models/rs_models.dart' show FanTier;
import '../providers/profile_view_provider.dart';
import '../widgets/profile_data.dart';
import '../widgets/profile_app_access_sheet.dart';
import '../widgets/profile_dialogs.dart';
import '../widgets/profile_header_widgets.dart';
import '../widgets/profile_settings_widgets.dart';
import '../widgets/profile_theme_sheet.dart';

/// User profile and settings hub.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late final ProviderSubscription<AuthState> _authSubscription;
  bool _didRequestDriverProfile = false;

  String _tierLabel(FanTier tier) {
    final l10n = context.l10n;
    return switch (tier) {
      FanTier.blue => l10n.profileTierBlue,
      FanTier.silver => l10n.profileTierSilver,
      FanTier.gold => l10n.profileTierGold,
      FanTier.platinum => l10n.profileTierPlatinum,
    };
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final userId = ref.read(authProvider).user?.id;
      if (userId != null && userId.isNotEmpty) {
        ref.read(coolStatusProvider.notifier).load(userId);
      }
      _maybeLoadDriverProfile(ref.read(authProvider));
    });

    _authSubscription = ref.listenManual<AuthState>(authProvider, (
      previous,
      next,
    ) {
      _maybeLoadDriverProfile(next);
    });
  }

  @override
  void dispose() {
    _authSubscription.close();
    super.dispose();
  }

  void _maybeLoadDriverProfile(AuthState authState) {
    if (_didRequestDriverProfile) {
      return;
    }

    final user = authState.user;
    final shouldLoadDriverProfile =
        user?.isDriver == true ||
        (user?.vehicleType?.trim().isNotEmpty ?? false);
    if (!shouldLoadDriverProfile) {
      return;
    }

    _didRequestDriverProfile = true;
    unawaited(ref.read(driverProvider.notifier).loadDriverProfile());
  }

  // ── App access sheet ──────────────────────────────────────────────────

  Future<void> _showAppAccessSheet() {
    return ProfileAppAccessSheet.show(context);
  }

  Future<void> _showThemeSheet() {
    return ProfileThemeSheet.show(context);
  }

  // ── Sign out ──────────────────────────────────────────────────────────

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const ProfileSignOutDialog(),
    );

    if (confirmed != true || !mounted) return;

    await ref.read(authProvider.notifier).signOut();
    if (!mounted) {
      return;
    }

    final error = ref.read(authProvider).error;
    if (error != null && error.isNotEmpty) {
      CoolToast.error(context, error);
      return;
    }

    // Invalidate cached providers to prevent stale data leaking across sessions.
    ref.invalidate(coolStatusProvider);
    ref.invalidate(driverProvider);
    ref.invalidate(creditDashboardProvider);

    context.go(AppRoutes.onboarding);
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const ProfileDeleteAccountDialog(),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProfileBlockingProgressDialog(
        message: context.l10n.profileDeletingAccount,
      ),
    );

    await ref.read(authProvider.notifier).deleteAccount();
    if (!mounted) {
      return;
    }

    Navigator.of(context, rootNavigator: true).pop();

    final error = ref.read(authProvider).error;
    if (error != null && error.isNotEmpty) {
      CoolToast.error(context, error);
      return;
    }

    // Invalidate cached providers before leaving.
    ref.invalidate(coolStatusProvider);
    ref.invalidate(driverProvider);
    ref.invalidate(creditDashboardProvider);

    context.go(AppRoutes.onboarding);
  }



  Future<void> _showMomoQrSheet(ProfileData profile) async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ProfileSheet(
        child: ProfileMomoQrCard(
          momoNumber: profile.momoNumber,
          countryCode: profile.countryCode,
        ),
      ),
    );
  }



  Future<void> _openSupportWhatsApp() async {
    try {
      final number = await ref.read(
        currentCountrySupportWhatsAppProvider.future,
      );
      final uri = Uri.parse('https://wa.me/$number');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }

      if (!mounted) {
        return;
      }
      CoolToast.error(context, context.l10n.profileSupportOpenError);
    } catch (_) {
      if (!mounted) {
        return;
      }
      CoolToast.error(context, context.l10n.profileSupportUnavailable);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final themePreference = ref.watch(themePreferenceProvider);
    final profile = ref.watch(profileViewProvider);
    final status = ref.watch(coolStatusProvider).valueOrNull;
    final adminAccess = ref.watch(adminWorkspaceAccessProvider);
    const profileBottomPadding = 140.0;

    // ── Account rows ───────────────────────────────────────────────
    final accountRows = <ProfileSettingsRow>[
      ProfileSettingsRow(
        icon: Icons.account_balance_wallet_outlined,
        label: 'Wallet',
        value: profile.momoLinked
            ? profile.momoDisplayLabel
            : 'Link wallet',
        valueColor: profile.momoLinked ? AppColors.accent : AppColors.text3,
        onTap: () => context.push(AppRoutes.profileWallet),
      ),
      if (status != null)
        ProfileSettingsRow(
          icon: Icons.token_rounded,
          label: 'Cool Tokens',
          value: '${_tierLabel(status.tier)} · ${status.totalPoints} pts',
          valueColor: AppColors.accent,
          onTap: () => context.push(AppRoutes.tokens),
        ),
      ProfileSettingsRow(
        icon: Icons.swap_horiz_rounded,
        label: 'Mobility',
        value: profile.isDriver ? 'Driver' : 'Passenger',
        valueColor: profile.travelRoleValueColor,
        onTap: () => context.push(AppRoutes.profileTravelRole),
      ),
      ProfileSettingsRow(
        icon: Icons.sms_outlined,
        label: 'MoMo Statements',
        value: profile.mobileMoneyActivityLabel,
        valueColor: profile.momoStatementCount > 0
            ? AppColors.blue
            : AppColors.text3,
        onTap: () => context.push(
          profile.momoStatementCount > 0
              ? AppRoutes.momoStatements
              : AppRoutes.momo,
        ),
      ),
      ProfileSettingsRow(
        icon: Icons.person_outlined,
        label: 'Personal Info',
        value: profile.officialName.isNotEmpty
            ? '${profile.officialName} · ${profile.creditScoreLabel}'
            : profile.kycLabel,
        valueColor: profile.officialName.isNotEmpty
            ? AppColors.blue
            : profile.kycValueColor,
        onTap: () => context.push(AppRoutes.profileIdentity),
      ),
    ];

    // ── Settings rows ──────────────────────────────────────────────
    final settingsRows = <ProfileSettingsRow>[
      if (profile.canShowMomoQr)
        ProfileSettingsRow(
          icon: Icons.qr_code_rounded,
          label: l10n.profileMomoQrTitle,
          value: l10n.openAction,
          valueColor: AppColors.accent,
          onTap: () => _showMomoQrSheet(profile),
        ),
      if (adminAccess.hasAnyAdminAccess)
        ProfileSettingsRow(
          icon: Icons.admin_panel_settings_outlined,
          iconColor: AppColors.purple,
          label: l10n.profileAdminPanel,
          value: l10n.openAction,
          valueColor: AppColors.purple,
          onTap: () => context.push(AppRoutes.admin),
        ),
      ProfileSettingsRow(
        icon: Icons.brightness_6_outlined,
        label: 'Theme',
        value: switch (themePreference) {
          AppThemePreference.system => 'System',
          AppThemePreference.light => 'Light',
          AppThemePreference.dark => 'Dark',
        },
        onTap: _showThemeSheet,
      ),
      ProfileSettingsRow(
        icon: Icons.help_outline_rounded,
        label: l10n.supportLabel,
        value: l10n.whatsapp,
        onTap: _openSupportWhatsApp,
      ),
      ProfileSettingsRow(
        icon: Icons.security_outlined,
        label: l10n.profileAppAccess,
        value: l10n.profileManageAction,
        onTap: _showAppAccessSheet,
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CoolScreenBackground(
        child: SafeArea(
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  18,
                  18,
                  18,
                  profileBottomPadding,
                ),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    Text(
                      l10n.navProfile,
                      style: GoogleFonts.dmSans(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 18),
                    ProfileHeader(profile: profile),
                    // ── Completion progress ─────────────────────
                    if (profile.showCompletionBanner) ...[
                      const SizedBox(height: 10),
                      _ProfileCompletionBar(profile: profile),
                    ],
                    const SizedBox(height: 14),
                    ProfileSettingsSection(
                      title: 'Account',
                      rows: accountRows,
                    ),
                    const SizedBox(height: 14),
                    ProfileSettingsSection(
                      title: 'Settings',
                      rows: settingsRows,
                    ),
                    const SizedBox(height: 14),
                    ProfileDangerZone(
                      onDeleteAccount: _confirmDeleteAccount,
                      onSignOut: _confirmSignOut,
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: Text(
                        'Cool v1.0.0',
                        style: GoogleFonts.dmSans(
                          fontSize: 11,
                          color: AppColors.text3,
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows profile completion progress when setup is incomplete.
class _ProfileCompletionBar extends StatelessWidget {
  const _ProfileCompletionBar({required this.profile});
  final ProfileData profile;

  @override
  Widget build(BuildContext context) {
    final fraction = profile.completionFraction;
    final done = profile.setupItems.where((i) => i.isComplete).length;
    final total = profile.setupItems.length;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.checklist_rounded, size: 16, color: AppColors.accent),
              const SizedBox(width: 8),
              Text(
                'Profile Setup',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              const Spacer(),
              Text(
                '$done / $total',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: AppColors.surface2,
              valueColor: const AlwaysStoppedAnimation(AppColors.accent),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: profile.setupItems.map((item) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    item.isComplete
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked,
                    size: 14,
                    color: item.isComplete ? AppColors.accent : AppColors.text3,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    item.label,
                    style: GoogleFonts.dmSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: item.isComplete ? AppColors.text2 : AppColors.text3,
                      decoration:
                          item.isComplete ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
