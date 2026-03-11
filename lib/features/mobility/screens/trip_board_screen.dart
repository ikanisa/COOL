import 'dart:async';

import 'package:cool_app/features/mobility/models/trip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../auth/providers/auth_provider.dart';
import '../../../core/services/whatsapp_contact_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/section_title.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/trip_card.dart';
import '../../../shared/widgets/vehicle_chip.dart';
import '../../../shared/widgets/wa_button.dart';
import '../providers/mobility_location_provider.dart';
import '../providers/trip_board_provider.dart';
import '../services/mobility_whatsapp_service.dart';
import '../widgets/mobility_listing_sheet.dart';

class TripBoardScreen extends ConsumerStatefulWidget {
  const TripBoardScreen({super.key});

  @override
  ConsumerState<TripBoardScreen> createState() => _TripBoardScreenState();
}

class _TripBoardScreenState extends ConsumerState<TripBoardScreen> {
  late final ProviderSubscription<MobilityLocationState> _locationSubscription;

  @override
  void initState() {
    super.initState();
    _locationSubscription = ref.listenManual<MobilityLocationState>(
      mobilityLocationProvider,
      (previous, next) {
        final notifier = ref.read(tripBoardProvider.notifier);
        notifier.updateLocation(next.position);

        final hadLocation = previous?.hasLocation ?? false;
        if (!hadLocation && next.hasLocation) {
          unawaited(notifier.loadPublicTrips());
        } else if (hadLocation && !next.hasLocation) {
          notifier.clearPublicTrips();
        }
      },
    );

    Future<void>.microtask(_bootstrap);
  }

  @override
  void dispose() {
    _locationSubscription.close();
    unawaited(ref.read(mobilityLocationProvider.notifier).releaseTracking());
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final locationNotifier = ref.read(mobilityLocationProvider.notifier);
    await locationNotifier.bootstrap();
    await locationNotifier.acquireTracking();

    ref
        .read(tripBoardProvider.notifier)
        .updateLocation(ref.read(mobilityLocationProvider).position);

    await ref.read(tripBoardProvider.notifier).refresh();
  }

  Future<void> _refreshTrips() async {
    await ref.read(mobilityLocationProvider.notifier).refresh();
    ref
        .read(tripBoardProvider.notifier)
        .updateLocation(ref.read(mobilityLocationProvider).position);
    await ref.read(tripBoardProvider.notifier).refresh();
  }

  Future<void> _openWhatsApp(Trip trip) async {
    final phoneNumber =
        trip.whatsappNumber?.trim() ?? trip.contactPhone?.trim() ?? '';
    if (phoneNumber.isEmpty) {
      _showSnackBar('Contact details are not available for this trip yet.');
      return;
    }

    await WhatsAppContactService.openChat(
      context,
      phoneNumber: phoneNumber,
      message: MobilityWhatsAppService.buildTripInquiryMessage(
        trip: trip,
        requester: ref.read(currentUserProvider),
      ),
    );
  }

  Future<void> _showTripPreview(Trip trip) {
    return showTripListingSheet(
      context,
      trip: trip,
      buttonLabel: _hasContactPhone(trip) ? 'Open WhatsApp' : 'No contact yet',
      onOpenWhatsApp: _hasContactPhone(trip)
          ? () {
              unawaited(_openWhatsApp(trip));
            }
          : null,
    );
  }

  Future<void> _cancelTrip(Trip trip) async {
    final tripId = trip.id;
    if (tripId == null) {
      _showSnackBar('This trip cannot be canceled right now.');
      return;
    }

    final succeeded = await ref
        .read(tripBoardProvider.notifier)
        .cancelTrip(tripId);

    if (!mounted) {
      return;
    }

    if (succeeded) {
      _showSnackBar('Trip canceled.');
      return;
    }

    final error = ref.read(tripBoardMutationErrorProvider);
    if (error != null) {
      _showSnackBar(error);
    }
  }

  Future<void> _deleteTrip(Trip trip) async {
    final tripId = trip.id;
    if (tripId == null) {
      _showSnackBar('This trip cannot be deleted right now.');
      return;
    }

    // Confirmation dialog — destructive action must not be instant.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.border),
        ),
        title: Text(
          'Delete Trip?',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        content: Text(
          'This will permanently delete the trip from '
          '${trip.fromLocation} to ${trip.toLocation}. '
          'This action cannot be undone.',
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
              'Delete',
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.red,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final succeeded = await ref
        .read(tripBoardProvider.notifier)
        .deleteTrip(tripId);

    if (!mounted) {
      return;
    }

    if (succeeded) {
      _showSnackBar('Trip deleted.');
      return;
    }

    final error = ref.read(tripBoardMutationErrorProvider);
    if (error != null) {
      _showSnackBar(error);
    }
  }

  Future<void> _pauseTrip(Trip trip) async {
    final tripId = trip.id;
    if (tripId == null) {
      _showSnackBar('This trip cannot be paused right now.');
      return;
    }

    final succeeded = await ref
        .read(tripBoardProvider.notifier)
        .pauseTrip(tripId);

    if (!mounted) {
      return;
    }

    if (succeeded) {
      _showSnackBar('Trip paused. It will no longer appear to others.');
      return;
    }

    final error = ref.read(tripBoardMutationErrorProvider);
    if (error != null) {
      _showSnackBar(error);
    }
  }

  Future<void> _repostTrip(Trip trip) async {
    final tripId = trip.id;
    if (tripId == null) {
      _showSnackBar('This trip cannot be reposted right now.');
      return;
    }

    final succeeded = await ref
        .read(tripBoardProvider.notifier)
        .repostTrip(tripId);

    if (!mounted) {
      return;
    }

    if (succeeded) {
      _showSnackBar('Trip reposted and visible again.');
      return;
    }

    final error = ref.read(tripBoardMutationErrorProvider);
    if (error != null) {
      _showSnackBar(error);
    }
  }

  Future<void> _showTripActions(Trip trip) async {
    final isPaused = _isPausedTrip(trip);
    final isActive = _isActiveTrip(trip);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Trip Actions',
                  style: GoogleFonts.dmSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${trip.fromLocation} \u2192 ${trip.toLocation}',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text2,
                  ),
                ),
                const SizedBox(height: 18),
                if (isActive) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.pause_circle_outline_rounded,
                      color: AppColors.orange,
                    ),
                    title: Text(
                      'Pause Trip',
                      style: GoogleFonts.dmSans(
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                    subtitle: Text(
                      'Temporarily hide from others',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: AppColors.text3,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      unawaited(_pauseTrip(trip));
                    },
                  ),
                  const Divider(color: AppColors.border),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.cancel_outlined,
                      color: AppColors.red,
                    ),
                    title: Text(
                      'Cancel Trip',
                      style: GoogleFonts.dmSans(
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      unawaited(_cancelTrip(trip));
                    },
                  ),
                  const Divider(color: AppColors.border),
                ],
                if (isPaused) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.play_circle_outline_rounded,
                      color: AppColors.accent,
                    ),
                    title: Text(
                      'Repost Trip',
                      style: GoogleFonts.dmSans(
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                    subtitle: Text(
                      'Make visible to others again',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: AppColors.text3,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      unawaited(_repostTrip(trip));
                    },
                  ),
                  const Divider(color: AppColors.border),
                ],
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.delete_outline_rounded,
                    color: AppColors.red,
                  ),
                  title: Text(
                    'Delete Trip',
                    style: GoogleFonts.dmSans(
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    unawaited(_deleteTrip(trip));
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.surface3,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(
          'Trip Board',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'trip-board-post-fab',
        backgroundColor: AppColors.accent,
        onPressed: () => context.push('/mobility/schedule'),
        child: const Icon(Icons.add_rounded, color: Colors.black, size: 28),
      ),
      body: RefreshIndicator(
        color: AppColors.accent,
        backgroundColor: AppColors.surface,
        onRefresh: _refreshTrips,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(18, 8, 18, 0),
              sliver: SliverToBoxAdapter(child: _TripBoardInfoBanner()),
            ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(18, 16, 18, 0),
              sliver: SliverToBoxAdapter(child: _TripBoardTabSection()),
            ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(18, 14, 18, 0),
              sliver: SliverToBoxAdapter(child: _TripBoardFilterBar()),
            ),
            _TripBoardPublicTripsSliver(
              onPostTrip: () => context.push('/mobility/schedule'),
              onPreviewTap: (trip) {
                unawaited(_showTripPreview(trip));
              },
              onWhatsAppTap: (trip) {
                unawaited(_openWhatsApp(trip));
              },
            ),
            _TripBoardMyTripsSliver(
              onCancelTrip: (trip) {
                unawaited(_cancelTrip(trip));
              },
              onDeleteTrip: (trip) {
                unawaited(_deleteTrip(trip));
              },
              onShowActions: (trip) {
                unawaited(_showTripActions(trip));
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      ),
    );
  }

  static const _vehicleFilters = [
    _VehicleFilter(label: 'All', value: 'All'),
    _VehicleFilter(label: '🛺 Moto', value: 'Moto'),
    _VehicleFilter(label: '🚗 Cab', value: 'Cab'),
    _VehicleFilter(label: '🚛 Truck', value: 'Truck'),
    _VehicleFilter(label: '🚐 Liffan', value: 'Liffan'),
  ];
}

class _TripBoardInfoBanner extends StatelessWidget {
  const _TripBoardInfoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.blueGlow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.blue.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📋', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Open scheduled trips nearby. Tap a listing to review details, then continue on WhatsApp to agree on price and pickup.',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.blue,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TripBoardTabSwitcher extends StatelessWidget {
  const _TripBoardTabSwitcher({
    required this.activeTab,
    required this.onChanged,
  });

  final TripBoardTab activeTab;
  final ValueChanged<TripBoardTab> onChanged;

  static const _tabs = [
    (TripBoardTab.passengerTrips, 'Passenger Trips'),
    (TripBoardTab.driverReturnTrips, 'Driver Return Trips'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          for (final tab in _tabs)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(tab.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: activeTab == tab.$1
                        ? AppColors.accent
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    tab.$2,
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: activeTab == tab.$1
                          ? Colors.black
                          : AppColors.text2,
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

class _TripBoardTabSection extends ConsumerWidget {
  const _TripBoardTabSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTab = ref.watch(tripBoardActiveTabProvider);
    return _TripBoardTabSwitcher(
      activeTab: activeTab,
      onChanged: (tab) {
        unawaited(ref.read(tripBoardProvider.notifier).setActiveTab(tab));
      },
    );
  }
}

class _TripBoardFilterBar extends ConsumerWidget {
  const _TripBoardFilterBar();

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
            index < _TripBoardScreenState._vehicleFilters.length;
            index++
          ) ...[
            VehicleChip(
              label: _TripBoardScreenState._vehicleFilters[index].label,
              isSelected:
                  selectedVehicle ==
                  _TripBoardScreenState._vehicleFilters[index].value,
              onTap: () {
                unawaited(
                  notifier.setVehicleFilter(
                    _TripBoardScreenState._vehicleFilters[index].value,
                  ),
                );
              },
            ),
            if (index != _TripBoardScreenState._vehicleFilters.length - 1)
              const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _TripBoardPublicTripsSliver extends ConsumerWidget {
  const _TripBoardPublicTripsSliver({
    required this.onPostTrip,
    required this.onPreviewTap,
    required this.onWhatsAppTap,
  });

  final VoidCallback onPostTrip;
  final ValueChanged<Trip> onPreviewTap;
  final ValueChanged<Trip> onWhatsAppTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips = ref.watch(tripBoardPublicTripsProvider);
    final activeTab = ref.watch(tripBoardActiveTabProvider);
    final isLoading = ref.watch(tripBoardPublicTripsLoadingProvider);
    final error = ref.watch(tripBoardPublicErrorProvider);
    final locationState = ref.watch(mobilityLocationProvider);
    final locationNotifier = ref.read(mobilityLocationProvider.notifier);

    if (isLoading && trips.isEmpty) {
      return const SliverPadding(
        padding: EdgeInsets.fromLTRB(18, 18, 18, 0),
        sliver: SliverToBoxAdapter(
          child: _TripBoardLoadingState(
            title: 'Loading nearby trips',
            subtitle: 'Checking currently open scheduled trips around you.',
          ),
        ),
      );
    }

    if (!locationState.hasLocation) {
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
        sliver: SliverToBoxAdapter(
          child: _TripBoardLocationStateCard(
            locationState: locationState,
            onEnableLocation: () {
              unawaited(locationNotifier.requestForegroundAccess());
            },
            onOpenAppSettings: () {
              unawaited(locationNotifier.openAppSettings());
            },
            onOpenLocationSettings: () {
              unawaited(locationNotifier.openLocationSettings());
            },
          ),
        ),
      );
    }

    if (error != null && trips.isEmpty) {
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
        sliver: SliverToBoxAdapter(
          child: _TripBoardEmptyState(
            emoji: '⚠️',
            title: 'Could not load nearby trips',
            subtitle: error,
            actionLabel: 'Post Your Trip',
            onActionTap: onPostTrip,
          ),
        ),
      );
    }

    if (activeTab == TripBoardTab.driverReturnTrips) {
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
        sliver: _DriverReturnTripsSliver(
          trips: trips,
          onEmptyActionTap: onPostTrip,
          onPreviewTap: onPreviewTap,
          onWhatsAppTap: onWhatsAppTap,
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
      sliver: _TripsTabSliver(
        trips: trips,
        emptyTitle: 'No scheduled trips nearby',
        emptyActionLabel: 'Post Your Trip',
        onEmptyActionTap: onPostTrip,
        onPreviewTap: onPreviewTap,
        onWhatsAppTap: onWhatsAppTap,
        buttonLabelBuilder: (trip) =>
            _hasContactPhone(trip) ? 'Join on WhatsApp' : 'No contact yet',
      ),
    );
  }
}

class _TripBoardMyTripsSliver extends ConsumerWidget {
  const _TripBoardMyTripsSliver({
    required this.onCancelTrip,
    required this.onDeleteTrip,
    required this.onShowActions,
  });

  final ValueChanged<Trip> onCancelTrip;
  final ValueChanged<Trip> onDeleteTrip;
  final ValueChanged<Trip> onShowActions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myTrips = ref.watch(tripBoardMyTripsProvider);
    final isLoading = ref.watch(tripBoardMyTripsLoadingProvider);
    final actionTripId = ref.watch(tripBoardActionTripIdProvider);
    final error = ref.watch(tripBoardMyTripsErrorProvider);

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(18, 28, 18, 0),
      sliver: SliverMainAxisGroup(
        slivers: [
          const SliverToBoxAdapter(
            child: SectionTitle(title: 'My Posted Trips'),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          if (isLoading && myTrips.isEmpty)
            const SliverToBoxAdapter(
              child: _TripBoardLoadingState(
                title: 'Loading your trips',
                subtitle: 'Fetching the trips you posted from your account.',
              ),
            )
          else if (error != null && myTrips.isEmpty)
            SliverToBoxAdapter(
              child: _TripBoardEmptyState(
                emoji: '⚠️',
                title: 'Could not load your trips',
                subtitle: error,
              ),
            )
          else if (myTrips.isEmpty)
            const SliverToBoxAdapter(
              child: _TripBoardEmptyState(
                emoji: '🗂️',
                title: 'No trips posted yet',
                subtitle:
                    'Trips you create from the schedule screen will appear here.',
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final trip = myTrips[index];
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index == myTrips.length - 1 ? 0 : 12,
                  ),
                  child: _MyTripTile(
                    trip: trip,
                    isBusy: actionTripId == trip.id,
                    onCancel: _isActiveTrip(trip)
                        ? () => onCancelTrip(trip)
                        : null,
                    onDelete: () => onDeleteTrip(trip),
                    onLongPress: () => onShowActions(trip),
                  ),
                );
              }, childCount: myTrips.length),
            ),
        ],
      ),
    );
  }
}

class _TripsTabSliver extends StatelessWidget {
  const _TripsTabSliver({
    required this.trips,
    required this.emptyTitle,
    required this.emptyActionLabel,
    required this.onEmptyActionTap,
    required this.onPreviewTap,
    required this.onWhatsAppTap,
    required this.buttonLabelBuilder,
  });

  final List<Trip> trips;
  final String emptyTitle;
  final String emptyActionLabel;
  final VoidCallback onEmptyActionTap;
  final ValueChanged<Trip> onPreviewTap;
  final ValueChanged<Trip> onWhatsAppTap;
  final String Function(Trip trip) buttonLabelBuilder;

  @override
  Widget build(BuildContext context) {
    if (trips.isEmpty) {
      return SliverToBoxAdapter(
        child: _TripBoardEmptyState(
          emoji: '🔍',
          title: emptyTitle,
          actionLabel: emptyActionLabel,
          onActionTap: onEmptyActionTap,
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final trip = trips[index];
        return Padding(
          padding: EdgeInsets.only(bottom: index == trips.length - 1 ? 0 : 12),
          child: _TripBoardTripTile(
            trip: trip,
            buttonLabel: buttonLabelBuilder(trip),
            onPreviewTap: () => onPreviewTap(trip),
            onWhatsAppTap: () => onWhatsAppTap(trip),
          ),
        );
      }, childCount: trips.length),
    );
  }
}

class _DriverReturnTripsSliver extends StatelessWidget {
  const _DriverReturnTripsSliver({
    required this.trips,
    required this.onEmptyActionTap,
    required this.onPreviewTap,
    required this.onWhatsAppTap,
  });

  final List<Trip> trips;
  final VoidCallback onEmptyActionTap;
  final ValueChanged<Trip> onPreviewTap;
  final ValueChanged<Trip> onWhatsAppTap;

  @override
  Widget build(BuildContext context) {
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.purple.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.purple.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🔁 Driver Return Trips',
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.purple,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Drivers sharing return trips so riders can join existing routes.',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: AppColors.text2,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        if (trips.isEmpty)
          SliverToBoxAdapter(
            child: _TripBoardEmptyState(
              emoji: '🔁',
              title: 'No return trips available',
              subtitle:
                  'Try another vehicle type or post your own trip to start matching.',
              actionLabel: 'Post Your Trip',
              onActionTap: onEmptyActionTap,
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final trip = trips[index];
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index == trips.length - 1 ? 0 : 12,
                ),
                child: _TripBoardTripTile(
                  trip: trip,
                  buttonLabel: _hasContactPhone(trip)
                      ? 'Contact Driver'
                      : 'No contact yet',
                  onPreviewTap: () => onPreviewTap(trip),
                  onWhatsAppTap: () => onWhatsAppTap(trip),
                ),
              );
            }, childCount: trips.length),
          ),
      ],
    );
  }
}

class _TripBoardTripTile extends StatelessWidget {
  const _TripBoardTripTile({
    required this.trip,
    required this.buttonLabel,
    required this.onPreviewTap,
    required this.onWhatsAppTap,
  });

  final Trip trip;
  final String buttonLabel;
  final VoidCallback onPreviewTap;
  final VoidCallback onWhatsAppTap;

  @override
  Widget build(BuildContext context) {
    final contactName = trip.contactName?.trim();
    final hasPinnedPickup = trip.latitude != null && trip.longitude != null;
    final hasRoutePreview =
        hasPinnedPickup &&
        trip.destinationLatitude != null &&
        trip.destinationLongitude != null;
    final distanceLabel = trip.distanceKm == null
        ? null
        : trip.distanceKm! < 1
        ? '${(trip.distanceKm! * 1000).round()} m away'
        : '${trip.distanceKm!.toStringAsFixed(1)} km away';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TripCard(
          fromLocation: trip.fromLocation,
          toLocation: trip.toLocation,
          departureTime: trip.departureTime,
          vehicleType: _displayVehicleType(trip.vehicleType),
          vehicleEmoji: _tripVehicleEmoji(trip),
          onTap: onPreviewTap,
          seats: trip.seats,
          isReturn: trip.isReturn,
          isRecurring: trip.isRecurring,
          isDriverReturnTrip: trip.isDriverReturnTrip,
        ),
        if (contactName != null && contactName.isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                const Icon(
                  Icons.person_outline_rounded,
                  size: 14,
                  color: AppColors.text3,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Posted by $contactName',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (distanceLabel != null)
                _TripMetaLabel(
                  icon: Icons.near_me_rounded,
                  label: distanceLabel,
                ),
              _TripMetaLabel(
                icon: hasRoutePreview
                    ? Icons.route_rounded
                    : hasPinnedPickup
                    ? Icons.location_on_outlined
                    : Icons.route_outlined,
                label: hasRoutePreview
                    ? 'Route preview'
                    : hasPinnedPickup
                    ? 'Pickup pinned'
                    : 'Text route',
              ),
              const _TripMetaLabel(
                icon: Icons.chat_bubble_outline_rounded,
                label: 'Agree on WhatsApp',
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        WaButton(label: buttonLabel, onTap: onWhatsAppTap),
      ],
    );
  }
}

class _TripMetaLabel extends StatelessWidget {
  const _TripMetaLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.text3),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.text2,
            ),
          ),
        ],
      ),
    );
  }
}

class _TripBoardEmptyState extends StatelessWidget {
  const _TripBoardEmptyState({
    required this.emoji,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onActionTap,
  });

  final String emoji;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onActionTap;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 34)),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text2,
                  height: 1.45,
                ),
              ),
            ],
            if (actionLabel != null && onActionTap != null) ...[
              const SizedBox(height: 18),
              SizedBox(
                width: 180,
                child: CoolButton(label: actionLabel!, onTap: onActionTap!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TripBoardLoadingState extends StatelessWidget {
  const _TripBoardLoadingState({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _TripBoardLocationStateCard extends StatelessWidget {
  const _TripBoardLocationStateCard({
    required this.locationState,
    required this.onEnableLocation,
    required this.onOpenAppSettings,
    required this.onOpenLocationSettings,
  });

  final MobilityLocationState locationState;
  final VoidCallback onEnableLocation;
  final VoidCallback onOpenAppSettings;
  final VoidCallback onOpenLocationSettings;

  @override
  Widget build(BuildContext context) {
    late final String emoji;
    late final String title;
    late final String subtitle;
    String? actionLabel;
    VoidCallback? action;

    switch (locationState.status) {
      case MobilityLocationStatus.checking:
      case MobilityLocationStatus.requesting:
      case MobilityLocationStatus.idle:
        emoji = '📡';
        title = 'Checking your location';
        subtitle = 'Nearby trip matching needs your current area.';
        break;
      case MobilityLocationStatus.needsPermission:
      case MobilityLocationStatus.denied:
        emoji = '📍';
        title = 'Enable location for nearby trips';
        subtitle =
            'You can still post and manage your own trips, but nearby matching needs location access.';
        actionLabel = 'Allow Location';
        action = onEnableLocation;
        break;
      case MobilityLocationStatus.deniedForever:
        emoji = '⚙️';
        title = 'Location is blocked in settings';
        subtitle =
            'Open app settings to allow location again for nearby trip discovery.';
        actionLabel = 'Open Settings';
        action = onOpenAppSettings;
        break;
      case MobilityLocationStatus.serviceDisabled:
        emoji = '🛰️';
        title = 'Turn on device location';
        subtitle =
            'Location services are off, so nearby trips cannot be calculated yet.';
        actionLabel = 'Turn On Location';
        action = onOpenLocationSettings;
        break;
      case MobilityLocationStatus.ready:
      case MobilityLocationStatus.approximateReady:
        emoji = '📍';
        title = 'Location ready';
        subtitle = 'Nearby trip matching is available.';
        break;
      case MobilityLocationStatus.error:
        emoji = '⚠️';
        title = 'Location could not be resolved';
        subtitle =
            locationState.error ??
            'Try refreshing or enable location again to load nearby trips.';
        actionLabel = 'Try Again';
        action = onEnableLocation;
        break;
    }

    return _TripBoardEmptyState(
      emoji: emoji,
      title: title,
      subtitle: subtitle,
      actionLabel: actionLabel,
      onActionTap: action,
    );
  }
}

class _MyTripTile extends StatelessWidget {
  const _MyTripTile({
    required this.trip,
    required this.onDelete,
    required this.onLongPress,
    required this.isBusy,
    this.onCancel,
  });

  final Trip trip;
  final VoidCallback? onCancel;
  final VoidCallback onDelete;
  final VoidCallback onLongPress;
  final bool isBusy;

  bool get _isExpired => trip.status == 'expired';
  bool get _isCancelled => trip.status == 'cancelled';
  bool get _isMatched => trip.status == 'matched';
  bool get _isPaused => trip.status.toUpperCase() == 'PAUSED';

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(
        trip.id ??
            '${trip.fromLocation}-${trip.departureTime.toIso8601String()}',
      ),
      direction: isBusy ? DismissDirection.none : DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.red.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          'Delete',
          style: GoogleFonts.dmSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.red,
          ),
        ),
      ),
      child: GestureDetector(
        onLongPress: isBusy ? null : onLongPress,
        child: Opacity(
          opacity: _isExpired || _isCancelled || _isPaused ? 0.58 : 1,
          child: CoolCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _tripVehicleEmoji(trip),
                      style: const TextStyle(fontSize: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${trip.fromLocation} → ${trip.toLocation}',
                            style: GoogleFonts.dmSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            DateFormat(
                              'EEE d MMM • HH:mm',
                            ).format(trip.departureTime),
                            style: GoogleFonts.dmSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppColors.text2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isBusy)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: AppColors.accent,
                        ),
                      )
                    else if (_isExpired)
                      const StatusBadge(
                        label: 'Expired',
                        bgColor: AppColors.surface3,
                        textColor: AppColors.text3,
                      )
                    else if (_isCancelled)
                      const StatusBadge(
                        label: 'Cancelled',
                        bgColor: AppColors.surface3,
                        textColor: AppColors.text3,
                      )
                    else if (_isPaused)
                      StatusBadge(
                        label: 'Paused',
                        bgColor: AppColors.orange.withValues(alpha: 0.15),
                        textColor: AppColors.orange,
                      )
                    else if (_isMatched)
                      const StatusBadge(
                        label: 'Matched',
                        bgColor: AppColors.blueGlow,
                        textColor: AppColors.blue,
                      )
                    else
                      GestureDetector(
                        onTap: onCancel,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.red.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.dmSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.red,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InfoPill(
                      label:
                          '${_tripVehicleEmoji(trip)} ${_displayVehicleType(trip.vehicleType)}',
                    ),
                    _InfoPill(
                      label: _isExpired || _isCancelled
                          ? 'Swipe or long-press to delete'
                          : 'Long-press for actions',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface3,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.text2,
        ),
      ),
    );
  }
}

class _VehicleFilter {
  const _VehicleFilter({required this.label, required this.value});

  final String label;
  final String value;
}

bool _isActiveTrip(Trip trip) {
  final s = trip.status.trim().toUpperCase();
  return s == 'OPEN' || s == 'MATCHED' || s == 'ACTIVE';
}

bool _isPausedTrip(Trip trip) => trip.status.trim().toUpperCase() == 'PAUSED';

bool _hasContactPhone(Trip trip) =>
    (trip.whatsappNumber?.trim().isNotEmpty ?? false) ||
    (trip.contactPhone?.trim().isNotEmpty ?? false);

String _tripVehicleEmoji(Trip trip) {
  final emoji = trip.vehicleEmoji?.trim();
  if (emoji != null && emoji.isNotEmpty) {
    return emoji;
  }

  switch (trip.vehicleType.trim().toLowerCase()) {
    case 'moto':
    case 'moto taxi':
      return '🛺';
    case 'cab':
      return '🚗';
    case 'truck':
      return '🚛';
    case 'liffan':
      return '🚐';
    default:
      return '🚗';
  }
}

String _displayVehicleType(String vehicleType) {
  switch (vehicleType.trim().toLowerCase()) {
    case 'moto':
      return 'Moto';
    case 'moto taxi':
      return 'Moto Taxi';
    case 'cab':
      return 'Cab';
    case 'truck':
      return 'Truck';
    case 'liffan':
      return 'Liffan';
    case 'any':
      return 'Any';
    default:
      return vehicleType;
  }
}
