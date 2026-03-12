import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config_provider.dart';
import '../../../core/config/country_catalog.dart';
import '../../../core/l10n/locale_provider.dart';
import '../../../core/providers/notification_settings_provider.dart';
import '../../../core/providers/supported_countries_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/status/models/cool_status.dart';
import '../../../core/status/providers/cool_status_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_status_card.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../auth/providers/auth_provider.dart';
import '../../credit/providers/credit_provider.dart';
import '../../mobility/providers/driver_provider.dart';
import '../../partners/rayon/models/rs_models.dart' show FanTierX;
import '../widgets/profile_data.dart';
import '../widgets/profile_dialogs.dart';
import '../widgets/profile_header_widgets.dart';
import '../widgets/profile_settings_widgets.dart';

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

  ProfileData _buildProfileData({
    required AuthState authState,
    required Locale locale,
    required NotificationSettingsState notificationSettings,
    required DriverProfileSnapshot driverSnapshot,
    required List<CoolCountry> availableCountries,
    String? creditScoreLabel,
  }) {
    final user = authState.user;
    if (user == null) {
      return ProfileData.empty.copyWith(
        languageCode: locale.languageCode,
        notificationsEnabled: notificationSettings.status.preferenceEnabled,
      );
    }

    final country = CoolCountryCatalog.resolve(
      country: resolveAuthStateCountryCode(authState),
      phone: user.phone,
      providerId: user.momoProvider,
      source: availableCountries,
    );

    final vehicleType = driverSnapshot.vehicleType ?? user.vehicleType;
    final vehicleStatus = driverSnapshot.vehicleStatus;

    return ProfileData(
      name: user.fullName.isNotEmpty ? user.fullName : 'User',
      officialName: user.officialName?.trim().isNotEmpty == true
          ? user.officialName!.trim()
          : (user.fullName.isNotEmpty ? user.fullName : 'Not set'),
      userId: user.id.substring(0, 6),
      phone: user.phone,
      officialPhone: user.officialPhone?.trim().isNotEmpty == true
          ? user.officialPhone!.trim()
          : user.phone,
      momoNumber: user.momoNumber,
      momoCode: user.momoCode,
      countryCode: country.isoCode,
      country: country.displayName,
      momoProvider: country.currencyCode,
      momoLinked: user.momoNumber.isNotEmpty,
      languageCode: locale.languageCode,
      notificationsEnabled: notificationSettings.status.preferenceEnabled,
      creditScoreLabel: creditScoreLabel ?? '--',
      kycStatus: user.kycStatus,
      isDriver: user.isDriver || driverSnapshot.hasProfile,
      vehicleType: vehicleType,
      vehicleStatus: vehicleStatus,
      subscriptionLabel: driverSnapshot.subscriptionLabel,
      subscriptionExpiring: driverSnapshot.subscriptionExpiring,
    );
  }

  // ── Language switcher ─────────────────────────────────────────────────

  Future<void> _showLanguageSheet() async {
    final currentLanguage = ref.read(localeProvider).languageCode;
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => ProfileLanguageSheet(current: currentLanguage),
    );

    if (!mounted || selected == null) return;

    // Persist to Hive and trigger app-wide locale rebuild.
    await ref.read(localeProvider.notifier).setLocale(selected);
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

    context.go('/onboarding');
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
      builder: (_) =>
          const ProfileBlockingProgressDialog(message: 'Deleting your account...'),
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
    final countries =
        ref.read(supportedCountriesProvider).valueOrNull ??
        CoolCountryCatalog.all;
    final country = CoolCountryCatalog.resolve(
      country: profile.countryCode,
      source: countries,
    );
    final result = await showModalBottomSheet<ProfileMomoEditResult>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ProfileMomoEditSheet(
        currentMomoNumber: profile.momoNumber,
        currentMomoCode: profile.momoCode,
        country: country,
        availableCountries: countries,
      ),
    );

    if (result == null || !mounted) return;

    // Show loading overlay while saving (Fix #5)
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const ProfileBlockingProgressDialog(message: 'Saving MoMo info...'),
    );

    final success = await ref
        .read(authProvider.notifier)
        .updateMomoInfo(
          momoNumber: result.momoNumber,
          momoCode: result.momoCode,
          country: result.countryCode,
        );

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // dismiss loading

    if (success) {
      CoolToast.success(context, 'MoMo info updated');
    } else {
      CoolToast.error(context, 'Failed to update MoMo info');
    }
  }

  Future<void> _showMomoQrSheet(ProfileData profile) async {
    await showModalBottomSheet<void>(
      context: context,
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

  Future<void> _showStatusSheet(CoolStatus status) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ProfileSheet(child: CoolStatusCard(status: status)),
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
      CoolToast.error(context, 'Could not open WhatsApp. Please try again.');
    } catch (_) {
      if (!mounted) {
        return;
      }
      CoolToast.error(context, 'Support is unavailable right now.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final locale = ref.watch(localeProvider);
    final notificationSettings = ref.watch(notificationSettingsProvider);
    final countries =
        ref.watch(supportedCountriesProvider).valueOrNull ??
        CoolCountryCatalog.all;
    final creditDashboard = ref.watch(creditDashboardProvider).valueOrNull;
    final driverState = ref.watch(driverProvider);
    final status = ref.watch(coolStatusProvider).valueOrNull;

    final profile = _buildProfileData(
      authState: authState,
      locale: locale,
      notificationSettings: notificationSettings,
      driverSnapshot: DriverProfileSnapshot.fromState(driverState),
      availableCountries: countries,
      creditScoreLabel: creditDashboard?.score?.toString(),
    );
    final moneyRows = <ProfileSettingsRow>[
      ProfileSettingsRow(
        icon: Icons.account_balance_wallet_outlined,
        label: 'Mobile Money',
        value: profile.momoLinked ? profile.momoDisplayLabel : 'Not linked',
        valueColor: profile.momoLinked ? AppColors.accent : AppColors.text3,
        onTap: () => _showMomoEditSheet(profile),
      ),
      ProfileSettingsRow(
        icon: Icons.insights_outlined,
        label: 'Credit score',
        value: profile.creditScoreLabel,
        valueColor: AppColors.blue,
        onTap: () => context.push(AppRoutes.credit),
      ),
    ];
    final preferenceRows = <ProfileSettingsRow>[
      ProfileSettingsRow(
        icon: Icons.translate_outlined,
        label: 'Language',
        value: profile.languageLabel,
        onTap: _showLanguageSheet,
      ),
      ProfileSettingsRow(
        icon: Icons.notifications_outlined,
        label: 'Notifications',
        trailing: ProfileNotificationToggle(
          value: profile.notificationsEnabled,
          isLoading: notificationSettings.isLoading,
          onChanged: _toggleNotifications,
        ),
        showArrow: false,
      ),
      ProfileSettingsRow(
        icon: Icons.help_outline_rounded,
        label: 'Support',
        value: 'WhatsApp',
        onTap: _openSupportWhatsApp,
      ),
    ];
    final moreToolRows = <ProfileSettingsRow>[
      if (profile.momoLinked && profile.momoNumber.isNotEmpty)
        ProfileSettingsRow(
          icon: Icons.qr_code_rounded,
          label: 'MoMo QR code',
          value: 'Open',
          valueColor: AppColors.accent,
          onTap: () => _showMomoQrSheet(profile),
        ),
      ProfileSettingsRow(
        icon: Icons.rule_folder_outlined,
        label: 'Credit readiness',
        value: profile.kycLabel,
        valueColor: AppColors.text2,
        onTap: () => context.push(AppRoutes.creditReadiness),
      ),
    ];
    if (profile.isDriver) {
      moreToolRows.add(
        ProfileSettingsRow(
          icon: Icons.directions_car_outlined,
          label: 'Driver tools',
          value:
              '${profile.vehicleType ?? 'Vehicle'} · ${profile.subscriptionLabel ?? 'Open'}',
          onTap: () => context.push(AppRoutes.mobilityDriver),
        ),
      );
    }
    if (status != null) {
      moreToolRows.add(
        ProfileSettingsRow(
          icon: Icons.stars_rounded,
          label: 'COOL status',
          value: '${status.tier.label} · ${status.totalPoints} pts',
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
          label: 'Admin panel',
          value: 'Open',
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
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 96),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    Text(
                      'Profile',
                      style: GoogleFonts.dmSans(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (authState.user != null &&
                        authState.user!.isProfileComplete != true) ...[
                      ProfileCompleteProfileBanner(phone: authState.user!.phone),
                      const SizedBox(height: 18),
                    ],
                    ProfileHeader(profile: profile),
                    const SizedBox(height: 18),
                    ProfileFactsCard(
                      items: [
                        ProfileFactItem(
                          label: 'Official name',
                          value: profile.officialName,
                        ),
                        ProfileFactItem(
                          label: 'Phone',
                          value: profile.phone,
                        ),
                        ProfileFactItem(
                          label: 'Identity',
                          value: profile.kycLabel,
                          valueColor: profile.kycValueColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ProfileSettingsSection(title: 'Money', rows: moneyRows),
                    const SizedBox(height: 14),
                    ProfileSettingsSection(
                      title: 'Preferences',
                      rows: preferenceRows,
                    ),
                    if (moreToolRows.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      ProfileSectionToggleCard(
                        title: 'More tools',
                        subtitle: _showMoreTools
                            ? 'Hide QR, driver, status, and admin shortcuts.'
                            : 'Show extra actions and secondary shortcuts.',
                        isExpanded: _showMoreTools,
                        onTap: () {
                          setState(() {
                            _showMoreTools = !_showMoreTools;
                          });
                        },
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _showMoreTools
                            ? Padding(
                                key: const ValueKey('profile-more-tools'),
                                padding: const EdgeInsets.only(top: 14),
                                child: ProfileSettingsSection(
                                  title: 'More tools',
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
