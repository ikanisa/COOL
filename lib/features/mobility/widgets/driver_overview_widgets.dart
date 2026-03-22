import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/cool_palette.dart';
import '../../../shared/widgets/cool_card.dart';
import 'driver_profile_models.dart';
import '../../../core/l10n/l10n.dart';

/// Stats card showing avatar, name, driver ID, online pill, and numeric stats.
class DriverStatsCard extends StatelessWidget {
  const DriverStatsCard({required this.driver, super.key});

  final DriverProfileData driver;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final hasUnlimitedTrips = driver.subscription != null;
    final isLowOnTrips = !hasUnlimitedTrips && driver.freeTripsRemaining < 5;

    return CoolCard(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [palette.accent, palette.blue],
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  driver.initials,
                  style: GoogleFonts.dmSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: palette.surface,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      driver.name,
                      style: GoogleFonts.dmSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: palette.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Driver ${driver.driverId}',
                      style: GoogleFonts.dmMono(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: palette.text2,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color:
                      (driver.isOnline ? palette.accent : palette.surface3)
                          .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color:
                        (driver.isOnline ? palette.accent : palette.border)
                            .withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.circle,
                      size: 15,
                      color: driver.isOnline
                          ? palette.accent
                          : palette.text3,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      driver.isOnline ? 'Online' : 'Offline',
                      style: GoogleFonts.dmMono(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: driver.isOnline
                            ? palette.accent
                            : palette.text2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: DriverStatBox(
                  label: context.l10n.tripsPosted,
                  value: '${driver.tripsDone}',
                  valueColor: palette.accent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DriverStatBox(
                  label: context.l10n.mobilityCredits,
                  value: hasUnlimitedTrips
                      ? 'Unlimited'
                      : '${driver.freeTripsRemaining}',
                  valueColor: palette.yellow,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DriverStatBox(
                  label: context.l10n.status,
                  value: hasUnlimitedTrips
                      ? 'Subscribed'
                      : (isLowOnTrips ? 'Low' : 'Ready'),
                  valueColor: isLowOnTrips
                      ? palette.orange
                      : palette.accent,
                  isMonospace: false,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small stat box used in the driver stats row.
class DriverStatBox extends StatelessWidget {
  const DriverStatBox({
    required this.label,
    required this.value,
    required this.valueColor,
    this.isMonospace = true,
    super.key,
  });

  final String label;
  final String value;
  final Color valueColor;
  final bool isMonospace;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: palette.surface3,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (isMonospace ? GoogleFonts.dmMono : GoogleFonts.dmSans)(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: palette.text3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Availability toggle card with online/offline status.
class DriverAvailabilityCard extends StatelessWidget {
  const DriverAvailabilityCard({
    required this.vehicleType,
    required this.isOnline,
    required this.onChanged,
    super.key,
  });

  final String vehicleType;
  final bool isOnline;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return CoolCard(
      borderColor: isOnline ? palette.accent.withValues(alpha: 0.35) : null,
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: palette.surface2,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Image.asset(
                  tripVehicleIcon(vehicleType),
                  width: 22,
                  height: 22,
                  color: palette.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Driver Mode',
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: palette.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      vehicleType,
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: palette.text2,
                      ),
                    ),
                  ],
                ),
              ),
              DriverModeToggle(value: isOnline, onChanged: onChanged),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isOnline ? palette.accentGlow : palette.surface3,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isOnline ? palette.accent : palette.border,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: isOnline ? palette.accent : palette.text3,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isOnline
                        ? 'Online — visible nearby.'
                        : 'Offline — toggle to go live.',
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isOnline ? palette.accent : palette.text2,
                      height: 1.4,
                    ),
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

/// Animated toggle for driver online/offline mode.
class DriverModeToggle extends StatelessWidget {
  const DriverModeToggle({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Semantics(
      button: true,
      toggled: value,
      label: value ? 'Driver mode on' : 'Driver mode off',
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 52,
          height: 28,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: value ? palette.accent : palette.surface3,
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: palette.text,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// Summary card showing subscription credits and optionally an upgrade link.
class DriverSubscriptionSummaryCard extends StatelessWidget {
  const DriverSubscriptionSummaryCard({
    required this.freeTripsRemaining,
    required this.tripsUsedThisMonth,
    required this.showUpgradeHint,
    this.onOpenManage,
    super.key,
  });

  final int freeTripsRemaining;
  final int tripsUsedThisMonth;
  final bool showUpgradeHint;
  final VoidCallback? onOpenManage;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return CoolCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: palette.surface2,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.account_balance_wallet_outlined,
              color: palette.text2,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Subscription',
                  style: GoogleFonts.dmSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: palette.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'freeTripsRemaining credits left tripsUsedThisMonth',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: palette.text2,
                    height: 1.4,
                  ),
                ),
                if (showUpgradeHint && onOpenManage != null) ...[
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: onOpenManage,
                    child: Text(context.l10n.openSubscriptionOptions),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// View switcher between Overview and Manage tabs.
class DriverViewSwitcher extends StatelessWidget {
  const DriverViewSwitcher({
    required this.activeIndex,
    required this.onChanged,
    super.key,
  });

  final int activeIndex;
  final ValueChanged<int> onChanged;

  static const _labels = ['Overview', 'Manage'];

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _labels.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: activeIndex == i,
                label: '${_labels[i]} tab',
                child: GestureDetector(
                  onTap: () => onChanged(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: activeIndex == i
                          ? palette.accent
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _labels[i],
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: activeIndex == i ? onPrimary : palette.text2,
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