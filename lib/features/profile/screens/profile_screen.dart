import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config_provider.dart';
import '../../../core/config/app_market.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/providers/notification_settings_provider.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/status/models/cool_status.dart';
import '../../../core/status/providers/cool_status_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_status_card.dart';
import '../../../shared/widgets/cool_toast.dart';
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
import '../widgets/profile_travel_role_sheet.dart';

/// User profile and settings hub.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late final ProviderSubscription<AuthState> _authSubscription;
  bool _didRequestDriverProfile = false;
  bool _showMoreTools = false;

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

  // ── Notifications toggle ──────────────────────────────────────────────

  Future<void> _toggleNotifications(bool value) async {
    await ref.read(notificationSettingsProvider.notifier).setEnabled(value);
    if (!mounted) {
      return;
    }

    final error = ref.read(notificationSettingsProvider).error;
    if (error != null && error.isNotEmpty) {
      CoolToast.error(context, error);
    }
  }

  // ── MoMo edit sheet ───────────────────────────────────────────────────

  Future<void> _showMomoEditSheet(ProfileData profile) async {
    final country = AppMarket.country;
    final result = await showModalBottomSheet<ProfileMomoEditResult>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ProfileMomoEditSheet(
        currentMomoNumber: profile.momoNumber,
        currentMomoCode: profile.momoCode,
        currentMomoRouteType: profile.effectiveMomoRouteType,
        country: country,
      ),
    );

    if (result == null || !mounted) return;

    // Show loading overlay while saving (Fix #5)
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProfileBlockingProgressDialog(
        message: context.l10n.profileSavingMomoInfo,
      ),
    );

    final success = await ref
        .read(authProvider.notifier)
        .updateMomoInfo(
          momoNumber: result.momoNumber,
          momoCode: result.momoCode,
          momoRouteType: result.momoRouteType,
          country: result.countryCode,
        );

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // dismiss loading

    if (success) {
      CoolToast.success(context, context.l10n.profileMomoUpdated);
    } else {
      CoolToast.error(context, context.l10n.profileMomoUpdateFailed);
    }
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

  Future<void> _showOfficialIdentitySheet(ProfileData profile) async {
    final user = ref.read(authProvider).user;
    if (user == null) {
      return;
    }

    final country = AppMarket.country;

    final result =
        await showModalBottomSheet<ProfileOfficialIdentityEditResult>(
          context: context,
          useRootNavigator: true,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (_) => ProfileOfficialIdentityEditSheet(
            currentOfficialName: profile.officialName,
            currentOfficialPhone: profile.officialPhone,
            country: country,
            kycLabel: profile.kycLabel,
            kycValueColor: profile.kycValueColor,
            kycVerifiedAt: user.kycVerifiedAt,
          ),
        );

    if (result == null || !mounted) {
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProfileBlockingProgressDialog(
        message: context.l10n.profileSavingIdentity,
      ),
    );

    final success = await ref
        .read(authProvider.notifier)
        .updateOfficialIdentity(
          officialName: result.officialName,
          officialPhone: result.officialPhone,
        );

    if (!mounted) {
      return;
    }
    Navigator.of(context, rootNavigator: true).pop();

    if (success) {
      CoolToast.success(context, context.l10n.profileIdentityUpdated);
    } else {
      CoolToast.error(context, context.l10n.profileIdentityUpdateFailed);
    }
  }

  Future<void> _showStatusSheet(CoolStatus status) async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ProfileSheet(child: CoolStatusCard(status: status)),
    );
  }

  Future<void> _showTravelRoleSheet(ProfileData profile) async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => ProfileSheet(
        child: ProfileTravelRoleSheet(
          profile: profile,
          onOpenPassengerTools: profile.momoLinked
              ? null
              : () {
                  Navigator.of(sheetContext).pop();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) {
                      return;
                    }
                    unawaited(_showMomoEditSheet(profile));
                  });
                },
          onOpenDriverSetup: () {
            Navigator.of(sheetContext).pop();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) {
                return;
              }
              context.push(AppRoutes.mobilityDriver);
            });
          },
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
    final authState = ref.watch(authProvider);
    final notificationSettings = ref.watch(notificationSettingsProvider);
    final profile = ref.watch(profileViewProvider);
    final status = ref.watch(coolStatusProvider).valueOrNull;
    const profileBottomPadding = 140.0;
    final moneyRows = <ProfileSettingsRow>[
      ProfileSettingsRow(
        icon: Icons.account_balance_wallet_outlined,
        label: l10n.profileMobileMoney,
        value: profile.momoLinked
            ? profile.momoDisplayLabel
            : l10n.profileNotLinked,
        valueColor: profile.momoLinked ? AppColors.accent : AppColors.text3,
        onTap: () => _showMomoEditSheet(profile),
      ),
      ProfileSettingsRow(
        icon: Icons.insights_outlined,
        label: l10n.profileCreditScore,
        value: profile.creditScoreLabel,
        valueColor: AppColors.blue,
        onTap: () => context.push(AppRoutes.credit),
      ),
    ];
    final supportAndAccessRows = <ProfileSettingsRow>[
      ProfileSettingsRow(
        icon: Icons.help_outline_rounded,
        label: l10n.supportLabel,
        value: l10n.whatsapp,
        onTap: _openSupportWhatsApp,
      ),
      ProfileSettingsRow(
        icon: Icons.admin_panel_settings_outlined,
        label: l10n.profileAppAccess,
        value: l10n.profileManageAction,
        onTap: _showAppAccessSheet,
      ),
    ];
    final preferenceRows = <ProfileSettingsRow>[
      ProfileSettingsRow(
        icon: Icons.notifications_outlined,
        label: l10n.notificationsLabel,
        trailing: ProfileNotificationToggle(
          value: profile.notificationsEnabled,
          isLoading: notificationSettings.isLoading,
          onChanged: _toggleNotifications,
        ),
        showArrow: false,
      ),
    ];
    final moreToolRows = <ProfileSettingsRow>[
      if (profile.canShowMomoQr)
        ProfileSettingsRow(
          icon: Icons.qr_code_rounded,
          label: l10n.profileMomoQrTitle,
          value: l10n.openAction,
          valueColor: AppColors.accent,
          onTap: () => _showMomoQrSheet(profile),
        ),
      ProfileSettingsRow(
        icon: Icons.rule_folder_outlined,
        label: l10n.profileCreditReadiness,
        value: profile.kycLabel,
        valueColor: AppColors.text2,
        onTap: () => context.push(AppRoutes.creditReadiness),
      ),
    ];
    if (profile.isDriver) {
      moreToolRows.add(
        ProfileSettingsRow(
          icon: Icons.directions_car_outlined,
          label: l10n.profileDriverTools,
          value: profile.driverSummary,
          onTap: () => context.push(AppRoutes.mobilityDriver),
        ),
      );
    }
    if (status != null) {
      moreToolRows.add(
        ProfileSettingsRow(
          icon: Icons.stars_rounded,
          label: l10n.profileCoolStatus,
          value: l10n.profileCoolStatusValue(
            _tierLabel(status.tier),
            status.totalPoints,
          ),
          valueColor: AppColors.accent,
          onTap: () => _showStatusSheet(status),
        ),
      );
    }
    if (authState.user?.isAdmin == true) {
      moreToolRows.add(
        ProfileSettingsRow(
          icon: Icons.admin_panel_settings_outlined,
          iconColor: AppColors.purple,
          label: l10n.profileAdminPanel,
          value: l10n.openAction,
          valueColor: AppColors.purple,
          onTap: () => context.push(AppRoutes.admin),
        ),
      );
    }

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
                    if (authState.user != null &&
                        profile.showCompletionBanner) ...[
                      ProfileCompleteProfileBanner(
                        phone: authState.user!.phone,
                      ),
                      const SizedBox(height: 18),
                    ],
                    ProfileHeader(profile: profile),
                    const SizedBox(height: 18),
                    
                    ProfileSettingsSection(
                      title: l10n.account,
                      rows: [
                        ...profile.setupItems.map((item) {
                          final onTap = switch (item.id) {
                            'account' => () => context.push(
                              AppRoutes.registerLocation(
                                phone: authState.user?.phone,
                              ),
                            ),
                            'wallet' => () => _showMomoEditSheet(profile),
                            'official_identity' =>
                              () => _showOfficialIdentitySheet(profile),
                            'travel_role' => () => _showTravelRoleSheet(
                              profile,
                            ),
                            _ => null,
                          };

                          return ProfileSettingsRow(
                            icon: switch (item.id) {
                              'wallet' =>
                                Icons.account_balance_wallet_outlined,
                              'official_identity' =>
                                Icons.verified_user_outlined,
                              'travel_role' => Icons.swap_horiz_rounded,
                              _ => Icons.badge_outlined,
                            },
                            label: item.label,
                            onTap: onTap,
                            showArrow: onTap != null,
                          );
                        }),
                        ...moneyRows,
                      ],
                    ),
                    const SizedBox(height: 14),
                    ProfileSettingsSection(
                      title: l10n.preferencesSectionTitle,
                      rows: preferenceRows,
                    ),
                    const SizedBox(height: 14),
                    ProfileSettingsSection(
                      title: l10n.supportLabel,
                      rows: supportAndAccessRows,
                    ),
                    if (moreToolRows.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      ProfileSectionToggleCard(
                        title: l10n.moreToolsSectionTitle,
                        subtitle: _showMoreTools
                            ? l10n.profileMoreToolsHideSubtitle
                            : l10n.profileMoreToolsShowSubtitle,
                        isExpanded: _showMoreTools,
                        onTap: () {
                          setState(() {
                            _showMoreTools = !_showMoreTools;
                          });
                        },
                      ),
                      AnimatedSwitcher(
                        duration:
                            MediaQuery.maybeOf(context)?.disableAnimations ??
                                false
                            ? Duration.zero
                            : const Duration(milliseconds: 200),
                        child: _showMoreTools
                            ? Padding(
                                key: const ValueKey('profile-more-tools'),
                                padding: const EdgeInsets.only(top: 14),
                                child: ProfileSettingsSection(
                                  title: l10n.moreToolsSectionTitle,
                                  rows: moreToolRows,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                    const SizedBox(height: 14),
                    ProfileDangerZone(
                      onDeleteAccount: _confirmDeleteAccount,
                      onSignOut: _confirmSignOut,
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
