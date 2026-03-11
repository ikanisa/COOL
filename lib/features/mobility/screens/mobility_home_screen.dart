import 'dart:async';

import 'package:cool_app/features/mobility/models/trip.dart';
import 'package:cool_app/core/models/geo_point.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;

import '../../auth/providers/auth_provider.dart';
import '../../../core/config/env_config.dart';
import '../../../core/services/whatsapp_contact_service.dart';
import '../services/mobility_whatsapp_service.dart';
import '../../../shared/widgets/cool_skeleton.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/driver_card.dart';
import '../../../shared/widgets/trip_card.dart';
import '../../../shared/widgets/vehicle_chip.dart';
import '../models/driver_info.dart';
import '../providers/driver_provider.dart';
import '../providers/mobility_location_provider.dart';
import '../providers/mobility_provider.dart';
import '../providers/vehicle_type_provider.dart';
import '../widgets/mobility_listing_sheet.dart';

const _defaultMapCenter = GeoPoint(latitude: -1.9441, longitude: 30.0619);

const _fallbackVehicleFilters = [
  _VehicleFilter(label: 'All', value: 'All'),
  _VehicleFilter(label: '🛺 Moto', value: 'Moto'),
  _VehicleFilter(label: '🚗 Cab', value: 'Cab'),
  _VehicleFilter(label: '🚛 Truck', value: 'Truck'),
  _VehicleFilter(label: '🚐 Liffan', value: 'Liffan'),
];

final mobilityVehicleFiltersProvider = Provider<List<_VehicleFilter>>((ref) {
  final country = ref.watch(
    authProvider.select((state) => state.user?.country),
  );
  final typesAsync = ref.watch(vehicleTypesProvider(country));
  return typesAsync.when(
    data: (types) => types
        .map((type) => _VehicleFilter(label: type.label, value: type.value))
        .toList(growable: false),
    loading: () => _fallbackVehicleFilters,
    error: (_, _) => _fallbackVehicleFilters,
  );
});

class MobilityHomeScreen extends ConsumerStatefulWidget {
  const MobilityHomeScreen({super.key});

  @override
  ConsumerState<MobilityHomeScreen> createState() => _MobilityHomeScreenState();
}

class _MobilityHomeScreenState extends ConsumerState<MobilityHomeScreen> {
  late final ProviderSubscription<MobilityLocationState> _locationSubscription;

  @override
  void initState() {
    super.initState();
    _locationSubscription = ref.listenManual<MobilityLocationState>(
      mobilityLocationProvider,
      (previous, next) {
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
      final locationNotifier = ref.read(mobilityLocationProvider.notifier);
      await locationNotifier.bootstrap();
      await locationNotifier.acquireTracking();
    });
  }

  @override
  void dispose() {
    _locationSubscription.close();
    unawaited(ref.read(mobilityLocationProvider.notifier).releaseTracking());
    super.dispose();
  }

  Future<void> _refreshNearbyDrivers() async {
    final locationNotifier = ref.read(mobilityLocationProvider.notifier);
    await locationNotifier.refresh();

    final locationState = ref.read(mobilityLocationProvider);
    if (!locationState.hasLocation) {
      return;
    }

    final notifier = ref.read(mobilityProvider.notifier);
    await notifier.loadNearbyDrivers();
    await notifier.loadScheduledTrips();
  }

  void _showMarketplaceSnackBar(String message) {
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

  Future<void> _openTripWhatsApp(Trip trip) async {
    final phoneNumber =
        trip.whatsappNumber?.trim() ?? trip.contactPhone?.trim() ?? '';
    if (phoneNumber.isEmpty) {
      _showMarketplaceSnackBar(
        'WhatsApp contact is not available for this trip yet.',
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
        'WhatsApp contact is not available for this driver yet.',
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
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(18, 8, 18, 0),
                sliver: SliverToBoxAdapter(child: _MobilityDiscoveryFeedback()),
              ),
              if (isDriver)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                  sliver: SliverToBoxAdapter(
                    child: _DriverStatusSection(
                      isOnline: driverIsOnline,
                      vehicleType: driverVehicleType,
                      onChanged: _handleDriverStatusToggle,
                    ),
                  ),
                ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(18, isDriver ? 0 : 16, 18, 0),
                sliver: SliverToBoxAdapter(
                  child: _MobilityMapSection(
                    onDriverTap: (driver) {
                      unawaited(_showDriverPreview(driver));
                    },
                  ),
                ),
              ),
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(18, 16, 18, 0),
                sliver: SliverToBoxAdapter(child: _MobilityFilterBar()),
              ),
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(18, 18, 18, 0),
                sliver: SliverToBoxAdapter(child: _MobilityTabSection()),
              ),
              _MobilityContentSliver(
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
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 96),
                sliver: SliverToBoxAdapter(
                  child: CoolButton(
                    label: '📅 Schedule a Trip',
                    onTap: () => context.push('/mobility/schedule'),
                  ),
                ),
              ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location is required before turning on driver mode.'),
        ),
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

class _DriverToggleCard extends StatelessWidget {
  const _DriverToggleCard({
    required this.isOnline,
    required this.vehicleEmoji,
    required this.vehicleType,
    required this.onChanged,
  });

  final bool isOnline;
  final String vehicleEmoji;
  final String vehicleType;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      child: Row(
        children: [
          Text(vehicleEmoji, style: const TextStyle(fontSize: 28)),
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
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  vehicleType,
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: AppColors.text2,
                  ),
                ),
              ],
            ),
          ),
          _DriverModeToggle(value: isOnline, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _DriverModeToggle extends StatelessWidget {
  const _DriverModeToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 52,
        height: 28,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value ? AppColors.accent : AppColors.surface3,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class _OnlineStatusBanner extends StatelessWidget {
  const _OnlineStatusBanner({required this.isOnline});

  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Container(
        key: ValueKey(isOnline),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isOnline ? AppColors.accentGlow : AppColors.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isOnline ? AppColors.accent : AppColors.border,
          ),
        ),
        child: Text(
          isOnline
              ? '● You are ONLINE — visible to nearby passengers'
              : '○ You are OFFLINE',
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isOnline ? AppColors.accent : AppColors.text2,
          ),
        ),
      ),
    );
  }
}

class _DriverStatusSection extends StatelessWidget {
  const _DriverStatusSection({
    required this.isOnline,
    required this.vehicleType,
    required this.onChanged,
  });

  final bool isOnline;
  final String vehicleType;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _DriverToggleCard(
          isOnline: isOnline,
          vehicleEmoji: _vehicleEmoji(vehicleType),
          vehicleType: vehicleType,
          onChanged: onChanged,
        ),
        const SizedBox(height: 10),
        _OnlineStatusBanner(isOnline: isOnline),
      ],
    );
  }
}

class _MobilityDiscoveryFeedback extends ConsumerWidget {
  const _MobilityDiscoveryFeedback();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoading = ref.watch(mobilityDiscoveryLoadingProvider);
    final error = ref.watch(mobilityDiscoveryErrorProvider);
    final drivers = ref.watch(mobilityNearbyDriversProvider);
    final locationState = ref.watch(mobilityLocationProvider);

    if (isLoading && drivers.isEmpty && locationState.hasLocation) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: CoolSkeletonList(itemCount: 2),
      );
    }

    if (error != null && drivers.isEmpty && locationState.hasLocation) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 30),
        child: Center(
          child: Text(
            error,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.red),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class _MobilityMapSection extends ConsumerWidget {
  const _MobilityMapSection({required this.onDriverTap});

  final ValueChanged<DriverInfo> onDriverTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationState = ref.watch(mobilityLocationProvider);
    final userLocation = ref.watch(mobilityUserLocationProvider);
    final drivers = ref.watch(mobilityNearbyDriversProvider);
    final center = locationState.position ?? userLocation ?? _defaultMapCenter;
    final notifier = ref.read(mobilityLocationProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RepaintBoundary(
          child: _MapBox(
            center: center,
            drivers: drivers,
            locationState: locationState,
            onDriverTap: onDriverTap,
            onRequestLocation: () {
              unawaited(notifier.requestForegroundAccess());
            },
            onOpenAppSettings: () {
              unawaited(notifier.openAppSettings());
            },
            onOpenLocationSettings: () {
              unawaited(notifier.openLocationSettings());
            },
          ),
        ),
        if (locationState.hasLocation &&
            (locationState.isApproximate || locationState.isStale)) ...[
          const SizedBox(height: 10),
          _LocationMetaBanner(locationState: locationState),
        ],
      ],
    );
  }
}

class _MobilityFilterBar extends ConsumerWidget {
  const _MobilityFilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedVehicle = ref.watch(mobilitySelectedVehicleProvider);
    final filters = ref.watch(mobilityVehicleFiltersProvider);
    final notifier = ref.read(mobilityProvider.notifier);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < filters.length; index++) ...[
            VehicleChip(
              label: filters[index].label,
              isSelected: selectedVehicle == filters[index].value,
              onTap: () {
                unawaited(notifier.setVehicleFilter(filters[index].value));
              },
            ),
            if (index != filters.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _MobilityTabSection extends ConsumerWidget {
  const _MobilityTabSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTab = ref.watch(mobilityActiveTabProvider);
    final notifier = ref.read(mobilityProvider.notifier);

    return _DualTabSwitcher(
      activeIndex: activeTab,
      onChanged: (index) {
        unawaited(notifier.setActiveTab(index));
      },
    );
  }
}

class _MobilityContentSliver extends ConsumerWidget {
  const _MobilityContentSliver({
    required this.onDriverPreviewTap,
    required this.onDriverWhatsAppTap,
    required this.onTripPreviewTap,
  });

  final ValueChanged<DriverInfo> onDriverPreviewTap;
  final ValueChanged<DriverInfo> onDriverWhatsAppTap;
  final ValueChanged<Trip> onTripPreviewTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTab = ref.watch(mobilityActiveTabProvider);
    return switch (activeTab) {
      0 => SliverPadding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
        sliver: _NearbyDriversSliver(
          drivers: ref.watch(mobilityNearbyDriversProvider),
          onPreviewTap: onDriverPreviewTap,
          onWhatsAppTap: onDriverWhatsAppTap,
        ),
      ),
      _ => SliverPadding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
        sliver: _ScheduledTripsSliver(
          trips: ref.watch(mobilityScheduledTripsProvider),
          onPreviewTap: onTripPreviewTap,
        ),
      ),
    };
  }
}

class _MapBox extends StatefulWidget {
  const _MapBox({
    required this.center,
    required this.drivers,
    required this.locationState,
    required this.onDriverTap,
    required this.onRequestLocation,
    required this.onOpenAppSettings,
    required this.onOpenLocationSettings,
  });

  final GeoPoint? center;
  final List<DriverInfo> drivers;
  final MobilityLocationState locationState;
  final ValueChanged<DriverInfo> onDriverTap;
  final VoidCallback onRequestLocation;
  final VoidCallback onOpenAppSettings;
  final VoidCallback onOpenLocationSettings;

  @override
  State<_MapBox> createState() => _MapBoxState();
}

class _MapBoxState extends State<_MapBox> {
  gmap.GoogleMapController? _controller;

  Future<void> _recenter() async {
    final center = widget.center;
    final controller = _controller;
    if (center == null || controller == null) {
      return;
    }

    await controller.animateCamera(
      gmap.CameraUpdate.newCameraPosition(_cameraPosition(center)),
    );
  }

  gmap.CameraPosition _cameraPosition(GeoPoint center) {
    return gmap.CameraPosition(target: _toGoogleLatLng(center), zoom: 13.8);
  }

  gmap.LatLng _toGoogleLatLng(GeoPoint point) {
    return gmap.LatLng(point.latitude, point.longitude);
  }

  Set<gmap.Marker> _buildDriverMarkers() {
    return widget.drivers
        .where((driver) => driver.latitude != null && driver.longitude != null)
        .map(
          (driver) => gmap.Marker(
            markerId: gmap.MarkerId('driver-${driver.driverId}'),
            position: gmap.LatLng(driver.latitude!, driver.longitude!),
            infoWindow: gmap.InfoWindow(
              title: driver.displayName,
              snippet: '${driver.vehicleEmoji ?? "🛺"} ${driver.vehicleType}',
            ),
            icon: gmap.BitmapDescriptor.defaultMarkerWithHue(
              _driverMarkerHue(driver.vehicleType),
            ),
            onTap: () => widget.onDriverTap(driver),
          ),
        )
        .toSet();
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (widget.locationState.hasLocation && widget.center != null) {
      child = Stack(
        children: [
          gmap.GoogleMap(
            initialCameraPosition: _cameraPosition(widget.center!),
            mapId: EnvConfig.googleMapsMapIdForPlatform(defaultTargetPlatform),
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
            zoomControlsEnabled: false,
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
            circles: <gmap.Circle>{
              gmap.Circle(
                circleId: const gmap.CircleId('user-location-pulse'),
                center: _toGoogleLatLng(widget.center!),
                radius: 85,
                fillColor: AppColors.accent.withValues(alpha: 0.18),
                strokeColor: AppColors.accent.withValues(alpha: 0.22),
                strokeWidth: 1,
              ),
              gmap.Circle(
                circleId: const gmap.CircleId('user-location-core'),
                center: _toGoogleLatLng(widget.center!),
                radius: 18,
                fillColor: AppColors.accent,
                strokeColor: AppColors.bg,
                strokeWidth: 2,
              ),
            },
            markers: _buildDriverMarkers(),
            onMapCreated: (controller) {
              _controller = controller;
            },
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _MapGridPainter()),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.bg.withValues(alpha: 0.12),
                    Colors.transparent,
                    AppColors.bg.withValues(alpha: 0.24),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: IconButton(
                onPressed: _recenter,
                tooltip: 'Recenter map',
                icon: const Icon(
                  Icons.my_location_rounded,
                  color: AppColors.text,
                ),
              ),
            ),
          ),
        ],
      );
    } else {
      child = _LocationStatePane(
        locationState: widget.locationState,
        onRequestLocation: widget.onRequestLocation,
        onOpenAppSettings: widget.onOpenAppSettings,
        onOpenLocationSettings: widget.onOpenLocationSettings,
      );
    }

    return CoolCard(
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: 180,
        child: ClipRRect(borderRadius: BorderRadius.circular(20), child: child),
      ),
    );
  }
}

class _LocationStatePane extends StatelessWidget {
  const _LocationStatePane({
    required this.locationState,
    required this.onRequestLocation,
    required this.onOpenAppSettings,
    required this.onOpenLocationSettings,
  });

  final MobilityLocationState locationState;
  final VoidCallback onRequestLocation;
  final VoidCallback onOpenAppSettings;
  final VoidCallback onOpenLocationSettings;

  @override
  Widget build(BuildContext context) {
    IconData icon = Icons.location_searching_rounded;
    String title = 'Detecting your location';
    String message = 'Cool is checking where you are to load nearby drivers.';
    String? actionLabel;
    VoidCallback? onAction;

    switch (locationState.status) {
      case MobilityLocationStatus.idle:
      case MobilityLocationStatus.checking:
      case MobilityLocationStatus.requesting:
        break;
      case MobilityLocationStatus.needsPermission:
        icon = Icons.my_location_rounded;
        title = 'Enable location';
        message =
            'Allow location while using the app so Cool can find nearby drivers and scheduled trips.';
        actionLabel = 'Allow location';
        onAction = onRequestLocation;
        break;
      case MobilityLocationStatus.denied:
        icon = Icons.location_off_rounded;
        title = 'Location denied';
        message =
            'You can still schedule trips manually, but nearby matching stays off until you allow location.';
        actionLabel = 'Try again';
        onAction = onRequestLocation;
        break;
      case MobilityLocationStatus.deniedForever:
        icon = Icons.settings_rounded;
        title = 'Location blocked';
        message =
            'Location permission is permanently denied for Cool. Open settings to enable it.';
        actionLabel = 'Open settings';
        onAction = onOpenAppSettings;
        break;
      case MobilityLocationStatus.serviceDisabled:
        icon = Icons.gps_off_rounded;
        title = 'Turn on location services';
        message =
            'Your device location services are off. Turn them on to load nearby drivers and trips.';
        actionLabel = 'Open location settings';
        onAction = onOpenLocationSettings;
        break;
      case MobilityLocationStatus.error:
        icon = Icons.error_outline_rounded;
        title = 'Location unavailable';
        message =
            locationState.error ??
            'Cool could not detect your location right now. Try again.';
        actionLabel = 'Retry';
        onAction = onRequestLocation;
        break;
      case MobilityLocationStatus.ready:
      case MobilityLocationStatus.approximateReady:
        break;
    }

    return Container(
      color: AppColors.surface2,
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (locationState.isLoading)
              const SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: AppColors.accent,
                ),
              )
            else
              Icon(icon, color: AppColors.text2, size: 30),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppColors.text2,
                height: 1.4,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: 190,
                child: CoolButton(label: actionLabel, onTap: onAction),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LocationMetaBanner extends StatelessWidget {
  const _LocationMetaBanner({required this.locationState});

  final MobilityLocationState locationState;

  @override
  Widget build(BuildContext context) {
    final segments = <String>[
      if (locationState.isApproximate) 'Approximate location',
      if (locationState.isStale) 'Using recent cached fix',
      if (locationState.accuracyMeters != null)
        '±${locationState.accuracyMeters!.round()}m',
    ];

    if (segments.isEmpty) {
      return const SizedBox.shrink();
    }

    return CoolCard(
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: AppColors.yellow,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              segments.join(' • '),
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.text2,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.accent.withValues(alpha: 0.08)
      ..strokeWidth = 1;

    const cellSize = 24.0;
    for (double x = 0; x <= size.width; x += cellSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += cellSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PulsingLocationDot extends StatefulWidget {
  const _PulsingLocationDot();

  @override
  State<_PulsingLocationDot> createState() => _PulsingLocationDotState();
}

class _PulsingLocationDotState extends State<_PulsingLocationDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            _PulseRing(progress: _controller.value),
            _PulseRing(progress: (_controller.value + 0.33) % 1.0),
            _PulseRing(progress: (_controller.value + 0.66) % 1.0),
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.35),
                    blurRadius: 14,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PulseRing extends StatelessWidget {
  const _PulseRing({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final size = 14 + (progress * 28);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.35 * (1 - progress)),
          width: 2,
        ),
      ),
    );
  }
}

class _FloatingVehicleMarker extends StatefulWidget {
  const _FloatingVehicleMarker({required this.emoji});

  final String emoji;

  @override
  State<_FloatingVehicleMarker> createState() => _FloatingVehicleMarkerState();
}

class _FloatingVehicleMarkerState extends State<_FloatingVehicleMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _offsetAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _offsetAnimation = Tween<double>(
      begin: -2,
      end: 2,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _offsetAnimation,
      builder: (_, child) {
        return Transform.translate(
          offset: Offset(0, _offsetAnimation.value),
          child: Text(widget.emoji, style: const TextStyle(fontSize: 22)),
        );
      },
    );
  }
}

class _DualTabSwitcher extends StatelessWidget {
  const _DualTabSwitcher({required this.activeIndex, required this.onChanged});

  final int activeIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const labels = ['Nearby Drivers', 'Scheduled Trips'];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final isActive = activeIndex == index;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isActive ? AppColors.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  labels[index],
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isActive ? Colors.black : AppColors.text2,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _NearbyDriversSliver extends StatelessWidget {
  const _NearbyDriversSliver({
    required this.drivers,
    required this.onPreviewTap,
    required this.onWhatsAppTap,
  });

  final List<DriverInfo> drivers;
  final ValueChanged<DriverInfo> onPreviewTap;
  final ValueChanged<DriverInfo> onWhatsAppTap;

  @override
  Widget build(BuildContext context) {
    if (drivers.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Center(
            child: Text(
              'No drivers found for this vehicle type.',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppColors.text2,
              ),
            ),
          ),
        ),
      );
    }

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Text(
            '📍 Top 30 within 10km · nearest first',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: AppColors.text2,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 10)),
        SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final driver = drivers[index];
            return Padding(
              padding: EdgeInsets.only(
                bottom: index == drivers.length - 1 ? 0 : 12,
              ),
              child: DriverCard(
                driverId: driver.driverId,
                displayName: driver.displayName,
                vehicleType: driver.vehicleType,
                vehicleEmoji: driver.vehicleEmoji ?? '🛺',
                distanceKm: driver.distanceKm,
                isOnline: driver.isOnline,
                onTap: () => onPreviewTap(driver),
                onWhatsAppTap: () => onWhatsAppTap(driver),
                rating: driver.rating ?? 0,
                tripCount: driver.tripCount ?? 0,
                scheduledRoute: driver.scheduledRoute,
                hasReturnTrip: driver.hasReturnTrip,
                baseLocation: driver.baseLocation,
                vehicleStatus: driver.vehicleStatus,
                isRegularDriver: driver.isRegularDriver,
              ),
            );
          }, childCount: drivers.length),
        ),
      ],
    );
  }
}

class _ScheduledTripsSliver extends StatelessWidget {
  const _ScheduledTripsSliver({
    required this.trips,
    required this.onPreviewTap,
  });

  final List<Trip> trips;
  final ValueChanged<Trip> onPreviewTap;

  @override
  Widget build(BuildContext context) {
    return SliverMainAxisGroup(
      slivers: [
        SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final trip = trips[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TripCard(
                fromLocation: trip.fromLocation,
                toLocation: trip.toLocation,
                departureTime: trip.departureTime,
                vehicleType: trip.vehicleType,
                vehicleEmoji: trip.vehicleEmoji ?? '🛺',
                onTap: () => onPreviewTap(trip),
                seats: trip.seats,
                isReturn: trip.isReturn,
                isRecurring: trip.isRecurring,
                isDriverReturnTrip: trip.isDriverReturnTrip,
              ),
            );
          }, childCount: trips.length),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 6)),
        SliverToBoxAdapter(
          child: Row(
            children: [
              Expanded(
                child: CoolButton(
                  label: 'See all trips',
                  variant: CoolButtonVariant.secondary,
                  onTap: () => context.push('/mobility/trips'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: CoolButton(
                  label: 'Post Your Trip',
                  onTap: () => context.push('/mobility/schedule'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _vehicleEmoji(String vehicleType) {
  final normalized = vehicleType.trim().toLowerCase();
  if (normalized.contains('moto')) {
    return '🛺';
  }
  if (normalized.contains('cab')) {
    return '🚗';
  }
  if (normalized.contains('truck')) {
    return '🚛';
  }
  if (normalized.contains('liffan') || normalized.contains('van')) {
    return '🚐';
  }
  return '🚘';
}

double _driverMarkerHue(String vehicleType) {
  final normalized = vehicleType.trim().toLowerCase();
  if (normalized.contains('moto')) {
    return gmap.BitmapDescriptor.hueAzure;
  }
  if (normalized.contains('cab')) {
    return gmap.BitmapDescriptor.hueViolet;
  }
  if (normalized.contains('truck')) {
    return gmap.BitmapDescriptor.hueOrange;
  }
  if (normalized.contains('liffan') || normalized.contains('van')) {
    return gmap.BitmapDescriptor.hueCyan;
  }
  return gmap.BitmapDescriptor.hueRed;
}

bool _hasTripContact(Trip trip) =>
    (trip.whatsappNumber?.trim().isNotEmpty ?? false) ||
    (trip.contactPhone?.trim().isNotEmpty ?? false);

bool _hasDriverContact(DriverInfo driver) =>
    driver.contactPhone?.trim().isNotEmpty ?? false;

class _VehicleFilter {
  const _VehicleFilter({required this.label, required this.value});

  final String label;
  final String value;
}
