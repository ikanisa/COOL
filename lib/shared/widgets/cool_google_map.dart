import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/config/env_config.dart';
import '../../core/theme/cool_palette.dart';

/// Google Maps dark-mode JSON style.
///
/// Matches the COOL dark-first design system. Muted labels, dark water/roads,
/// and subtle geometry keep the map from overwhelming the UI.
const _kDarkMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#1d2c4d"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#8ec3b9"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#1a3646"}]},
  {"featureType":"administrative.country","elementType":"geometry.stroke","stylers":[{"color":"#4b6878"}]},
  {"featureType":"landscape","elementType":"geometry","stylers":[{"color":"#1d2c4d"}]},
  {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#283d6a"}]},
  {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#6f9ba5"}]},
  {"featureType":"poi.park","elementType":"geometry.fill","stylers":[{"color":"#023e58"}]},
  {"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#3C7680"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#304a7d"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#98a5be"}]},
  {"featureType":"road","elementType":"labels.text.stroke","stylers":[{"color":"#1d2c4d"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#2c6675"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#255763"}]},
  {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#b0d5ce"}]},
  {"featureType":"transit","elementType":"labels.text.fill","stylers":[{"color":"#98a5be"}]},
  {"featureType":"transit","elementType":"labels.text.stroke","stylers":[{"color":"#1d2c4d"}]},
  {"featureType":"transit.line","elementType":"geometry.fill","stylers":[{"color":"#283d6a"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0e1626"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#4e6d70"}]}
]
''';

/// Default camera position: Kigali, Rwanda.
const _kDefaultTarget = LatLng(-1.9403, 29.8739);

/// Reusable Google Maps widget for the COOL app.
///
/// Features:
/// - Dark-mode JSON styling (always, matching the app's dark-first policy)
/// - Cloud Map ID from [EnvConfig] (enables server-side styling if configured)
/// - Disabled tilt, rotation, and map toolbar for cleaner mobile UX
/// - Built-in loading shimmer
/// - User location dot (when enabled)
class CoolGoogleMap extends StatefulWidget {
  const CoolGoogleMap({
    this.initialTarget,
    this.initialZoom = 14.0,
    this.markers = const <Marker>{},
    this.polylines = const <Polyline>{},
    this.myLocationEnabled = true,
    this.myLocationButtonEnabled = false,
    this.onMapCreated,
    this.onCameraMove,
    this.onCameraIdle,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final LatLng? initialTarget;
  final double initialZoom;
  final Set<Marker> markers;
  final Set<Polyline> polylines;
  final bool myLocationEnabled;
  final bool myLocationButtonEnabled;
  final void Function(GoogleMapController controller)? onMapCreated;
  final void Function(CameraPosition position)? onCameraMove;
  final VoidCallback? onCameraIdle;
  final EdgeInsets padding;

  @override
  State<CoolGoogleMap> createState() => _CoolGoogleMapState();
}

class _CoolGoogleMapState extends State<CoolGoogleMap> {
  bool _isMapReady = false;

  String? get _mapId {
    if (Platform.isAndroid && EnvConfig.googleMapsAndroidMapId.isNotEmpty) {
      return EnvConfig.googleMapsAndroidMapId;
    }
    if (Platform.isIOS && EnvConfig.googleMapsIosMapId.isNotEmpty) {
      return EnvConfig.googleMapsIosMapId;
    }
    return null;
  }

  void _handleMapCreated(GoogleMapController controller) {
    // Apply dark style regardless of cloud Map ID — the JSON style is our
    // fallback/baseline, and cloud styling would override it if a Map ID
    // is set on the Google Cloud Console side.
    controller.setMapStyle(_kDarkMapStyle);

    setState(() => _isMapReady = true);
    widget.onMapCreated?.call(controller);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final target = widget.initialTarget ?? _kDefaultTarget;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: target,
              zoom: widget.initialZoom,
            ),
            cloudMapId: _mapId,
            markers: widget.markers,
            polylines: widget.polylines,
            myLocationEnabled: widget.myLocationEnabled,
            myLocationButtonEnabled: widget.myLocationButtonEnabled,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            tiltGesturesEnabled: false,
            rotateGesturesEnabled: false,
            compassEnabled: false,
            padding: widget.padding,
            onMapCreated: _handleMapCreated,
            onCameraMove: widget.onCameraMove,
            onCameraIdle: widget.onCameraIdle,
          ),

          // Loading shimmer until the map tiles have loaded.
          if (!_isMapReady)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: palette.surface2,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Center(
                  child: CupertinoActivityIndicator(color: palette.accent),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
