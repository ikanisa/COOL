import 'dart:async';
import 'dart:math' as math;

import 'package:cool_app/core/config/env_config.dart';
import 'package:cool_app/core/models/geo_point.dart';
import 'package:cool_app/core/theme/app_colors.dart';
import 'package:cool_app/features/mobility/models/mobility_route_preview.dart';
import 'package:cool_app/shared/widgets/cool_card.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;

class ScheduleTripMapPreview extends StatefulWidget {
  const ScheduleTripMapPreview({
    required this.originLabel,
    required this.destinationLabel,
    this.origin,
    this.destination,
    this.preview,
    this.isLoading = false,
    this.error,
    super.key,
  });

  final String originLabel;
  final String destinationLabel;
  final GeoPoint? origin;
  final GeoPoint? destination;
  final MobilityRoutePreview? preview;
  final bool isLoading;
  final String? error;

  @override
  State<ScheduleTripMapPreview> createState() => _ScheduleTripMapPreviewState();
}

class _ScheduleTripMapPreviewState extends State<ScheduleTripMapPreview> {
  gmap.GoogleMapController? _controller;

  @override
  void didUpdateWidget(covariant ScheduleTripMapPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preview != widget.preview ||
        oldWidget.origin != widget.origin ||
        oldWidget.destination != widget.destination) {
      unawaited(_syncCamera());
    }
  }

  Future<void> _syncCamera() async {
    final controller = _controller;
    final bounds = _buildBounds(_contentPoints);
    if (controller == null || bounds == null) {
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) {
      return;
    }

    try {
      await controller.animateCamera(
        gmap.CameraUpdate.newLatLngBounds(bounds, 48),
      );
    } catch (_) {
      final fallback = _contentPoints.isEmpty
          ? null
          : _toLatLng(_contentPoints.first);
      if (fallback != null) {
        await controller.animateCamera(
          gmap.CameraUpdate.newCameraPosition(
            gmap.CameraPosition(target: fallback, zoom: 13),
          ),
        );
      }
    }
  }

  List<GeoPoint> get _contentPoints {
    final previewPoints = widget.preview?.polylinePoints ?? const <GeoPoint>[];
    if (previewPoints.isNotEmpty) {
      return previewPoints;
    }

    return <GeoPoint>[
      if (widget.origin != null) widget.origin!,
      if (widget.destination != null) widget.destination!,
    ];
  }

  Set<gmap.Marker> get _markers {
    return <gmap.Marker>{
      if (widget.origin != null)
        gmap.Marker(
          markerId: const gmap.MarkerId('schedule-origin'),
          position: _toLatLng(widget.origin!),
          infoWindow: gmap.InfoWindow(title: widget.originLabel),
          icon: gmap.BitmapDescriptor.defaultMarkerWithHue(
            gmap.BitmapDescriptor.hueGreen,
          ),
        ),
      if (widget.destination != null)
        gmap.Marker(
          markerId: const gmap.MarkerId('schedule-destination'),
          position: _toLatLng(widget.destination!),
          infoWindow: gmap.InfoWindow(title: widget.destinationLabel),
          icon: gmap.BitmapDescriptor.defaultMarkerWithHue(
            gmap.BitmapDescriptor.hueRed,
          ),
        ),
    };
  }

  Set<gmap.Polyline> get _polylines {
    final preview = widget.preview;
    if (preview == null || preview.polylinePoints.isEmpty) {
      return const <gmap.Polyline>{};
    }

    return <gmap.Polyline>{
      gmap.Polyline(
        polylineId: const gmap.PolylineId('schedule-route'),
        color: AppColors.accent,
        width: 5,
        startCap: gmap.Cap.roundCap,
        endCap: gmap.Cap.roundCap,
        jointType: gmap.JointType.round,
        points: preview.polylinePoints.map(_toLatLng).toList(growable: false),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final contentPoints = _contentPoints;
    final preview = widget.preview;
    final supportsEmbeddedMaps = EnvConfig.hasEmbeddedGoogleMapsSupport(
      Theme.of(context).platform,
    );

    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                supportsEmbeddedMaps ? 'Route Preview' : 'Route Summary',
                style: GoogleFonts.dmSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const Spacer(),
              if (widget.isLoading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.accent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            preview == null
                ? supportsEmbeddedMaps
                      ? 'Resolve pickup and destination to preview the route on the map.'
                      : 'Resolve pickup and destination to preview route details before posting.'
                : supportsEmbeddedMaps
                ? 'Review the path, ETA, and distance before posting the trip.'
                : 'Review the route, ETA, and distance before posting the trip.',
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              height: 220,
              child: Stack(
                children: [
                  if (contentPoints.isEmpty)
                    Container(
                      color: AppColors.surface3,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        'Add at least one resolved place to start the map preview.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.text2,
                          height: 1.45,
                        ),
                      ),
                    )
                  else if (!supportsEmbeddedMaps)
                    _RouteSummaryPane(
                      originLabel: widget.originLabel,
                      destinationLabel: widget.destinationLabel,
                      preview: preview,
                    )
                  else
                    gmap.GoogleMap(
                      initialCameraPosition: gmap.CameraPosition(
                        target: _toLatLng(contentPoints.first),
                        zoom: contentPoints.length == 1 ? 14.2 : 11.5,
                      ),
                      mapId: EnvConfig.googleMapsMapIdForPlatform(
                        defaultTargetPlatform,
                      ),
                      myLocationEnabled: false,
                      myLocationButtonEnabled: false,
                      mapToolbarEnabled: false,
                      compassEnabled: false,
                      zoomControlsEnabled: false,
                      rotateGesturesEnabled: false,
                      tiltGesturesEnabled: false,
                      markers: _markers,
                      polylines: _polylines,
                      onMapCreated: (controller) {
                        _controller = controller;
                        unawaited(_syncCamera());
                      },
                    ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              AppColors.bg.withValues(alpha: 0.10),
                              Colors.transparent,
                              AppColors.bg.withValues(alpha: 0.20),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (preview != null && supportsEmbeddedMaps)
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 10,
                      child: _PreviewChips(preview: preview),
                    ),
                ],
              ),
            ),
          ),
          if (widget.error?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 10),
            Text(
              widget.error!.trim(),
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.orange,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RouteSummaryPane extends StatelessWidget {
  const _RouteSummaryPane({
    required this.originLabel,
    required this.destinationLabel,
    required this.preview,
  });

  final String originLabel;
  final String destinationLabel;
  final MobilityRoutePreview? preview;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface3,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.alt_route_rounded,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Map rendering is hidden in this build. Route details still work.',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _RouteStopRow(
            icon: Icons.trip_origin_rounded,
            label: 'Pickup',
            value: originLabel,
          ),
          const SizedBox(height: 12),
          _RouteStopRow(
            icon: Icons.place_outlined,
            label: 'Destination',
            value: destinationLabel,
          ),
          if (preview != null) ...[
            const Spacer(),
            _PreviewChips(preview: preview!),
          ],
        ],
      ),
    );
  }
}

class _RouteStopRow extends StatelessWidget {
  const _RouteStopRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.text2),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value.trim().isEmpty ? 'Not attached yet.' : value.trim(),
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PreviewChips extends StatelessWidget {
  const _PreviewChips({required this.preview});

  final MobilityRoutePreview preview;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _PreviewChip(icon: Icons.route_rounded, label: preview.distanceLabel),
        _PreviewChip(
          icon: Icons.schedule_rounded,
          label: preview.durationLabel,
        ),
        _PreviewChip(
          icon: preview.travelMode == MobilityRouteTravelMode.twoWheeler
              ? Icons.two_wheeler_rounded
              : Icons.directions_car_filled_rounded,
          label: preview.travelMode == MobilityRouteTravelMode.twoWheeler
              ? 'Moto route'
              : 'Drive route',
        ),
      ],
    );
  }
}

class _PreviewChip extends StatelessWidget {
  const _PreviewChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.accent),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
        ],
      ),
    );
  }
}

gmap.LatLng _toLatLng(GeoPoint point) {
  return gmap.LatLng(point.latitude, point.longitude);
}

gmap.LatLngBounds? _buildBounds(List<GeoPoint> points) {
  if (points.isEmpty) {
    return null;
  }

  var minLat = points.first.latitude;
  var maxLat = points.first.latitude;
  var minLng = points.first.longitude;
  var maxLng = points.first.longitude;

  for (final point in points.skip(1)) {
    minLat = math.min(minLat, point.latitude);
    maxLat = math.max(maxLat, point.latitude);
    minLng = math.min(minLng, point.longitude);
    maxLng = math.max(maxLng, point.longitude);
  }

  final latPadding = (maxLat - minLat).abs() < 0.002 ? 0.004 : 0.0012;
  final lngPadding = (maxLng - minLng).abs() < 0.002 ? 0.004 : 0.0012;

  return gmap.LatLngBounds(
    southwest: gmap.LatLng(minLat - latPadding, minLng - lngPadding),
    northeast: gmap.LatLng(maxLat + latPadding, maxLng + lngPadding),
  );
}
