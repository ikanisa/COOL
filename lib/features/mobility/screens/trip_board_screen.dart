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
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/trip_card.dart';
import '../../../shared/widgets/vehicle_chip.dart';
import '../../../shared/widgets/wa_button.dart';
import '../providers/mobility_location_provider.dart';
import '../providers/trip_board_provider.dart';
import '../services/mobility_whatsapp_service.dart';
import '../widgets/mobility_listing_sheet.dart';

enum _TripBoardViewMode { explore, myTrips }

class TripBoardScreen extends ConsumerStatefulWidget {
  const TripBoardScreen({super.key});

  @override
  ConsumerState<TripBoardScreen> createState() => _TripBoardScreenState();
}

class _TripBoardScreenState extends ConsumerState<TripBoardScreen> {
  late final ProviderSubscription<MobilityLocationState> _locationSubscription;
  late final MobilityLocationNotifier _locationNotifier;
  _TripBoardViewMode _activeView = _TripBoardViewMode.explore;

  @override
  void initState() {
    super.initState();
    _locationNotifier = ref.read(mobilityLocationProvider.notifier);
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
    unawaited(_locationNotifier.releaseTracking());
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _locationNotifier.bootstrap();
    await _locationNotifier.acquireTracking();

    ref
        .read(tripBoardProvider.notifier)
        .updateLocation(ref.read(mobilityLocationProvider).position);

    await ref.read(tripBoardProvider.notifier).refresh();
  }

  Future<void> _refreshTrips() async {
    await _locationNotifier.refresh();
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
    CoolToast.info(context, message);
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
          'Trip board',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.accent,
        backgroundColor: AppColors.surface,
        onRefresh: _refreshTrips,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              sliver: SliverToBoxAdapter(
                child: _TripBoardModeSwitcher(
                  activeView: _activeView,
                  onChanged: (view) {
                    setState(() => _activeView = view);
                  },
                ),
              ),
            ),
            if (_activeView == _TripBoardViewMode.explore) ...[
              SliverPadding(
                padding: EdgeInsets.fromLTRB(18, 14, 18, 0),
                sliver: SliverToBoxAdapter(
                  child: _TripBoardExploreHeaderCard(
                    onPostTrip: () => context.push('/mobility/schedule'),
                  ),
                ),
              ),
              _TripBoardPublicTripsSliver(
                onPreviewTap: (trip) {
                  unawaited(_showTripPreview(trip));
                },
                onWhatsAppTap: (trip) {
                  unawaited(_openWhatsApp(trip));
                },
              ),
            ] else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                sliver: SliverToBoxAdapter(
                  child: _TripBoardMyTripsHeaderCard(
                    onPostTrip: () => context.push('/mobility/schedule'),
                  ),
                ),
              ),
              _TripBoardMyTripsSliver(
                onShowActions: (trip) {
                  unawaited(_showTripActions(trip));
                },
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      ),
    );
  }

  static const _vehicleFilters = [
    _VehicleFilter(label: 'All', value: 'All'),
    _VehicleFilter(label: 'Moto', value: 'Moto'),
    _VehicleFilter(label: 'Cab', value: 'Cab'),
    _VehicleFilter(label: 'Truck', value: 'Truck'),
    _VehicleFilter(label: 'Liffan', value: 'Liffan'),
  ];
}

class _TripBoardHeaderCard extends StatelessWidget {
  const _TripBoardHeaderCard({
    required this.title,
    required this.subtitle,
    required this.primaryLabel,
    required this.onPrimaryTap,
    this.child,
  });

  final String title;
  final String subtitle;
  final String primaryLabel;
  final VoidCallback onPrimaryTap;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppColors.text2,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: CoolButton(label: primaryLabel, onTap: onPrimaryTap),
          ),
          if (child != null) ...[
            const SizedBox(height: 16),
            child!,
          ],
        ],
      ),
    );
  }
}

class _TripBoardExploreHeaderCard extends ConsumerWidget {
  const _TripBoardExploreHeaderCard({required this.onPostTrip});

  final VoidCallback onPostTrip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTab = ref.watch(tripBoardActiveTabProvider);
    final title = activeTab == TripBoardTab.driverReturnTrips
        ? 'Driver return trips'
        : 'Explore trips';
    final subtitle = activeTab == TripBoardTab.driverReturnTrips
        ? 'Browse return routes from drivers heading back.'
        : 'Find a nearby ride, then continue on WhatsApp if it fits.';

    return _TripBoardHeaderCard(
      title: title,
      subtitle: subtitle,
      primaryLabel: 'Post trip',
      onPrimaryTap: onPostTrip,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TripBoardTabSection(),
          SizedBox(height: 12),
          _TripBoardFilterBar(),
        ],
      ),
    );
  }
}

class _TripBoardMyTripsHeaderCard extends StatelessWidget {
  const _TripBoardMyTripsHeaderCard({required this.onPostTrip});

  final VoidCallback onPostTrip;

  @override
  Widget build(BuildContext context) {
    return _TripBoardHeaderCard(
      title: 'Manage your trips',
      subtitle: 'Pause, repost, or delete what you already posted.',
      primaryLabel: 'Post trip',
      onPrimaryTap: onPostTrip,
    );
  }
}

class _TripBoardModeSwitcher extends StatelessWidget {
  const _TripBoardModeSwitcher({
    required this.activeView,
    required this.onChanged,
  });

  final _TripBoardViewMode activeView;
  final ValueChanged<_TripBoardViewMode> onChanged;

  static const _items = [
    (_TripBoardViewMode.explore, 'Explore'),
    (_TripBoardViewMode.myTrips, 'My trips'),
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
          for (final item in _items)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(item.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: activeView == item.$1
                        ? AppColors.accent
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    item.$2,
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: activeView == item.$1
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

class _TripBoardTabSwitcher extends StatelessWidget {
  const _TripBoardTabSwitcher({
    required this.activeTab,
    required this.onChanged,
  });

  final TripBoardTab activeTab;
  final ValueChanged<TripBoardTab> onChanged;

  static const _tabs = [
    (TripBoardTab.passengerTrips, 'Passenger'),
    (TripBoardTab.driverReturnTrips, 'Return trips'),
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
    required this.onPreviewTap,
    required this.onWhatsAppTap,
  });

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
            subtitle: 'Searching nearby…',
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
            icon: Icons.warning_amber_rounded,
            title: 'Could not load nearby trips',
            subtitle: error,
          ),
        ),
      );
    }

    if (activeTab == TripBoardTab.driverReturnTrips) {
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
        sliver: _DriverReturnTripsSliver(
          trips: trips,
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
        onPreviewTap: onPreviewTap,
        onWhatsAppTap: onWhatsAppTap,
        buttonLabelBuilder: (trip) =>
            _hasContactPhone(trip) ? 'Join on WhatsApp' : 'No contact yet',
      ),
    );
  }
}

class _TripBoardMyTripsSliver extends ConsumerWidget {
  const _TripBoardMyTripsSliver({required this.onShowActions});

  final ValueChanged<Trip> onShowActions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myTrips = ref.watch(tripBoardMyTripsProvider);
    final isLoading = ref.watch(tripBoardMyTripsLoadingProvider);
    final actionTripId = ref.watch(tripBoardActionTripIdProvider);
    final error = ref.watch(tripBoardMyTripsErrorProvider);

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
      sliver: SliverMainAxisGroup(
        slivers: [
          if (isLoading && myTrips.isEmpty)
            const SliverToBoxAdapter(
              child: _TripBoardLoadingState(
                title: 'Loading your trips',
                subtitle: 'Loading your trips…',
              ),
            )
          else if (error != null && myTrips.isEmpty)
            SliverToBoxAdapter(
              child: _TripBoardEmptyState(
                icon: Icons.warning_amber_rounded,
                title: 'Could not load your trips',
                subtitle: error,
              ),
            )
          else if (myTrips.isEmpty)
            const SliverToBoxAdapter(
              child: _TripBoardEmptyState(
                icon: Icons.folder_open_rounded,
                title: 'No trips posted yet',
                subtitle: 'Post a trip to see it here.',
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
                    onShowActions: () => onShowActions(trip),
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
    required this.onPreviewTap,
    required this.onWhatsAppTap,
    required this.buttonLabelBuilder,
  });

  final List<Trip> trips;
  final String emptyTitle;
  final ValueChanged<Trip> onPreviewTap;
  final ValueChanged<Trip> onWhatsAppTap;
  final String Function(Trip trip) buttonLabelBuilder;

  @override
  Widget build(BuildContext context) {
    if (trips.isEmpty) {
      return SliverToBoxAdapter(
        child: _TripBoardEmptyState(
          icon: Icons.search_rounded,
          title: emptyTitle,
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
    required this.onPreviewTap,
    required this.onWhatsAppTap,
  });

  final List<Trip> trips;
  final ValueChanged<Trip> onPreviewTap;
  final ValueChanged<Trip> onWhatsAppTap;

  @override
  Widget build(BuildContext context) {
    return SliverMainAxisGroup(
      slivers: [
        if (trips.isEmpty)
          SliverToBoxAdapter(
            child: _TripBoardEmptyState(
              icon: Icons.repeat_rounded,
              title: 'No return trips available',
              subtitle: 'Try another vehicle type or post a trip.',
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

          onTap: onPreviewTap,
          seats: trip.seats,
          isReturn: trip.isReturn,
          isRecurring: trip.isRecurring,
          isDriverReturnTrip: trip.isDriverReturnTrip,
        ),
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
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onActionTap,
  });

  final IconData icon;
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
            Icon(icon, size: 34, color: AppColors.text2),
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
    late final IconData icon;
    late final String title;
    late final String subtitle;
    String? actionLabel;
    VoidCallback? action;

    switch (locationState.status) {
      case MobilityLocationStatus.checking:
      case MobilityLocationStatus.requesting:
      case MobilityLocationStatus.idle:
        icon = Icons.satellite_alt_rounded;
        title = 'Checking your location';
        subtitle = 'Nearby trip matching needs your current area.';
        break;
      case MobilityLocationStatus.needsPermission:
      case MobilityLocationStatus.denied:
        icon = Icons.pin_drop_rounded;
        title = 'Enable location for nearby trips';
        subtitle =
            'You can still post and manage your own trips, but nearby matching needs location access.';
        actionLabel = 'Allow Location';
        action = onEnableLocation;
        break;
      case MobilityLocationStatus.deniedForever:
        icon = Icons.settings_rounded;
        title = 'Location is blocked in settings';
        subtitle =
            'Open app settings to allow location again for nearby trip discovery.';
        actionLabel = 'Open Settings';
        action = onOpenAppSettings;
        break;
      case MobilityLocationStatus.serviceDisabled:
        icon = Icons.satellite_alt_rounded;
        title = 'Turn on device location';
        subtitle =
            'Location services are off, so nearby trips cannot be calculated yet.';
        actionLabel = 'Turn On Location';
        action = onOpenLocationSettings;
        break;
      case MobilityLocationStatus.ready:
      case MobilityLocationStatus.approximateReady:
        icon = Icons.pin_drop_rounded;
        title = 'Location ready';
        subtitle = 'Nearby trip matching is available.';
        break;
      case MobilityLocationStatus.error:
        icon = Icons.warning_amber_rounded;
        title = 'Location could not be resolved';
        subtitle =
            locationState.error ??
            'Try refreshing or enable location again to load nearby trips.';
        actionLabel = 'Try Again';
        action = onEnableLocation;
        break;
    }

    return _TripBoardEmptyState(
      icon: icon,
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
    required this.onShowActions,
    required this.isBusy,
  });

  final Trip trip;
  final VoidCallback onShowActions;
  final bool isBusy;

  bool get _isExpired => trip.status == 'expired';
  bool get _isCancelled => trip.status == 'cancelled';
  bool get _isMatched => trip.status == 'matched';
  bool get _isPaused => trip.status.toUpperCase() == 'PAUSED';

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: _isExpired || _isCancelled || _isPaused ? 0.58 : 1,
      child: CoolCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _vehicleIconForType(trip.vehicleType),
                  size: 22,
                  color: AppColors.accent,
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
                else
                  IconButton(
                    onPressed: onShowActions,
                    tooltip: 'Trip actions',
                    icon: const Icon(
                      Icons.more_horiz_rounded,
                      color: AppColors.text2,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _InfoPill(
                    label: _displayVehicleType(trip.vehicleType),
                  ),
                ),
                const SizedBox(width: 8),
                _MyTripStatusBadge(
                  isExpired: _isExpired,
                  isCancelled: _isCancelled,
                  isPaused: _isPaused,
                  isMatched: _isMatched,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MyTripStatusBadge extends StatelessWidget {
  const _MyTripStatusBadge({
    required this.isExpired,
    required this.isCancelled,
    required this.isPaused,
    required this.isMatched,
  });

  final bool isExpired;
  final bool isCancelled;
  final bool isPaused;
  final bool isMatched;

  @override
  Widget build(BuildContext context) {
    if (isExpired) {
      return const StatusBadge(
        label: 'Expired',
        bgColor: AppColors.surface3,
        textColor: AppColors.text3,
      );
    }
    if (isCancelled) {
      return const StatusBadge(
        label: 'Cancelled',
        bgColor: AppColors.surface3,
        textColor: AppColors.text3,
      );
    }
    if (isPaused) {
      return StatusBadge(
        label: 'Paused',
        bgColor: AppColors.orange.withValues(alpha: 0.15),
        textColor: AppColors.orange,
      );
    }
    if (isMatched) {
      return const StatusBadge(
        label: 'Matched',
        bgColor: AppColors.blueGlow,
        textColor: AppColors.blue,
      );
    }
    return const StatusBadge(
      label: 'Active',
      bgColor: AppColors.accentGlow,
      textColor: AppColors.accent,
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

IconData _vehicleIconForType(String vehicleType) {
  final normalized = vehicleType.trim().toLowerCase();
  if (normalized.contains('moto')) return Icons.two_wheeler_rounded;
  if (normalized.contains('cab')) return Icons.directions_car_rounded;
  if (normalized.contains('truck')) return Icons.local_shipping_rounded;
  if (normalized.contains('liffan') || normalized.contains('van')) {
    return Icons.airport_shuttle_rounded;
  }
  return Icons.directions_car_filled_rounded;
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
