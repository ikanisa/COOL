import 'dart:async';

import 'package:cool_app/features/mobility/models/trip.dart';
import 'package:cool_app/core/models/geo_point.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../auth/providers/auth_provider.dart';
import '../../../core/services/whatsapp_contact_service.dart';
import '../services/mobility_whatsapp_service.dart';
import '../../../shared/widgets/cool_toast.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../models/driver_info.dart';
import '../providers/driver_provider.dart';
import '../providers/mobility_location_provider.dart';
import '../providers/mobility_provider.dart';
import '../widgets/mobility_driver_widgets.dart';
import '../widgets/mobility_list_widgets.dart';
import '../widgets/mobility_listing_sheet.dart';
import '../widgets/mobility_map_widgets.dart';

class MobilityHomeScreen extends ConsumerStatefulWidget {
  const MobilityHomeScreen({super.key});

  @override
  ConsumerState<MobilityHomeScreen> createState() => _MobilityHomeScreenState();
}

class _MobilityHomeScreenState extends ConsumerState<MobilityHomeScreen> {
  late final ProviderSubscription<MobilityLocationState> _locationSubscription;
  late final MobilityLocationNotifier _locationNotifier;
  bool _showMap = false;

  @override
  void initState() {
    super.initState();
    _locationNotifier = ref.read(mobilityLocationProvider.notifier);
    _locationSubscription = ref.listenManual<MobilityLocationState>(
      mobilityLocationProvider,
      (previous, next) {
        if (!mounted) {
          return;
        }
        final notifier = ref.read(mobilityProvider.notifier);
        final nextPosition = next.position;
        if (next.hasLocation && nextPosition != null) {
          final driverNotifier = ref.read(driverProvider.notifier);
          final driverState = ref.read(driverProvider);
          final previousPosition = previous?.position;
          notifier.updateLocation(nextPosition);
          final shouldReload =
              previousPosition == null ||
              _distanceBetween(previousPosition, nextPosition) > 0.05 ||
              previous?.status != next.status;
          if (shouldReload) {
            if (driverState.profile?.isOnline == true) {
              unawaited(
                driverNotifier.syncOnlineLocation(
                  latitude: nextPosition.latitude,
                  longitude: nextPosition.longitude,
                ),
              );
            }
            unawaited(notifier.loadNearbyDrivers());
            unawaited(notifier.loadScheduledTrips());
          }
          return;
        }

        if (previous?.hasLocation == true && !next.hasLocation) {
          notifier.clearLocation();
        }
      },
    );

    Future.microtask(() async {
      await ref.read(driverProvider.notifier).loadDriverProfile();
      await _locationNotifier.bootstrap();
      await _locationNotifier.acquireTracking();
    });
  }

  @override
  void dispose() {
    _locationSubscription.close();
    unawaited(_locationNotifier.releaseTracking());
    super.dispose();
  }

  Future<void> _refreshNearbyDrivers() async {
    await _locationNotifier.refresh();

    final locationState = ref.read(mobilityLocationProvider);
    if (!locationState.hasLocation) {
      return;
    }

    final notifier = ref.read(mobilityProvider.notifier);
    await notifier.loadNearbyDrivers();
    await notifier.loadScheduledTrips();
  }

  void _showMarketplaceSnackBar(String message) {
    CoolToast.info(context, message);
  }

  Future<void> _openTripWhatsApp(Trip trip) async {
    final phoneNumber =
        trip.whatsappNumber?.trim() ?? trip.contactPhone?.trim() ?? '';
    if (phoneNumber.isEmpty) {
      _showMarketplaceSnackBar(
        'No WhatsApp contact available yet.',
      );
      return;
    }

    final message = MobilityWhatsAppService.buildTripInquiryMessage(
      trip: trip,
      requester: ref.read(currentUserProvider),
    );

    await WhatsAppContactService.openChat(
      context,
      phoneNumber: phoneNumber,
      message: message,
    );
  }

  Future<void> _openDriverWhatsApp(DriverInfo driver) async {
    final phoneNumber = driver.contactPhone?.trim() ?? '';
    if (phoneNumber.isEmpty) {
      _showMarketplaceSnackBar(
        'No WhatsApp contact available yet.',
      );
      return;
    }

    final message = MobilityWhatsAppService.buildDriverInquiryMessage(
      driver: driver,
      requester: ref.read(currentUserProvider),
    );

    await WhatsAppContactService.openChat(
      context,
      phoneNumber: phoneNumber,
      message: message,
    );
  }

  Future<void> _showTripPreview(Trip trip) {
    return showTripListingSheet(
      context,
      trip: trip,
      buttonLabel: _hasTripContact(trip)
          ? 'Chat on WhatsApp'
          : 'No contact yet',
      onOpenWhatsApp: _hasTripContact(trip)
          ? () {
              unawaited(_openTripWhatsApp(trip));
            }
          : null,
    );
  }

  Future<void> _showDriverPreview(DriverInfo driver) {
    return showDriverListingSheet(
      context,
      driver: driver,
      buttonLabel: _hasDriverContact(driver)
          ? 'Chat on WhatsApp'
          : 'No contact yet',
      onOpenWhatsApp: _hasDriverContact(driver)
          ? () {
              unawaited(_openDriverWhatsApp(driver));
            }
          : null,
    );
  }

  double _distanceBetween(GeoPoint a, GeoPoint b) {
    return a.distanceToKm(b);
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final driverProfile = ref.watch(
      driverProvider.select((state) => state.profile),
    );
    final activeTab = ref.watch(mobilityActiveTabProvider);
    final isDriver = (currentUser?.isDriver ?? false) || driverProfile != null;
    final driverIsOnline = driverProfile?.isOnline ?? false;
    final driverVehicleType =
        driverProfile?.vehicleType ?? currentUser?.vehicleType ?? 'Driver';

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          'Mobility',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
      ),
      body: CoolScreenBackground(
        child: RefreshIndicator(
          color: AppColors.accent,
          backgroundColor: AppColors.surface2,
          onRefresh: _refreshNearbyDrivers,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(18, isDriver ? 8 : 16, 18, 0),
                sliver: SliverToBoxAdapter(
                  child: MobilityTopActionsCard(
                    isDriver: isDriver,
                    onOpenTrips: () => context.push('/mobility/trips'),
                    onScheduleTrip: () => context.push('/mobility/schedule'),
                    onOpenDriverTools: isDriver
                        ? () => context.push('/mobility/driver')
                        : null,
                  ),
                ),
              ),
              if (isDriver)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                  sliver: SliverToBoxAdapter(
                    child: MobilityDriverStatusSection(
                      isOnline: driverIsOnline,
                      vehicleType: driverVehicleType,
                      onChanged: _handleDriverStatusToggle,
                    ),
                  ),
                ),
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(18, 18, 18, 0),
                sliver: SliverToBoxAdapter(
                  child: MobilityBrowseControlsCard(),
                ),
              ),
              MobilityContentSliver(
                onDriverPreviewTap: (driver) {
                  unawaited(_showDriverPreview(driver));
                },
                onDriverWhatsAppTap: (driver) {
                  unawaited(_openDriverWhatsApp(driver));
                },
                onTripPreviewTap: (trip) {
                  unawaited(_showTripPreview(trip));
                },
              ),
              if (activeTab == 0) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                  sliver: SliverToBoxAdapter(
                    child: MobilityMapToggleCard(
                      isExpanded: _showMap,
                      onTap: () {
                        setState(() => _showMap = !_showMap);
                      },
                    ),
                  ),
                ),
                if (_showMap)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                    sliver: SliverToBoxAdapter(
                      child: MobilityMapSection(
                        onDriverTap: (driver) {
                          unawaited(_showDriverPreview(driver));
                        },
                      ),
                    ),
                  ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleDriverStatusToggle(bool value) async {
    final position =
        ref.read(mobilityLocationProvider).position ??
        ref.read(mobilityUserLocationProvider);
    if (position == null) {
      CoolToast.error(
        context,
        'Location is required before turning on driver mode.',
      );
      return;
    }

    await ref
        .read(driverProvider.notifier)
        .setOnlineStatus(
          isOnline: value,
          latitude: position.latitude,
          longitude: position.longitude,
        );
    await ref.read(mobilityProvider.notifier).loadNearbyDrivers();
  }
}

bool _hasTripContact(Trip trip) =>
    (trip.whatsappNumber?.trim().isNotEmpty ?? false) ||
    (trip.contactPhone?.trim().isNotEmpty ?? false);

bool _hasDriverContact(DriverInfo driver) =>
    driver.contactPhone?.trim().isNotEmpty ?? false;
