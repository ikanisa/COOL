import 'dart:async';

import 'package:cool_app/features/mobility/models/trip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../auth/providers/auth_provider.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/services/whatsapp_contact_service.dart';
import '../services/mobility_whatsapp_service.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/cool_layout.dart';
import '../../../core/theme/cool_palette.dart';
import '../../../shared/widgets/cool_google_map.dart';
import '../../../shared/widgets/cool_toast.dart';

import '../../../shared/widgets/cool_screen_background.dart';
import '../models/driver_info.dart';
import '../providers/discovery_provider.dart';
import '../widgets/mobility_listing_sheet.dart';
import '../providers/driver_provider.dart';
import '../providers/mobility_location_provider.dart';
import '../widgets/mobility_list_widgets.dart';

class MobilityHomeScreen extends ConsumerStatefulWidget {
  const MobilityHomeScreen({super.key});

  @override
  ConsumerState<MobilityHomeScreen> createState() => _MobilityHomeScreenState();
}

class _MobilityHomeScreenState extends ConsumerState<MobilityHomeScreen> {
  late final MobilityLocationNotifier _locationNotifier;
  GoogleMapController? _mapController;

  @override
  void initState() {
    super.initState();
    _locationNotifier = ref.read(mobilityLocationProvider.notifier);

    Future.microtask(() async {
      await ref.read(driverProvider.notifier).loadDriverProfile();
      await _locationNotifier.bootstrap();
      await _locationNotifier.acquireTracking();
    });
  }

  @override
  void dispose() {
    unawaited(_locationNotifier.releaseTracking());
    _mapController = null;
    super.dispose();
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  void _recenterMap() {
    final pos = ref.read(mobilityLocationProvider).position;
    if (pos != null && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)),
      );
    }
  }

  Set<Marker> _buildDriverMarkers(List<DriverInfo> drivers) {
    final markers = <Marker>{};
    for (final driver in drivers) {
      if (driver.latitude == null || driver.longitude == null) continue;
      markers.add(
        Marker(
          markerId: MarkerId('driver_${driver.driverId}'),
          position: LatLng(driver.latitude!, driver.longitude!),
          infoWindow: InfoWindow(
            title: driver.displayName ?? 'Driver',
            snippet: driver.vehicleType,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            _vehicleTypeHue(driver.vehicleType),
          ),
        ),
      );
    }
    return markers;
  }

  static double _vehicleTypeHue(String? type) {
    switch (type?.toLowerCase()) {
      case 'moto':
        return BitmapDescriptor.hueGreen;
      case 'cab':
        return BitmapDescriptor.hueAzure;
      case 'truck':
        return BitmapDescriptor.hueOrange;
      case 'trike':
        return BitmapDescriptor.hueViolet;
      default:
        return BitmapDescriptor.hueRed;
    }
  }

  Future<void> _refreshNearby() async {
    await _locationNotifier.refresh();
    await ref.read(discoveryProvider.notifier).refresh();
  }

  void _showMarketplaceSnackBar(String message) {
    CoolToast.info(context, message);
  }

  Future<void> _openTripWhatsApp(Trip trip) async {
    final l10n = context.l10n;
    final phoneNumber =
        trip.whatsappNumber?.trim() ?? trip.contactPhone?.trim() ?? '';
    if (phoneNumber.isEmpty) {
      _showMarketplaceSnackBar(l10n.mobilityNoWhatsappAvailable);
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
    final l10n = context.l10n;
    final phoneNumber = driver.contactPhone?.trim() ?? '';
    if (phoneNumber.isEmpty) {
      _showMarketplaceSnackBar(l10n.mobilityNoWhatsappAvailable);
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
    final l10n = context.l10n;
    return showTripListingSheet(
      context,
      trip: trip,
      buttonLabel: _hasTripContact(trip)
          ? l10n.contactViaWhatsapp
          : l10n.mobilityNoContactYet,
      onOpenWhatsApp: _hasTripContact(trip)
          ? () {
              unawaited(_openTripWhatsApp(trip));
            }
          : null,
    );
  }

  Future<void> _showDriverPreview(DriverInfo driver) {
    final l10n = context.l10n;
    return showDriverListingSheet(
      context,
      driver: driver,
      buttonLabel: _hasDriverContact(driver)
          ? l10n.contactViaWhatsapp
          : l10n.mobilityNoContactYet,
      onOpenWhatsApp: _hasDriverContact(driver)
          ? () {
              unawaited(_openDriverWhatsApp(driver));
            }
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.coolPalette;
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final currentUser = ref.watch(currentUserProvider);
    final driverProfile = ref.watch(
      driverProvider.select((state) => state.profile),
    );
    final isDriver = (currentUser?.isDriver ?? false) || driverProfile != null;

    return Scaffold(
      backgroundColor: colors.appBackground,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          tooltip: context.l10n.back,
          icon: Icon(Icons.arrow_back_rounded, color: colors.primaryText),
        ),
      ),
      body: CoolScreenBackground(
        child: RefreshIndicator(
          color: colors.accent,
          backgroundColor: colors.cardSurfaceStrong,
          onRefresh: _refreshNearby,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: CoolLayout.rootPagePadding.copyWith(bottom: 0, top: 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.navMobility,
                        style: theme.textTheme.displayLarge?.copyWith(
                          color: colors.primaryText,
                        ),
                      ),
                      const SizedBox(height: CoolSpace.x2),
                      Text(
                        'Routes, nearby drivers, and direct action handoff with immediate clarity.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.secondaryText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Google Map ──────────────────────────────────────
              SliverPadding(
                padding: EdgeInsets.symmetric(
                  horizontal: CoolLayout.horizontalPagePadding,
                  vertical: 10,
                ),
                sliver: SliverToBoxAdapter(
                  child: _MobilityMapSection(
                    onMapCreated: _onMapCreated,
                    onRecenter: _recenterMap,
                    driverMarkers: _buildDriverMarkers(
                      ref.watch(
                        discoveryProvider.select((s) => s.nearbyDrivers),
                      ),
                    ),
                  ),
                ),
              ),

              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  CoolLayout.horizontalPagePadding,
                  isDriver ? 0 : 8,
                  CoolLayout.horizontalPagePadding,
                  0,
                ),
                sliver: SliverToBoxAdapter(
                  child: MobilityTopActionsCard(
                    isDriver: isDriver,
                    onScheduleTrip: () =>
                        context.push(AppRoutes.mobilitySchedule),
                  ),
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
              const SliverToBoxAdapter(
                child: SizedBox(height: CoolLayout.rootBottomClearance),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _hasTripContact(Trip trip) =>
    (trip.whatsappNumber?.trim().isNotEmpty ?? false) ||
    (trip.contactPhone?.trim().isNotEmpty ?? false);

bool _hasDriverContact(DriverInfo driver) =>
    driver.contactPhone?.trim().isNotEmpty ?? false;

// ═══════════════════════════════════════════════════════════════════════════════
// MAP SECTION WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

class _MobilityMapSection extends ConsumerWidget {
  const _MobilityMapSection({
    required this.onMapCreated,
    required this.onRecenter,
    required this.driverMarkers,
  });

  final void Function(GoogleMapController) onMapCreated;
  final VoidCallback onRecenter;
  final Set<Marker> driverMarkers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.coolPalette;
    final locationState = ref.watch(mobilityLocationProvider);
    final userPos = locationState.position;

    final target = userPos != null
        ? LatLng(userPos.latitude, userPos.longitude)
        : null;

    return SizedBox(
      height: 200,
      child: Stack(
        children: [
          CoolGoogleMap(
            initialTarget: target,
            initialZoom: 14.0,
            markers: driverMarkers,
            myLocationEnabled: locationState.hasLocation,
            myLocationButtonEnabled: false,
            onMapCreated: onMapCreated,
          ),

          // Recenter FAB
          if (userPos != null)
            Positioned(
              right: 12,
              bottom: 12,
              child: Material(
                color: palette.surface,
                elevation: 4,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: onRecenter,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(
                      Icons.my_location_rounded,
                      color: palette.accent,
                      size: 22,
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
