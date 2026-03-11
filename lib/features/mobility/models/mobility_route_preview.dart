import 'package:cool_app/core/models/geo_point.dart';

enum MobilityRouteTravelMode { drive, twoWheeler }

extension MobilityRouteTravelModeX on MobilityRouteTravelMode {
  String get apiValue => switch (this) {
    MobilityRouteTravelMode.drive => 'DRIVE',
    MobilityRouteTravelMode.twoWheeler => 'TWO_WHEELER',
  };
}

class MobilityRoutePreview {
  const MobilityRoutePreview({
    required this.origin,
    required this.destination,
    required this.distanceMeters,
    required this.duration,
    required this.encodedPolyline,
    required this.travelMode,
    this.localizedDistance,
    this.localizedDuration,
    this.polylinePoints = const <GeoPoint>[],
  });

  factory MobilityRoutePreview.fromJson(
    Map<String, dynamic> json, {
    required GeoPoint origin,
    required GeoPoint destination,
  }) {
    final encodedPolyline = json['encodedPolyline']?.toString().trim() ?? '';
    final travelModeRaw = json['travelMode']?.toString().trim().toUpperCase();

    return MobilityRoutePreview(
      origin: origin,
      destination: destination,
      distanceMeters: _asInt(json['distanceMeters']),
      duration: _parseDuration(json['duration']),
      encodedPolyline: encodedPolyline,
      travelMode: travelModeRaw == 'TWO_WHEELER'
          ? MobilityRouteTravelMode.twoWheeler
          : MobilityRouteTravelMode.drive,
      localizedDistance: json['localizedDistance']?.toString(),
      localizedDuration: json['localizedDuration']?.toString(),
      polylinePoints: encodedPolyline.isEmpty
          ? const <GeoPoint>[]
          : _decodePolyline(encodedPolyline),
    );
  }

  final GeoPoint origin;
  final GeoPoint destination;
  final int distanceMeters;
  final Duration duration;
  final String encodedPolyline;
  final MobilityRouteTravelMode travelMode;
  final String? localizedDistance;
  final String? localizedDuration;
  final List<GeoPoint> polylinePoints;

  double get distanceKm => distanceMeters / 1000;

  String get distanceLabel {
    final localized = localizedDistance?.trim();
    if (localized != null && localized.isNotEmpty) {
      return localized;
    }
    if (distanceMeters < 1000) {
      return '$distanceMeters m';
    }
    return '${distanceKm.toStringAsFixed(1)} km';
  }

  String get durationLabel {
    final localized = localizedDuration?.trim();
    if (localized != null && localized.isNotEmpty) {
      return localized;
    }

    final totalMinutes = duration.inMinutes;
    if (totalMinutes < 1) {
      return '<1 min';
    }
    if (totalMinutes < 60) {
      return '$totalMinutes min';
    }

    final hours = duration.inHours;
    final minutes = totalMinutes.remainder(60);
    if (minutes == 0) {
      return '$hours h';
    }
    return '$hours h $minutes min';
  }
}

int _asInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

Duration _parseDuration(dynamic value) {
  if (value is int) {
    return Duration(seconds: value);
  }
  if (value is num) {
    return Duration(milliseconds: value.round());
  }

  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) {
    return Duration.zero;
  }
  if (raw.endsWith('s')) {
    final seconds = double.tryParse(raw.substring(0, raw.length - 1));
    if (seconds != null) {
      return Duration(milliseconds: (seconds * 1000).round());
    }
  }

  return Duration.zero;
}

List<GeoPoint> _decodePolyline(String encoded) {
  final points = <GeoPoint>[];
  var index = 0;
  var latitude = 0;
  var longitude = 0;

  while (index < encoded.length) {
    final latitudeResult = _decodePolylineValue(encoded, index);
    latitude += latitudeResult.value;
    index = latitudeResult.nextIndex;

    final longitudeResult = _decodePolylineValue(encoded, index);
    longitude += longitudeResult.value;
    index = longitudeResult.nextIndex;

    points.add(GeoPoint(latitude: latitude / 1e5, longitude: longitude / 1e5));
  }

  return points;
}

_DecodedPolylineValue _decodePolylineValue(String encoded, int startIndex) {
  var result = 0;
  var shift = 0;
  var index = startIndex;

  while (index < encoded.length) {
    final codeUnit = encoded.codeUnitAt(index++) - 63;
    result |= (codeUnit & 0x1f) << shift;
    shift += 5;
    if (codeUnit < 0x20) {
      break;
    }
  }

  final value = (result & 1) == 1 ? ~(result >> 1) : (result >> 1);
  return _DecodedPolylineValue(value: value, nextIndex: index);
}

class _DecodedPolylineValue {
  const _DecodedPolylineValue({required this.value, required this.nextIndex});

  final int value;
  final int nextIndex;
}
