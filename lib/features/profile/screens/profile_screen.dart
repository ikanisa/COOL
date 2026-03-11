import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config_provider.dart';
import '../../../core/config/country_catalog.dart';
import '../../../core/l10n/locale_provider.dart';
import '../../../core/providers/notification_settings_provider.dart';
import '../../../core/providers/supported_countries_provider.dart';

import '../../../core/status/providers/cool_status_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/phone_validator.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_status_card.dart';
import '../../auth/providers/auth_provider.dart';
import '../../credit/providers/credit_provider.dart';
import '../../mobility/models/subscription_status.dart';
import '../../mobility/providers/driver_provider.dart';
import '../../../core/router/app_router.dart';

/// User profile and settings hub.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late final ProviderSubscription<AuthState> _authSubscription;
  bool _didRequestDriverProfile = false;

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

  _ProfileData _buildProfileData({
    required AuthState authState,
    required Locale locale,
    required NotificationSettingsState notificationSettings,
    required _DriverProfileSnapshot driverSnapshot,
    required List<CoolCountry> availableCountries,
    String? creditScoreLabel,
  }) {
    final user = authState.user;
    if (user == null) {
      return _ProfileData.empty.copyWith(
        languageCode: locale.languageCode,
        notificationsEnabled: notificationSettings.status.preferenceEnabled,
      );
    }

    final country = CoolCountryCatalog.resolve(
      country: user.country,
      phone: user.phone,
      providerId: user.momoProvider,
      source: availableCountries,
    );

    final vehicleType = driverSnapshot.vehicleType ?? user.vehicleType;
    final vehicleStatus = driverSnapshot.vehicleStatus;

    return _ProfileData(
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
      countryCode: user.country,
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
      builder: (_) => _LanguageSheet(current: currentLanguage),
    );

    if (!mounted || selected == null) return;

    // Persist to Hive and trigger app-wide locale rebuild.
    await ref.read(localeProvider.notifier).setLocale(selected);
  }

  // ── Sign out ──────────────────────────────────────────────────────────

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _SignOutDialog(),
    );

    if (confirmed != true || !mounted) return;

    await ref.read(authProvider.notifier).signOut();
    if (!mounted) {
      return;
    }

    final error = ref.read(authProvider).error;
    if (error != null && error.isNotEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
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
      builder: (_) => const _DeleteAccountDialog(),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const _BlockingProgressDialog(message: 'Deleting your account...'),
    );

    await ref.read(authProvider.notifier).deleteAccount();
    if (!mounted) {
      return;
    }

    Navigator.of(context, rootNavigator: true).pop();

    final error = ref.read(authProvider).error;
    if (error != null && error.isNotEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    // Invalidate cached providers before leaving.
    ref.invalidate(coolStatusProvider);
    ref.invalidate(driverProvider);
    ref.invalidate(creditDashboardProvider);

    context.go(AppRoutes.onboarding);
  }

  // ── COOL Status card ───────────────────────────────────────────────

  Widget _buildCoolStatusCard() {
    final statusAsync = ref.watch(coolStatusProvider);
    return statusAsync.when(
      data: (status) => CoolStatusCard(status: status),
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  // ── Notifications toggle ──────────────────────────────────────────────

  Future<void> _toggleNotifications(bool value) async {
    await ref.read(notificationSettingsProvider.notifier).setEnabled(value);
    if (!mounted) {
      return;
    }

    final error = ref.read(notificationSettingsProvider).error;
    if (error != null && error.isNotEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  // ── MoMo edit sheet ───────────────────────────────────────────────────

  Future<void> _showMomoEditSheet(_ProfileData profile) async {
    final countries =
        ref.read(supportedCountriesProvider).valueOrNull ??
        CoolCountryCatalog.all;
    final country = CoolCountryCatalog.resolve(
      country: profile.countryCode,
      source: countries,
    );
    final result = await showModalBottomSheet<_MomoEditResult>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _MomoEditSheet(
        currentMomoNumber: profile.momoNumber,
        currentMomoCode: profile.momoCode,
        country: country,
      ),
    );

    if (result == null || !mounted) return;

    // Show loading overlay while saving (Fix #5)
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const _BlockingProgressDialog(message: 'Saving MoMo info...'),
    );

    final success = await ref
        .read(authProvider.notifier)
        .updateMomoInfo(
          momoNumber: country.buildE164Phone(result.momoNumber),
          momoCode:
              !country.supportsMomoCode ||
                  (result.momoCode?.trim().isEmpty ?? true)
              ? null
              : country.normalizeMerchantCode(result.momoCode!),
        );

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // dismiss loading

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? 'MoMo info updated ✅' : 'Failed to update MoMo info',
        ),
      ),
    );
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

    final profile = _buildProfileData(
      authState: authState,
      locale: locale,
      notificationSettings: notificationSettings,
      driverSnapshot: _DriverProfileSnapshot.fromState(driverState),
      availableCountries: countries,
      creditScoreLabel: creditDashboard?.score?.toString(),
    );

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
                    if (authState.user != null &&
                        authState.user!.isProfileComplete != true) ...[
                      _CompleteProfileBanner(phone: authState.user!.phone),
                      const SizedBox(height: 14),
                    ],
                    _ProfileHeader(profile: profile),
                    const SizedBox(height: 14),
                    _buildCoolStatusCard(),
                    const SizedBox(height: 14),
                    if (profile.momoLinked && profile.momoNumber.isNotEmpty)
                      _MomoQrCard(
                        momoNumber: profile.momoNumber,
                        countryCode: profile.countryCode,
                      ),
                    const SizedBox(height: 14),
                    _SettingsSection(
                      title: 'Account',
                      rows: [
                        _SettingsRow(
                          emoji: '📱',
                          label: 'Phone',
                          value: profile.phone,
                        ),
                        _SettingsRow(
                          emoji: '🪪',
                          label: 'Official Name',
                          value: profile.officialName,
                        ),
                        _SettingsRow(
                          emoji: '💳',
                          label: 'MOMO Number',
                          value: profile.momoLinked
                              ? '${profile.momoDisplayLabel} ✅'
                              : 'Not linked',
                          valueColor: profile.momoLinked
                              ? AppColors.accent
                              : AppColors.text3,
                          onTap: () => _showMomoEditSheet(profile),
                        ),
                        _SettingsRow(
                          emoji: '🌐',
                          label: 'Language',
                          value: profile.languageLabel,
                          onTap: _showLanguageSheet,
                        ),
                        _SettingsRow(
                          emoji: '✅',
                          label: 'KYC Status',
                          value: profile.kycLabel,
                          valueColor: profile.kycValueColor,
                        ),
                        _SettingsRow(
                          emoji: '🔔',
                          label: 'Notifications',
                          trailing: _NotificationToggle(
                            value: profile.notificationsEnabled,
                            isLoading: notificationSettings.isLoading,
                            onChanged: _toggleNotifications,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (profile.isDriver) ...[
                      _SettingsSection(
                        title: 'Driver Profile',
                        rows: [
                          _SettingsRow(
                            emoji: '🛺',
                            label: 'Vehicle',
                            value:
                                '${profile.vehicleType ?? 'Not set'} · ${profile.vehicleStatus ?? 'Setup needed'}',
                            onTap: () => context.push('/mobility/driver'),
                          ),
                          _SettingsRow(
                            emoji: '📋',
                            label: 'Subscription',
                            value:
                                profile.subscriptionLabel ?? 'No active plan',
                            valueColor: profile.subscriptionExpiring
                                ? AppColors.orange
                                : AppColors.accent,
                            onTap: () => context.push('/mobility/driver'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                    ],
                    _SettingsSection(
                      title: 'Security',
                      rows: [
                        _SettingsRow(
                          emoji: '💬',
                          label: 'WhatsApp OTP',
                          value: 'Active',
                          valueColor: AppColors.accent,
                        ),

                      ],
                    ),
                    const SizedBox(height: 14),
                    _SettingsSection(
                      title: 'More',
                      rows: [
                        if (authState.user?.isAdmin == true)
                          _SettingsRow(
                            emoji: '🛡️',
                            label: 'Admin Panel',
                            value: 'Manage content',
                            valueColor: AppColors.purple,
                            onTap: () => context.push(AppRoutes.admin),
                          ),
                        _SettingsRow(
                          emoji: '📊',
                          label: 'Credit Score',
                          value: profile.creditScoreLabel,
                          valueColor: AppColors.purple,
                          onTap: () => context.push('/credit'),
                        ),
                        _SettingsRow(
                          emoji: '❓',
                          label: 'Help & Support',
                          onTap: () async {
                            try {
                              final number = await ref.read(
                                supportWhatsAppProvider.future,
                              );
                              final uri = Uri.parse('https://wa.me/$number');
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(
                                  uri,
                                  mode: LaunchMode.externalApplication,
                                );
                              } else {
                                if (!mounted) {
                                  return;
                                }
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Could not open WhatsApp. Please try again.',
                                    ),
                                  ),
                                );
                              }
                            } catch (_) {
                              if (!mounted) {
                                return;
                              }
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Support is unavailable right now.',
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                        _SettingsRow(
                          emoji: '🗑️',
                          label: 'Delete Account',
                          value: 'Permanent',
                          valueColor: AppColors.red,
                          labelColor: AppColors.red,
                          onTap: _confirmDeleteAccount,
                          showArrow: false,
                        ),
                        _SettingsRow(
                          emoji: '🚪',
                          label: 'Sign Out',
                          valueColor: AppColors.red,
                          labelColor: AppColors.red,
                          onTap: _confirmSignOut,
                          showArrow: false,
                        ),
                      ],
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

// ═════════════════════════════════════════════════════════════════════════════
// PROFILE HEADER
// ═════════════════════════════════════════════════════════════════════════════

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile});

  final _ProfileData profile;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Avatar with edit overlay
        Stack(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: AppColors.accentGradient,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                profile.initials,
                style: GoogleFonts.dmSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.surface,
                ),
              ),
            ),
            // Avatar edit is disabled until image upload is implemented.
          ],
        ),
        const SizedBox(height: 14),

        // Name
        Text(
          profile.name,
          style: GoogleFonts.dmSans(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 4),

        // ID
        Text(
          'ID: ${profile.userId}',
          style: GoogleFonts.dmMono(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.accent,
          ),
        ),
        const SizedBox(height: 4),

        // Country + provider
        Text(
          '${profile.country} · ${profile.momoProvider}',
          style: GoogleFonts.dmSans(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: AppColors.text2,
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// MOMO QR CARD
// ═════════════════════════════════════════════════════════════════════════════

class _MomoQrCard extends StatelessWidget {
  const _MomoQrCard({required this.momoNumber, required this.countryCode});

  final String momoNumber;
  final String countryCode;

  @override
  Widget build(BuildContext context) {
    final country =
        CoolCountryCatalog.byIsoCode(countryCode) ??
        CoolCountryCatalog.defaultCountry;
    final qrData = PhoneValidator.generateMomoQrData(momoNumber, country);
    final displayNumber = countryCode.toUpperCase() == 'RW'
        ? PhoneValidator.formatRwandanDisplay(momoNumber)
        : momoNumber;
    final providerLabel = PhoneValidator.providerLabel(momoNumber, countryCode);

    return CoolCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            Text(
              '📲 MOMO Pay QR',
              style: GoogleFonts.dmSans(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.all(10),
              child: QrImageView(
                data: qrData,
                size: 100,
                backgroundColor: Colors.transparent,
                eyeStyle: const QrEyeStyle(
                  color: Colors.black,
                  eyeShape: QrEyeShape.square,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  color: Colors.black,
                  dataModuleShape: QrDataModuleShape.square,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              displayNumber,
              style: GoogleFonts.dmMono(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
              ),
            ),
            if (providerLabel != null) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accentGlow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  providerLabel,
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              'Scan to pay me',
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.text3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// SETTINGS SECTION
// ═════════════════════════════════════════════════════════════════════════════

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.rows});

  final String title;
  final List<_SettingsRow> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            title.toUpperCase(),
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.text3,
              letterSpacing: 1.2,
            ),
          ),
        ),
        CoolCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                rows[i],
                if (i < rows.length - 1)
                  const Divider(color: AppColors.border, height: 1, indent: 48),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// SETTINGS ROW
// ═════════════════════════════════════════════════════════════════════════════

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.emoji,
    required this.label,
    this.value,
    this.valueColor = AppColors.text2,
    this.labelColor = AppColors.text,
    this.onTap,
    this.trailing,
    this.showArrow = true,
  });

  final String emoji;
  final String label;
  final String? value;
  final Color valueColor;
  final Color labelColor;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool showArrow;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: labelColor,
              ),
            ),
          ),
          if (trailing != null)
            trailing!
          else if (value != null) ...[
            Flexible(
              child: Text(
                value!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: valueColor,
                ),
              ),
            ),
          ],
          if (onTap != null && showArrow) ...[
            const SizedBox(width: 6),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: AppColors.text3,
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return content;

    return InkWell(
      onTap: onTap,
      splashColor: AppColors.accentGlow,
      highlightColor: Colors.transparent,
      child: content,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// NOTIFICATION TOGGLE
// ═════════════════════════════════════════════════════════════════════════════

class _NotificationToggle extends StatelessWidget {
  const _NotificationToggle({
    required this.value,
    required this.onChanged,
    this.isLoading = false,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Notifications',
      toggled: value,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLoading) ...[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
          ],
          Switch.adaptive(
            value: value,
            onChanged: isLoading ? null : onChanged,
            activeTrackColor: AppColors.accent,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

class _CompleteProfileBanner extends StatelessWidget {
  const _CompleteProfileBanner({required this.phone});

  final String phone;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(AppRoutes.registerLocation(phone: phone)),
      child: CoolCard(
        gradient: AppColors.cardGradient,
        borderColor: const Color(0xFFFFD700).withValues(alpha: 0.45),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Text('✏️', style: TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Complete your profile',
                      style: GoogleFonts.barlow(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Add your name and payment info to unlock all features.',
                      style: GoogleFonts.barlow(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text2,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: AppColors.text3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// LANGUAGE BOTTOM SHEET
// ═════════════════════════════════════════════════════════════════════════════

class _LanguageSheet extends ConsumerWidget {
  const _LanguageSheet({required this.current});

  final String current;

  static const _fallbackLanguages = [
    _LanguageOption('en', '🇬🇧', 'English'),
    _LanguageOption('fr', '🇫🇷', 'Français'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final langAsync = ref.watch(supportedLanguagesProvider);

    final languages = langAsync.when(
      data: (langs) => langs.isEmpty
          ? _fallbackLanguages
          : langs
                .map(
                  (l) => _LanguageOption(
                    l['code'] ?? 'en',
                    l['flag'] ?? '🏳️',
                    l['name'] ?? '',
                  ),
                )
                .toList(),
      loading: () => _fallbackLanguages,
      error: (_, _) => _fallbackLanguages,
    );

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border2,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              Text(
                'Language',
                style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 18),

              for (final lang in languages) ...[
                _buildLanguageTile(context, lang),
                if (lang != languages.last)
                  const Divider(color: AppColors.border, height: 1),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageTile(BuildContext context, _LanguageOption lang) {
    final isSelected = current == lang.code;

    return InkWell(
      onTap: () => Navigator.of(context).pop(lang.code),
      borderRadius: BorderRadius.circular(12),
      splashColor: AppColors.accentGlow,
      highlightColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Row(
          children: [
            Text(lang.flag, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                lang.label,
                style: GoogleFonts.dmSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? AppColors.accent : AppColors.text,
                ),
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle_rounded,
                size: 22,
                color: AppColors.accent,
              ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// SIGN OUT DIALOG
// ═════════════════════════════════════════════════════════════════════════════

class _SignOutDialog extends StatelessWidget {
  const _SignOutDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.border),
      ),
      title: Text(
        'Sign Out',
        style: GoogleFonts.dmSans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.text,
        ),
      ),
      content: Text(
        'Are you sure you want to sign out? You will need to verify your WhatsApp OTP again to log back in.',
        style: GoogleFonts.dmSans(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.text2,
          height: 1.5,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            'Cancel',
            style: GoogleFonts.dmSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.text2,
            ),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            'Sign Out',
            style: GoogleFonts.dmSans(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.red,
            ),
          ),
        ),
      ],
    );
  }
}

class _DeleteAccountDialog extends StatelessWidget {
  const _DeleteAccountDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        'Delete account?',
        style: GoogleFonts.dmSans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.text,
        ),
      ),
      content: Text(
        'This permanently removes your Cool account and associated app data. '
        'This action cannot be undone.',
        style: GoogleFonts.dmSans(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppColors.text2,
          height: 1.45,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(
            'Cancel',
            style: GoogleFonts.dmSans(
              fontWeight: FontWeight.w700,
              color: AppColors.text2,
            ),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            'Delete',
            style: GoogleFonts.dmSans(
              fontWeight: FontWeight.w800,
              color: AppColors.red,
            ),
          ),
        ),
      ],
    );
  }
}

class _BlockingProgressDialog extends StatelessWidget {
  const _BlockingProgressDialog({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      content: Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═════════════════════════════════════════════════════════════════════════════

class _ProfileData {
  const _ProfileData({
    required this.name,
    required this.officialName,
    required this.userId,
    required this.phone,
    required this.officialPhone,
    this.momoNumber = '',
    this.momoCode,
    this.countryCode = 'RW',
    required this.country,
    required this.momoProvider,
    required this.momoLinked,
    required this.languageCode,
    required this.notificationsEnabled,
    required this.creditScoreLabel,
    required this.kycStatus,
    required this.isDriver,
    this.vehicleType,
    this.vehicleStatus,
    this.subscriptionLabel,
    this.subscriptionExpiring = false,
  });

  final String name;
  final String officialName;
  final String userId;
  final String phone;
  final String officialPhone;
  final String momoNumber;
  final String? momoCode;
  final String countryCode;
  final String country;
  final String momoProvider;
  final bool momoLinked;
  final String languageCode;
  final bool notificationsEnabled;
  final String creditScoreLabel;
  final String kycStatus;

  String get momoDisplayLabel {
    if (momoNumber.isEmpty) return 'Not linked';
    if (countryCode.toUpperCase() == 'RW') {
      return PhoneValidator.formatRwandanDisplay(momoNumber);
    }
    return momoNumber;
  }

  // Driver-only fields
  final bool isDriver;
  final String? vehicleType;
  final String? vehicleStatus;
  final String? subscriptionLabel;
  final bool subscriptionExpiring;

  String get initials {
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length == 1) return parts.first.characters.take(2).toString();
    return '${parts.first.characters.first}${parts.last.characters.first}'
        .toUpperCase();
  }

  String get languageLabel {
    switch (languageCode) {
      case 'fr':
        return 'Français';
      default:
        return 'English';
    }
  }

  String get kycLabel {
    switch (kycStatus) {
      case 'verified':
        return 'Verified';
      case 'pending_review':
        return 'Pending review';
      case 'rejected':
        return 'Needs update';
      default:
        return 'Unverified';
    }
  }

  Color get kycValueColor {
    switch (kycStatus) {
      case 'verified':
        return AppColors.accent;
      case 'pending_review':
        return AppColors.orange;
      case 'rejected':
        return AppColors.red;
      default:
        return AppColors.text3;
    }
  }

  _ProfileData copyWith({String? languageCode, bool? notificationsEnabled}) {
    return _ProfileData(
      name: name,
      officialName: officialName,
      userId: userId,
      phone: phone,
      officialPhone: officialPhone,
      momoNumber: momoNumber,
      momoCode: momoCode,
      countryCode: countryCode,
      country: country,
      momoProvider: momoProvider,
      momoLinked: momoLinked,
      languageCode: languageCode ?? this.languageCode,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      creditScoreLabel: creditScoreLabel,
      kycStatus: kycStatus,
      isDriver: isDriver,
      vehicleType: vehicleType,
      vehicleStatus: vehicleStatus,
      subscriptionLabel: subscriptionLabel,
      subscriptionExpiring: subscriptionExpiring,
    );
  }

  static const empty = _ProfileData(
    name: 'User',
    officialName: 'User',
    userId: '------',
    phone: '',
    officialPhone: '',
    country: '🇷🇼 Rwanda',
    momoProvider: 'RWF',
    momoLinked: false,
    languageCode: 'en',
    notificationsEnabled: true,
    creditScoreLabel: '--',
    kycStatus: 'unverified',
    isDriver: false,
  );
}

class _DriverProfileSnapshot {
  const _DriverProfileSnapshot({
    required this.hasProfile,
    this.vehicleType,
    this.vehicleStatus,
    this.credits = 0,
    this.subscriptionLabel,
    this.subscriptionExpiring = false,
  });

  final bool hasProfile;
  final String? vehicleType;
  final String? vehicleStatus;
  final int credits;
  final String? subscriptionLabel;
  final bool subscriptionExpiring;

  factory _DriverProfileSnapshot.fromState(DriverState state) {
    final profile = state.profile;
    final subscription = state.subscription;
    final now = DateTime.now();

    final subscriptionExpiring =
        subscription?.expiresAt != null &&
        subscription!.expiresAt!.isAfter(now) &&
        subscription.expiresAt!.difference(now).inDays <= 5;

    return _DriverProfileSnapshot(
      hasProfile: profile != null,
      vehicleType: profile?.vehicleType,
      vehicleStatus: profile == null
          ? null
          : (profile.isRegularDriver ? 'Regular Driver' : 'Occasional Driver'),
      credits: profile?.credits ?? 0,
      subscriptionLabel: _subscriptionLabel(
        subscription,
        profile?.credits ?? 0,
      ),
      subscriptionExpiring: subscriptionExpiring,
    );
  }
}

String? _subscriptionLabel(
  SubscriptionStatus? subscription,
  int creditsBalance,
) {
  if (subscription == null || !subscription.isSubscribed) {
    return 'Mobility credits: $creditsBalance';
  }

  final expiresAt = subscription.expiresAt;
  if (expiresAt == null) {
    return 'Active mobility subscription';
  }

  return 'Active until ${DateFormat('d MMM').format(expiresAt)}';
}

class _LanguageOption {
  const _LanguageOption(this.code, this.flag, this.label);

  final String code;
  final String flag;
  final String label;
}

// ═════════════════════════════════════════════════════════════════════════════
// MOMO EDIT RESULT & SHEET
// ═════════════════════════════════════════════════════════════════════════════

class _MomoEditResult {
  const _MomoEditResult({required this.momoNumber, this.momoCode});
  final String momoNumber;
  final String? momoCode;
}

class _MomoEditSheet extends StatefulWidget {
  const _MomoEditSheet({
    required this.currentMomoNumber,
    required this.country,
    this.currentMomoCode,
  });

  final String currentMomoNumber;
  final String? currentMomoCode;
  final CoolCountry country;

  @override
  State<_MomoEditSheet> createState() => _MomoEditSheetState();
}

class _MomoEditSheetState extends State<_MomoEditSheet> {
  late final TextEditingController _numberController;
  late final TextEditingController _codeController;
  String? _numberError;
  String? _codeError;
  String? _detectedProvider;

  @override
  void initState() {
    super.initState();
    // Show local format (strip +250) in the input for Rwandan numbers.
    final localNumber = widget.country.isoCode.toUpperCase() == 'RW'
        ? PhoneValidator.toRwandanLocal(widget.currentMomoNumber) ??
              widget.currentMomoNumber
        : widget.currentMomoNumber;
    _numberController = TextEditingController(text: localNumber);
    _codeController = TextEditingController(
      text: widget.country.supportsMomoCode ? widget.currentMomoCode ?? '' : '',
    );
    _updateProvider(localNumber);
  }

  @override
  void dispose() {
    _numberController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _updateProvider(String value) {
    final label = PhoneValidator.providerLabel(value, widget.country.isoCode);
    if (mounted) setState(() => _detectedProvider = label);
  }

  void _save() {
    final number = _numberController.text.trim();
    final code = widget.country.supportsMomoCode
        ? _codeController.text.trim()
        : '';

    final numErr = PhoneValidator.validateMomoNumberForCountry(
      number,
      widget.country,
    );
    final codeErr = PhoneValidator.validateMomoCode(
      code,
      country: widget.country,
    );

    setState(() {
      _numberError = numErr;
      _codeError = codeErr;
    });

    if (numErr != null || codeErr != null) return;

    Navigator.of(context).pop(
      _MomoEditResult(momoNumber: number, momoCode: code.isEmpty ? null : code),
    );
  }

  @override
  Widget build(BuildContext context) {
    final country = widget.country;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(22, 12, 22, 22 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border2,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              Text(
                'Edit MoMo Info',
                style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'This number will be used for Mobile Money payments',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: AppColors.text3,
                ),
              ),
              const SizedBox(height: 20),

              // MoMo Number
              Text(
                'MOMO NUMBER',
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text3,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _numberController,
                keyboardType: TextInputType.phone,
                style: GoogleFonts.dmSans(fontSize: 15, color: AppColors.text),
                cursorColor: AppColors.accent,
                decoration: InputDecoration(
                  hintText: country.phoneExampleHint(),
                  hintStyle: GoogleFonts.dmSans(
                    fontSize: 15,
                    color: AppColors.text3.withValues(alpha: 0.5),
                  ),
                  prefixText: '${country.dialCode} ',
                  prefixStyle: GoogleFonts.dmSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text2,
                  ),
                  filled: true,
                  fillColor: AppColors.surface2,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.accent),
                  ),
                  errorText: _numberError,
                ),
                onChanged: _updateProvider,
              ),

              // Provider chip
              if (_detectedProvider != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accentGlow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _detectedProvider!,
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ],

              // MoMo Code (if supported)
              if (country.supportsMomoCode) ...[
                const SizedBox(height: 20),
                Text(
                  'MOMO CODE (OPTIONAL)',
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text3,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  style: GoogleFonts.dmSans(
                    fontSize: 15,
                    color: AppColors.text,
                  ),
                  cursorColor: AppColors.accent,
                  decoration: InputDecoration(
                    hintText: country.momoCodeExample ?? '123456',
                    hintStyle: GoogleFonts.dmSans(
                      fontSize: 15,
                      color: AppColors.text3.withValues(alpha: 0.5),
                    ),
                    filled: true,
                    fillColor: AppColors.surface2,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.accent),
                    ),
                    errorText: _codeError,
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Save button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Save',
                    style: GoogleFonts.dmSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
