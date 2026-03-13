import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/config/country_catalog.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/phone_validator.dart';
import '../../../shared/widgets/cool_card.dart';
import 'profile_data.dart';

/// Top-of-screen card showing user name, initials, and country/currency.
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({required this.profile, super.key});

  final ProfileData profile;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      backgroundColor: AppColors.surface,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(18),
            ),
            alignment: Alignment.center,
            child: Text(
              profile.initials,
              style: GoogleFonts.dmSans(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
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
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${profile.country} · ${profile.currencyCode}',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text2,
                  ),
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
    final l10n = context.l10n;
    final country =
        CoolCountryCatalog.byIsoCode(countryCode) ??
        CoolCountryCatalog.defaultCountry;
    final qrData = PhoneValidator.generateMomoQrData(
      momoNumber,
      country,
      preferDirectDial: false,
    );
    final displayNumber = PhoneValidator.formatMomoDisplay(momoNumber, country);
    final providerLabel = PhoneValidator.providerLabel(momoNumber, countryCode);

    return CoolCard(
      backgroundColor: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.profileMomoQrTitle,
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.profileMomoQrSubtitle(displayNumber),
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: AppColors.text2,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: Container(
              decoration: BoxDecoration(
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
                  color: AppColors.accentGlow,
                  borderRadius: BorderRadius.circular(999),
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
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                  color: AppColors.border2,
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
