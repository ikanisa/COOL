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
import '../../../core/theme/cool_layout.dart';
import '../../../core/theme/cool_palette.dart';
import '../../../core/theme/theme_preference.dart';
import '../../../core/theme/theme_preference_provider.dart';
import '../../../core/providers/supabase_client_provider.dart';
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
          value: '${_tierLabel(status.tier)} · ${status.totalPoints} Tokens',
          valueColor: AppColors.accent,
          onTap: () => context.push(AppRoutes.tokens),
        ),
      ProfileSettingsRow(
        icon: Icons.card_giftcard_rounded,
        label: 'Invite Friends',
        value: 'Earn 150 tokens',
        valueColor: AppColors.accent,
        onTap: () => context.push(AppRoutes.referral),
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
      backgroundColor: context.coolPalette.bg,
      body: CoolScreenBackground(
        child: SafeArea(
          bottom: false,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: CoolLayout.rootPagePadding,
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    Text(
                      l10n.navProfile,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.displayLarge,
                    ),
                    const SizedBox(height: 24),
                    ProfileHeader(profile: profile),
                    // ── Completion progress ─────────────────────
                    if (profile.showCompletionBanner) ...[
                      const SizedBox(height: 16),
                      _ProfileCompletionBar(profile: profile),
                    ],
                    const SizedBox(height: 32),
                    ProfileSettingsSection(
                      title: 'Account',
                      rows: accountRows,
                    ),
                    const SizedBox(height: 24),
                    ProfileSettingsSection(
                      title: 'Settings',
                      rows: settingsRows,
                    ),
                    const SizedBox(height: 24),
                    _WealthArchiveCard(),
                    const SizedBox(height: 24),
                    ProfileDangerZone(
                      onDeleteAccount: _confirmDeleteAccount,
                      onSignOut: _confirmSignOut,
                    ),
                    const SizedBox(height: 40),
                    Center(
                      child: Opacity(
                        opacity: 0.5,
                        child: Text(
                          'COOL v1.0.0',
                          style: Theme.of(context).textTheme.labelSmall,
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

class _WealthArchiveCard extends StatefulWidget {
  @override
  State<_WealthArchiveCard> createState() => _WealthArchiveCardState();
}

class _WealthArchiveCardState extends State<_WealthArchiveCard> {
  bool _isArchiving = false;

  Future<void> _archiveWealth(WidgetRef ref) async {
    setState(() => _isArchiving = true);
    
    try {
      final client = ref.read(supabaseClientProvider);
      final response = await client.functions.invoke('run-monthly-archive');
      
      if (response.data != null && response.data['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Wealth Archive saved to Google Drive & emailed!'),
              action: SnackBarAction(
                label: 'VIEW',
                onPressed: () {
                  // doc_url logic
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to complete archive.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isArchiving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                child: const Icon(Icons.auto_awesome_rounded, size: 16, color: Colors.black),
              ),
              const SizedBox(width: 12),
              Text(
                'Smart Reports',
                style: GoogleFonts.dmSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: palette.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Compile your monthly progress into a formal report, archive it to Google Drive, and receive a summary via Gmail.',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: palette.text2,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          Consumer(
            builder: (context, ref, _) => Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _isArchiving ? null : () => _archiveWealth(ref),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: palette.bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: palette.border),
                  ),
                  alignment: Alignment.center,
                  child: _isArchiving 
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
                    : Text(
                        'Archive Current Month',
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accent,
                        ),
                      ),
                ),
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
    final palette = context.coolPalette;
    final fraction = profile.completionFraction;
    final done = profile.setupItems.where((i) => i.isComplete).length;
    final total = profile.setupItems.length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.accent.withValues(alpha: 0.15), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.checklist_rounded, size: 18, color: palette.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Profile Setup',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontSize: 16,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '$done / $total',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: palette.accent,
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
              minHeight: 8,
              backgroundColor: palette.surface2,
              valueColor: AlwaysStoppedAnimation(palette.accent),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: profile.setupItems.map((item) {
              final color = item.isComplete ? palette.accent : palette.text3;
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
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontSize: 12,
                      color: item.isComplete ? palette.text : palette.text3,
                      decoration: item.isComplete ? TextDecoration.lineThrough : null,
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
