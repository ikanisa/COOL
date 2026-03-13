import 'dart:async';

import 'package:cool_app/core/models/geo_point.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;

import '../../../core/config/env_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../models/driver_info.dart';
import '../providers/mobility_location_provider.dart';
import '../providers/mobility_provider.dart';

const _defaultMapCenter = GeoPoint(latitude: -1.9441, longitude: 30.0619);

// ═════════════════════════════════════════════════════════════════════════════
// MAP SECTION (orchestrates map box + location meta banner)
// ═════════════════════════════════════════════════════════════════════════════

class MobilityMapSection extends ConsumerWidget {
  const MobilityMapSection({required this.onDriverTap, super.key});

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
          child: MobilityMapBox(
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
          MobilityLocationMetaBanner(locationState: locationState),
        ],
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// MAP BOX (Google Maps + overlays)
// ═════════════════════════════════════════════════════════════════════════════

class MobilityMapBox extends StatefulWidget {
  const MobilityMapBox({
    required this.center,
    required this.drivers,
    required this.locationState,
    required this.onDriverTap,
    required this.onRequestLocation,
    required this.onOpenAppSettings,
    required this.onOpenLocationSettings,
    super.key,
  });

  final GeoPoint? center;
  final List<DriverInfo> drivers;
  final MobilityLocationState locationState;
  final ValueChanged<DriverInfo> onDriverTap;
  final VoidCallback onRequestLocation;
  final VoidCallback onOpenAppSettings;
  final VoidCallback onOpenLocationSettings;

  @override
  State<MobilityMapBox> createState() => _MobilityMapBoxState();
}

class _MobilityMapBoxState extends State<MobilityMapBox> {
  gmap.GoogleMapController? _controller;

  Future<void> _recenter() async {
    final center = widget.center;
    final controller = _controller;
    if (center == null || controller == null) return;

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
              snippet: driver.vehicleType,
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
    final supportsEmbeddedMaps = EnvConfig.hasEmbeddedGoogleMapsSupport(
      Theme.of(context).platform,
    );
    Widget child;
    if (!supportsEmbeddedMaps) {
      child = MobilityMapUnavailablePane(
        message:
            EnvConfig.embeddedGoogleMapsUnavailableReason(
              Theme.of(context).platform,
            ) ??
            'Embedded maps are unavailable in this build.',
      );
    } else if (widget.locationState.hasLocation && widget.center != null) {
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
      child = MobilityLocationStatePane(
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

// ═════════════════════════════════════════════════════════════════════════════
// LOCATION STATE PANE (permission / error states)
// ═════════════════════════════════════════════════════════════════════════════

class MobilityMapUnavailablePane extends StatelessWidget {
  const MobilityMapUnavailablePane({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface3,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.map_outlined, color: AppColors.text2, size: 28),
          const SizedBox(height: 10),
          Text(
            'Nearby map unavailable',
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$message Browse nearby drivers and trips from the list instead.',
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppColors.text2,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class MobilityLocationStatePane extends StatelessWidget {
  const MobilityLocationStatePane({
    required this.locationState,
    required this.onRequestLocation,
    required this.onOpenAppSettings,
    required this.onOpenLocationSettings,
    super.key,
  });

  final MobilityLocationState locationState;
  final VoidCallback onRequestLocation;
  final VoidCallback onOpenAppSettings;
  final VoidCallback onOpenLocationSettings;

  @override
  Widget build(BuildContext context) {
    IconData icon = Icons.location_searching_rounded;
    String title = 'Detecting your location';
    String message = 'Detecting your location…';
    String? actionLabel;
    VoidCallback? onAction;

    switch (locationState.status) {
      case MobilityLocationStatus.idle:
      case MobilityLocationStatus.checking:
      case MobilityLocationStatus.requesting:
        break;
      case MobilityLocationStatus.accessDisabled:
        icon = Icons.admin_panel_settings_outlined;
        title = 'Location is off in COOL';
        message =
            'Enable location in Profile settings to restore nearby drivers and mobility matching.';
        actionLabel = 'Enable location';
        onAction = onRequestLocation;
        break;
      case MobilityLocationStatus.needsPermission:
        icon = Icons.my_location_rounded;
        title = 'Enable location';
        message = 'Allow location to see nearby drivers.';
        actionLabel = 'Allow location';
        onAction = onRequestLocation;
        break;
      case MobilityLocationStatus.denied:
        icon = Icons.location_off_rounded;
        title = 'Location denied';
        message = 'Nearby matching is off. Allow location to enable it.';
        actionLabel = 'Try again';
        onAction = onRequestLocation;
        break;
      case MobilityLocationStatus.deniedForever:
        icon = Icons.settings_rounded;
        title = 'Location blocked';
        message = 'Location blocked. Open settings to allow it.';
        actionLabel = 'Open settings';
        onAction = onOpenAppSettings;
        break;
      case MobilityLocationStatus.serviceDisabled:
        icon = Icons.gps_off_rounded;
        title = 'Turn on location services';
        message = 'Location services off. Turn on to see nearby drivers.';
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
        child: SingleChildScrollView(
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
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// LOCATION META BANNER
// ═════════════════════════════════════════════════════════════════════════════

class MobilityLocationMetaBanner extends StatelessWidget {
  const MobilityLocationMetaBanner({required this.locationState, super.key});

  final MobilityLocationState locationState;

  @override
  Widget build(BuildContext context) {
    final segments = <String>[
      if (locationState.isApproximate) 'Approximate location',
      if (locationState.isStale) 'Using recent cached fix',
      if (locationState.accuracyMeters != null)
        '±${locationState.accuracyMeters!.round()}m',
    ];

    if (segments.isEmpty) return const SizedBox.shrink();

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

// ═════════════════════════════════════════════════════════════════════════════
// MAP GRID OVERLAY PAINTER
// ═════════════════════════════════════════════════════════════════════════════

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

// ═════════════════════════════════════════════════════════════════════════════
// HELPERS
// ═════════════════════════════════════════════════════════════════════════════

double _driverMarkerHue(String vehicleType) {
  final normalized = vehicleType.trim().toLowerCase();
  if (normalized.contains('moto')) return gmap.BitmapDescriptor.hueAzure;
  if (normalized.contains('cab')) return gmap.BitmapDescriptor.hueViolet;
  if (normalized.contains('truck')) return gmap.BitmapDescriptor.hueOrange;
  if (normalized.contains('liffan') || normalized.contains('van')) {
    return gmap.BitmapDescriptor.hueCyan;
  }
  return gmap.BitmapDescriptor.hueRed;
}
