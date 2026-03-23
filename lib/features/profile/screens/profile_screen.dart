import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config_provider.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/status/providers/cool_status_provider.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/theme_preference.dart';
import '../../../core/theme/theme_preference_provider.dart';
import '../../../shared/widgets/cool_bottom_sheet.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_scaffold.dart';
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
    await showCoolBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (_) => ProfileMomoQrCard(
        momoNumber: profile.momoNumber,
        countryCode: profile.countryCode,
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
    final colors = context.coolSemanticColors;
    final l10n = context.l10n;
    final themePreference = ref.watch(themePreferenceProvider);
    final profile = ref.watch(profileViewProvider);
    final status = ref.watch(coolStatusProvider).valueOrNull;
    final adminAccess = ref.watch(adminWorkspaceAccessProvider);

    // ── Account rows ───────────────────────────────────────────────
    final accountRows = <ProfileSettingsRow>[
      ProfileSettingsRow(
        icon: Icons.account_balance_wallet_outlined,
        label: 'Wallet',
        value: profile.momoLinked ? profile.momoDisplayLabel : 'Link wallet',
        valueColor: profile.momoLinked ? colors.accent : colors.tertiaryText,
        onTap: () => context.push(AppRoutes.profileWallet),
      ),
      if (status != null)
        ProfileSettingsRow(
          icon: Icons.token_rounded,
          label: 'Cool Tokens',
          value: '${_tierLabel(status.tier)} · ${status.totalPoints} Tokens',
          valueColor: colors.accent,
          onTap: () => context.push(AppRoutes.tokens),
        ),
      ProfileSettingsRow(
        icon: Icons.card_giftcard_rounded,
        label: 'Invite Friends',
        value: 'Share & earn tokens',
        valueColor: colors.accent,
        onTap: () => context.push(AppRoutes.referral),
      ),
      ProfileSettingsRow(
        icon: Icons.swap_horiz_rounded,
        label: 'Mobility',
        value: profile.isDriver ? 'Driver' : 'Passenger',
        valueColor: profile.travelRoleValueColor(colors),
        onTap: () => context.push(AppRoutes.profileTravelRole),
      ),
      ProfileSettingsRow(
        icon: Icons.sms_outlined,
        label: 'MoMo Statements',
        value: profile.mobileMoneyActivityLabel,
        valueColor: profile.momoStatementCount > 0
            ? colors.info
            : colors.tertiaryText,
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
            ? profile.officialName
            : profile.kycLabel,
        valueColor: profile.officialName.isNotEmpty
            ? colors.info
            : profile.kycValueColor(colors),
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
          valueColor: colors.accent,
          onTap: () => _showMomoQrSheet(profile),
        ),
      if (adminAccess.hasAnyAdminAccess)
        ProfileSettingsRow(
          icon: Icons.admin_panel_settings_outlined,
          iconColor: colors.accentStrong,
          label: l10n.profileAdminPanel,
          value: l10n.openAction,
          valueColor: colors.accentStrong,
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

    return CoolScreenScaffold(
      title: l10n.navProfile,
      showBackButton: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProfileHeader(profile: profile),
          if (profile.showCompletionBanner) ...[
            const SizedBox(height: 16),
            _ProfileCompletionBar(profile: profile),
          ],
          const SizedBox(height: 32),
          ProfileSettingsSection(title: 'Account', rows: accountRows),
          const SizedBox(height: 24),
          ProfileSettingsSection(title: 'Settings', rows: settingsRows),
          const SizedBox(height: 24),
          ProfileDangerZone(
            onDeleteAccount: _confirmDeleteAccount,
            onSignOut: _confirmSignOut,
          ),
          const SizedBox(height: 40),
          Center(
            child: Text(
              'COOL v1.1.0',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: context.coolSemanticColors.tertiaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final fraction = profile.completionFraction;
    final done = profile.setupItems.where((i) => i.isComplete).length;
    final total = profile.setupItems.length;

    return CoolCard(
      backgroundColor: colors.analyticsSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.cardSurfaceStrong.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(CoolRadii.sm),
                  border: Border.all(color: colors.border),
                ),
                child: Icon(
                  Icons.checklist_rounded,
                  size: 20,
                  color: colors.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Profile Setup',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: colors.cardSurfaceStrong.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: colors.border),
                ),
                child: Text(
                  '$done / $total',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 10,
              backgroundColor: colors.cardSurfaceStrong,
              valueColor: AlwaysStoppedAnimation(colors.accent),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: profile.setupItems.map((item) {
              final color = item.isComplete
                  ? colors.accent
                  : colors.secondaryText;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    item.isComplete
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked,
                    size: 16,
                    color: color,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    item.label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: item.isComplete
                          ? colors.primaryText
                          : colors.secondaryText,
                      decoration: item.isComplete
                          ? TextDecoration.lineThrough
                          : null,
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
