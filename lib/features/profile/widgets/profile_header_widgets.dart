import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/config/app_market.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/utils/phone_validator.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_glass_card.dart';
import 'profile_data.dart';

/// Top-of-screen card showing user name, phone, KYC badge, and member since.
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({required this.profile, super.key});

  final ProfileData profile;

  Color _kycColor(CoolSemanticColors colors) {
    return switch (profile.kycStatus) {
      'verified' => colors.accent,
      'pending_review' => colors.warning,
      'rejected' => colors.danger,
      _ => colors.tertiaryText,
    };
  }

  String _kycLabel() {
    return switch (profile.kycStatus) {
      'verified' => 'Verified',
      'pending_review' => 'Pending',
      'rejected' => 'Update needed',
      _ => 'Unverified',
    };
  }

  IconData _kycIcon() {
    return switch (profile.kycStatus) {
      'verified' => Icons.verified_rounded,
      'pending_review' => Icons.schedule_rounded,
      'rejected' => Icons.error_outline_rounded,
      _ => Icons.shield_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final kycColor = _kycColor(colors);
    final memberSince = profile.createdAt != null
        ? DateFormat('MMM yyyy').format(profile.createdAt!)
        : null;

    return CoolGlassCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: colors.operationalSurface,
              borderRadius: BorderRadius.circular(CoolRadii.md),
              border: Border.all(color: colors.border),
            ),
            alignment: Alignment.center,
            child: Text(
              profile.initials,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: colors.accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (profile.phone.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    profile.phone,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.secondaryText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: kycColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(CoolRadii.sm),
                        border: Border.all(
                          color: kycColor.withValues(alpha: 0.22),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_kycIcon(), size: 16, color: kycColor),
                          const SizedBox(width: 4),
                          Text(
                            _kycLabel(),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: kycColor,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (memberSince != null) ...[
                      const SizedBox(width: 10),
                      Text(
                        'Since $memberSince',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.secondaryText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// QR code card for MoMo payments.
class ProfileMomoQrCard extends StatelessWidget {
  const ProfileMomoQrCard({
    required this.momoNumber,
    required this.countryCode,
    super.key,
  });

  final String momoNumber;
  final String countryCode;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final country = AppMarket.country;
    final qrData = PhoneValidator.generateMomoQrData(
      momoNumber,
      country,
      preferDirectDial: false,
    );
    final providerLabel = PhoneValidator.providerLabel(momoNumber, countryCode);

    return CoolCard(
      backgroundColor: colors.cardSurfaceStrong,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.profileMomoQrTitle,
            style: theme.textTheme.titleSmall?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Container(
              decoration: BoxDecoration(
                // Keep the QR payload on a white surface for reliable scanning
                // regardless of the surrounding app theme.
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.all(12),
              child: QrImageView(
                data: qrData,
                size: 156,
                padding: const EdgeInsets.all(14),
                backgroundColor: Colors.white,
                errorCorrectionLevel: QrErrorCorrectLevel.H,
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
          ),
          if (providerLabel != null) ...[
            const SizedBox(height: 12),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: colors.contactSurface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: colors.border),
                ),
                child: Text(
                  providerLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Standard bottom-sheet wrapper used on the profile screen.
class ProfileSheet extends StatelessWidget {
  const ProfileSheet({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.overlaySurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.borderStrong,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
