import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/tab_pill.dart';
import '../../../shared/widgets/vehicle_chip.dart';
import '../providers/trip_board_provider.dart';
import 'trip_display_strings.dart';

class VehicleFilter {
  const VehicleFilter({required this.label, required this.value});

  final String label;
  final String value;
}

const List<VehicleFilter> tripBoardVehicleFilters = <VehicleFilter>[
  VehicleFilter(label: 'All', value: 'All'),
  VehicleFilter(label: 'Moto', value: 'Moto'),
  VehicleFilter(label: 'Cab', value: 'Cab'),
  VehicleFilter(label: 'Truck', value: 'Truck'),
  VehicleFilter(label: 'Trike', value: 'Trike'),
];

enum TripBoardViewMode { explore, myTrips }

class TripBoardTopCard extends ConsumerWidget {
  const TripBoardTopCard({
    required this.activeView,
    required this.onViewChanged,
    required this.onPostTrip,
    required this.onOpenTripType,
    super.key,
  });

  final TripBoardViewMode activeView;
  final ValueChanged<TripBoardViewMode> onViewChanged;
  final VoidCallback onPostTrip;
  final VoidCallback onOpenTripType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final activeTab = ref.watch(tripBoardActiveTabProvider);
    final selectedVehicle = ref.watch(tripBoardSelectedVehicleProvider);
    final isExplore = activeView == TripBoardViewMode.explore;

    return CoolCard(
      backgroundColor: colors.routeSurface,
      useGradient: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TripBoardModeSwitcher(
            activeView: activeView,
            onChanged: onViewChanged,
          ),
          const SizedBox(height: 16),
          Text(
            isExplore ? 'Explore trips' : 'Manage your trips',
            style: theme.textTheme.titleMedium?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isExplore
                ? 'Find rides near you.'
                : 'Update or repost posted trips.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.secondaryText,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: CoolButton(label: context.l10n.postTrip1, onTap: onPostTrip),
          ),
          if (isExplore) ...[
            const SizedBox(height: 14),
            Text(
              '${tripBoardTabLabel(activeTab)} · ${tripBoardVehicleSummary(selectedVehicle)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.secondaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            CoolButton(
              label: context.l10n.tripType,
              onTap: onOpenTripType,
              variant: CoolButtonVariant.secondary,
            ),
            const SizedBox(height: 12),
            const TripBoardFilterBar(),
          ],
        ],
      ),
    );
  }
}

class TripBoardHeaderCard extends StatelessWidget {
  const TripBoardHeaderCard({
    required this.title,
    required this.subtitle,
    required this.primaryLabel,
    required this.onPrimaryTap,
    this.child,
    super.key,
  });

  final String title;
  final String subtitle;
  final String primaryLabel;
  final VoidCallback onPrimaryTap;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return CoolCard(
      backgroundColor: colors.routeSurface,
      useGradient: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.secondaryText,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: CoolButton(label: primaryLabel, onTap: onPrimaryTap),
          ),
          if (child != null) ...[const SizedBox(height: 16), child!],
        ],
      ),
    );
  }
}

class TripBoardExploreHeaderCard extends ConsumerWidget {
  const TripBoardExploreHeaderCard({required this.onPostTrip, super.key});

  final VoidCallback onPostTrip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TripBoardHeaderCard(
      title: context.l10n.exploreTrips,
      subtitle: context.l10n.findARideNearby,
      primaryLabel: 'Post trip',
      onPrimaryTap: onPostTrip,
    );
  }
}

class TripBoardExploreControlsCard extends ConsumerWidget {
  const TripBoardExploreControlsCard({required this.onOpenTripType, super.key});

  final VoidCallback onOpenTripType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final activeTab = ref.watch(tripBoardActiveTabProvider);
    final selectedVehicle = ref.watch(tripBoardSelectedVehicleProvider);

    return CoolCard(
      backgroundColor: colors.routeSurface,
      useGradient: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Results',
            style: theme.textTheme.titleSmall?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${tripBoardTabLabel(activeTab)} · ${tripBoardVehicleSummary(selectedVehicle)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.secondaryText,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          CoolButton(
            label: context.l10n.tripType,
            onTap: onOpenTripType,
            variant: CoolButtonVariant.secondary,
          ),
          const SizedBox(height: 12),
          const TripBoardFilterBar(),
        ],
      ),
    );
  }
}

class TripBoardMyTripsHeaderCard extends StatelessWidget {
  const TripBoardMyTripsHeaderCard({required this.onPostTrip, super.key});

  final VoidCallback onPostTrip;

  @override
  Widget build(BuildContext context) {
    return TripBoardHeaderCard(
      title: context.l10n.manageYourTrips,
      subtitle: context.l10n.manageYourPostedTrips,
      primaryLabel: 'Post trip',
      onPrimaryTap: onPostTrip,
    );
  }
}

class TripBoardModeSwitcher extends StatelessWidget {
  const TripBoardModeSwitcher({
    required this.activeView,
    required this.onChanged,
    super.key,
  });

  final TripBoardViewMode activeView;
  final ValueChanged<TripBoardViewMode> onChanged;

  static const List<(TripBoardViewMode, String)> _items =
      <(TripBoardViewMode, String)>[
        (TripBoardViewMode.explore, 'Explore'),
        (TripBoardViewMode.myTrips, 'My trips'),
      ];

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.cardSurfaceStrong,
        borderRadius: BorderRadius.circular(CoolRadii.lg),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          for (final item in _items) ...[
            Expanded(
              child: TabPill(
                label: item.$2,
                isActive: activeView == item.$1,
                onTap: () => onChanged(item.$1),
              ),
            ),
            if (item != _items.last) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class TripBoardTabSwitcher extends StatelessWidget {
  const TripBoardTabSwitcher({
    required this.activeTab,
    required this.onChanged,
    super.key,
  });

  final TripBoardTab activeTab;
  final ValueChanged<TripBoardTab> onChanged;

  static const List<(TripBoardTab, String)> _tabs = <(TripBoardTab, String)>[
    (TripBoardTab.passengerTrips, 'Passenger'),
    (TripBoardTab.driverReturnTrips, 'Driver returns'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.cardSurfaceStrong,
        borderRadius: BorderRadius.circular(CoolRadii.lg),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          for (final tab in _tabs) ...[
            Expanded(
              child: TabPill(
                label: tab.$2,
                isActive: activeTab == tab.$1,
                onTap: () => onChanged(tab.$1),
              ),
            ),
            if (tab != _tabs.last) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class TripBoardTabSection extends ConsumerWidget {
  const TripBoardTabSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTab = ref.watch(tripBoardActiveTabProvider);
    return TripBoardTabSwitcher(
      activeTab: activeTab,
      onChanged: (tab) {
        unawaited(ref.read(tripBoardProvider.notifier).setActiveTab(tab));
      },
    );
  }
}

class TripBoardFilterBar extends ConsumerWidget {
  const TripBoardFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedVehicle = ref.watch(tripBoardSelectedVehicleProvider);
    final notifier = ref.read(tripBoardProvider.notifier);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (
            var index = 0;
            index < tripBoardVehicleFilters.length;
            index++
          ) ...[
            VehicleChip(
              label: tripBoardVehicleFilters[index].label,
              isSelected:
                  selectedVehicle == tripBoardVehicleFilters[index].value,
              onTap: () {
                unawaited(
                  notifier.setVehicleFilter(
                    tripBoardVehicleFilters[index].value,
                  ),
                );
              },
            ),
            if (index != tripBoardVehicleFilters.length - 1)
              const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

String tripBoardTabLabel(TripBoardTab tab) {
  return tripCollectionLabel(
    isDriverReturn: tab == TripBoardTab.driverReturnTrips,
  );
}

String tripBoardVehicleSummary(String selectedVehicle) {
  return selectedVehicle == 'All' ? 'Any type' : '$selectedVehicle only';
}

class TripBoardTripTypeSheet extends StatelessWidget {
  const TripBoardTripTypeSheet({required this.activeTab, super.key});

  final TripBoardTab activeTab;

  @override
  Widget build(BuildContext context) {
    return _TripBoardSelectionSheet<TripBoardTab>(
      title: context.l10n.tripType,
      subtitle: context.l10n.filterByTripType,
      value: activeTab,
      options: <({TripBoardTab value, String label, String subtitle})>[
        (
          value: TripBoardTab.passengerTrips,
          label: context.l10n.passengerTrips,
          subtitle: context.l10n.ridesNearYou,
        ),
        (
          value: TripBoardTab.driverReturnTrips,
          label: context.l10n.driverReturns,
          subtitle: context.l10n.driversWithAvailableSeats,
        ),
      ],
    );
  }
}

class _TripBoardSelectionSheet<T> extends StatelessWidget {
  const _TripBoardSelectionSheet({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.options,
  });

  final String title;
  final String subtitle;
  final T value;
  final List<({T value, String label, String subtitle})> options;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.overlaySurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.borderStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: colors.primaryText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.secondaryText,
                  fontWeight: FontWeight.w700,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              for (var index = 0; index < options.length; index++) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    options[index].value == value
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: options[index].value == value
                        ? colors.accent
                        : colors.tertiaryText,
                  ),
                  title: Text(
                    options[index].label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.primaryText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    options[index].subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.secondaryText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () => Navigator.of(context).pop(options[index].value),
                ),
                if (index != options.length - 1)
                  Divider(color: colors.border, height: 1),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
