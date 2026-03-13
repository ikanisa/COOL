import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import 'profile_data.dart';
import 'profile_settings_widgets.dart';

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
    final driverValue = profile.isDriver
        ? profile.driverSummary
        : 'Open driver setup to add vehicle type, plate number, and base.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Travel role',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Passenger stays available by default. Open driver mode only when you want to post as a driver.',
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: AppColors.text2,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 18),
        ProfileSettingsSection(
          title: 'Default',
          rows: [
            ProfileSettingsRow(
              icon: Icons.route_outlined,
              label: 'Passenger',
              value: profile.momoLinked
                  ? 'Default role for trip requests and bookings.'
                  : 'Default role. Add a wallet route before booking trips.',
              valueColor: profile.momoLinked
                  ? AppColors.accent
                  : AppColors.text2,
              trailing: _TravelRoleBadge(
                label: profile.momoLinked ? 'Default' : 'Needs wallet',
                color: profile.momoLinked ? AppColors.accent : AppColors.orange,
              ),
              onTap: onOpenPassengerTools,
              showArrow: onOpenPassengerTools != null,
            ),
          ],
        ),
        const SizedBox(height: 14),
        ProfileSettingsSection(
          title: 'Optional',
          rows: [
            ProfileSettingsRow(
              icon: Icons.directions_car_outlined,
              label: profile.isDriver ? 'Driver setup' : 'Switch to driver',
              value: driverValue,
              valueColor: profile.isDriver ? AppColors.accent : AppColors.text2,
              trailing: _TravelRoleBadge(
                label: profile.isDriver ? 'Open' : 'Set up',
                color: AppColors.blue,
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
