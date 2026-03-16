import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/config/app_market.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/cool_palette.dart';
import '../../../core/utils/phone_validator.dart';
import '../../../shared/widgets/cool_card.dart';
import 'profile_data.dart';

/// Top-of-screen card showing user name, phone, KYC badge, and member since.
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({required this.profile, super.key});

  final ProfileData profile;

  Color _kycColor(CoolPalette palette) {
    return switch (profile.kycStatus) {
      'verified' => palette.accent,
      'pending_review' => const Color(0xFFF59E0B),
      'rejected' => palette.red,
      _ => palette.text3,
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
    final palette = context.coolPalette;
    final memberSince = profile.createdAt != null
        ? DateFormat('MMM yyyy').format(profile.createdAt!)
        : null;

    return CoolCard(
      backgroundColor: palette.surface,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: palette.surface2,
              borderRadius: BorderRadius.circular(18),
            ),
            alignment: Alignment.center,
            child: Text(
              profile.initials,
              style: GoogleFonts.dmSans(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: palette.accent,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.name,
                  style: GoogleFonts.dmSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: palette.text,
                  ),
                ),
                if (profile.phone.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    profile.phone,
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: palette.text2,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    // KYC badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _kycColor(palette).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _kycIcon(),
                            size: 12,
                            color: _kycColor(palette),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _kycLabel(),
                            style: GoogleFonts.dmSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: _kycColor(palette),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Member since
                    if (memberSince != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        'Since $memberSince',
                        style: GoogleFonts.dmSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: palette.text3,
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
    final palette = context.coolPalette;
    final l10n = context.l10n;
    final country = AppMarket.country;
    final qrData = PhoneValidator.generateMomoQrData(
      momoNumber,
      country,
      preferDirectDial: false,
    );
    final providerLabel = PhoneValidator.providerLabel(momoNumber, countryCode);

    return CoolCard(
      backgroundColor: palette.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.profileMomoQrTitle,
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 14),
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
                size: 132,
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
                  color: palette.accentGlow,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  providerLabel,
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: palette.accent,
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
    final palette = context.coolPalette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
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
                  color: palette.border2,
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
