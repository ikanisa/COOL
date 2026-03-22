import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/cool_palette.dart';
import 'profile_data.dart';
import 'profile_settings_widgets.dart';
import '../../../core/l10n/l10n.dart';

class ProfileTravelRoleSheet extends StatelessWidget {
  const ProfileTravelRoleSheet({
    required this.profile,
    required this.onOpenDriverSetup,
    this.onOpenPassengerTools,
    super.key,
  });

  final ProfileData profile;
  final VoidCallback onOpenDriverSetup;
  final VoidCallback? onOpenPassengerTools;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final driverValue = profile.isDriver
        ? profile.driverSummary
        : 'Setup driver profile';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Travel role',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: palette.text,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Passenger stays available by',
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: palette.text2,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 18),
        ProfileSettingsSection(
          title: context.l10n.defaultKey,
          rows: [
            ProfileSettingsRow(
              icon: Icons.route_outlined,
              label: context.l10n.passenger,
              value: profile.momoLinked
                  ? 'Default travel role'
                  : 'Add wallet first',
              valueColor: profile.momoLinked
                  ? palette.accent
                  : palette.text2,
              trailing: _TravelRoleBadge(
                label: profile.momoLinked ? 'Default' : 'Needs wallet',
                color: profile.momoLinked ? palette.accent : palette.orange,
              ),
              onTap: onOpenPassengerTools,
              showArrow: onOpenPassengerTools != null,
            ),
          ],
        ),
        const SizedBox(height: 14),
        ProfileSettingsSection(
          title: context.l10n.optional,
          rows: [
            ProfileSettingsRow(
              icon: Icons.directions_car_outlined,
              label: profile.isDriver ? 'Driver setup' : 'Switch to driver',
              value: driverValue,
              valueColor: profile.isDriver ? palette.accent : palette.text2,
              trailing: _TravelRoleBadge(
                label: profile.isDriver ? 'Open' : 'Set up',
                color: palette.blue,
              ),
              onTap: onOpenDriverSetup,
              showArrow: false,
            ),
          ],
        ),
      ],
    );
  }
}

class _TravelRoleBadge extends StatelessWidget {
  const _TravelRoleBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}