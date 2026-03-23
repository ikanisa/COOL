import 'package:cool_app/core/models/geo_point.dart';
import 'package:cool_app/core/theme/cool_foundations.dart';
import 'package:cool_app/features/mobility/models/mobility_route_preview.dart';
import 'package:cool_app/shared/widgets/cool_card.dart';
import 'package:cool_app/shared/widgets/cool_google_map.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/l10n/l10n.dart';

class ScheduleTripRoutePreview extends StatelessWidget {
  const ScheduleTripRoutePreview({
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final hasAnyPoint = origin != null || destination != null;

    return CoolCard(
      backgroundColor: colors.routeSurface,
      borderColor: colors.borderStrong,
      useGradient: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Route summary',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colors.primaryText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (isLoading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CupertinoActivityIndicator(radius: 9),
                ),
            ],
          ),
          const SizedBox(height: CoolSpace.x2),
          Text(
            preview == null ? 'Add both points' : 'Review before posting',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.secondaryText,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.cardSurfaceStrong,
              borderRadius: BorderRadius.circular(CoolRadii.xl),
              border: Border.all(color: colors.border),
            ),
            child: hasAnyPoint
                ? _RouteSummaryPane(
                    originLabel: originLabel,
                    destinationLabel: destinationLabel,
                    preview: preview,
                  )
                : Text(
                    'Add one stop',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.secondaryText,
                      fontWeight: FontWeight.w600,
                      height: 1.45,
                    ),
                  ),
          ),
          if (origin != null || destination != null) ...[
            const SizedBox(height: 14),
            _RouteMapPreview(
              origin: origin,
              destination: destination,
              polylinePoints: preview?.polylinePoints,
            ),
          ],
          if (error?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 10),
            Text(
              error!.trim(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.warning,
                fontWeight: FontWeight.w700,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RouteStopRow(
          icon: Icons.trip_origin_rounded,
          label: context.l10n.pickup,
          value: originLabel,
        ),
        const SizedBox(height: CoolSpace.x3),
        _RouteStopRow(
          icon: Icons.place_outlined,
          label: context.l10n.dropoff,
          value: destinationLabel,
        ),
        if (preview != null) ...[
          const SizedBox(height: CoolSpace.x4),
          _PreviewChips(preview: preview!),
        ],
      ],
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
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: colors.secondaryText),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.tertiaryText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value.trim().isEmpty ? 'Not set yet' : value.trim(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.primaryText,
                  fontWeight: FontWeight.w700,
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
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.chipBackground,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors.accent),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteMapPreview extends StatefulWidget {
  const _RouteMapPreview({this.origin, this.destination, this.polylinePoints});

  final GeoPoint? origin;
  final GeoPoint? destination;
  final List<GeoPoint>? polylinePoints;

  @override
  State<_RouteMapPreview> createState() => _RouteMapPreviewState();
}

class _RouteMapPreviewState extends State<_RouteMapPreview> {
  GoogleMapController? _controller;

  LatLng? get _originLatLng => widget.origin != null
      ? LatLng(widget.origin!.latitude, widget.origin!.longitude)
      : null;

  LatLng? get _destinationLatLng => widget.destination != null
      ? LatLng(widget.destination!.latitude, widget.destination!.longitude)
      : null;

  Set<Marker> get _markers {
    final markers = <Marker>{};
    if (_originLatLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: _originLatLng!,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: const InfoWindow(title: 'Pickup'),
        ),
      );
    }
    if (_destinationLatLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: _destinationLatLng!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'Destination'),
        ),
      );
    }
    return markers;
  }

  Set<Polyline> _polylines(BuildContext context) {
    final points = widget.polylinePoints;
    if (points == null || points.length < 2) return const <Polyline>{};
    return <Polyline>{
      Polyline(
        polylineId: const PolylineId('route'),
        points: points
            .map((p) => LatLng(p.latitude, p.longitude))
            .toList(growable: false),
        color: context.coolSemanticColors.info,
        width: 4,
      ),
    };
  }

  void _fitBounds() {
    if (_controller == null) return;
    if (_originLatLng != null && _destinationLatLng != null) {
      final bounds = LatLngBounds(
        southwest: LatLng(
          _originLatLng!.latitude < _destinationLatLng!.latitude
              ? _originLatLng!.latitude
              : _destinationLatLng!.latitude,
          _originLatLng!.longitude < _destinationLatLng!.longitude
              ? _originLatLng!.longitude
              : _destinationLatLng!.longitude,
        ),
        northeast: LatLng(
          _originLatLng!.latitude > _destinationLatLng!.latitude
              ? _originLatLng!.latitude
              : _destinationLatLng!.latitude,
          _originLatLng!.longitude > _destinationLatLng!.longitude
              ? _originLatLng!.longitude
              : _destinationLatLng!.longitude,
        ),
      );
      _controller!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 40));
    }
  }

  @override
  void didUpdateWidget(covariant _RouteMapPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.origin != oldWidget.origin ||
        widget.destination != oldWidget.destination) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitBounds());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(CoolRadii.xl),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(CoolRadii.xl),
        ),
        child: SizedBox(
          height: 160,
          child: CoolGoogleMap(
            initialTarget: _originLatLng ?? _destinationLatLng,
            initialZoom: 13.0,
            markers: _markers,
            polylines: _polylines(context),
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            onMapCreated: (controller) {
              _controller = controller;
              Future.delayed(const Duration(milliseconds: 400), _fitBounds);
            },
          ),
        ),
      ),
    );
  }
}
