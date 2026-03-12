import 'dart:async';

import 'package:cool_app/core/models/geo_point.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/config/deep_link_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/share_card.dart';
import '../../../shared/widgets/wa_button.dart';
import '../models/driver_info.dart';
import '../models/mobility_route_preview.dart';
import '../models/trip.dart';
import '../services/place_search_service.dart';
import 'schedule_trip_map_preview.dart';

Future<void> showTripListingSheet(
  BuildContext context, {
  required Trip trip,
  required String buttonLabel,
  VoidCallback? onOpenWhatsApp,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
        child: _TripListingSheetBody(
          trip: trip,
          buttonLabel: buttonLabel,
          onOpenWhatsApp: onOpenWhatsApp,
        ),
      ),
    ),
  );
}

Future<void> showDriverListingSheet(
  BuildContext context, {
  required DriverInfo driver,
  required String buttonLabel,
  VoidCallback? onOpenWhatsApp,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
        child: _DriverListingSheetBody(
          driver: driver,
          buttonLabel: buttonLabel,
          onOpenWhatsApp: onOpenWhatsApp,
        ),
      ),
    ),
  );
}

class _TripListingSheetBody extends ConsumerStatefulWidget {
  const _TripListingSheetBody({
    required this.trip,
    required this.buttonLabel,
    this.onOpenWhatsApp,
  });

  final Trip trip;
  final String buttonLabel;
  final VoidCallback? onOpenWhatsApp;

  @override
  ConsumerState<_TripListingSheetBody> createState() =>
      _TripListingSheetBodyState();
}

class _TripListingSheetBodyState extends ConsumerState<_TripListingSheetBody> {
  MobilityRoutePreview? _routePreview;
  bool _loadingRoutePreview = false;
  String? _routePreviewError;
  int _routePreviewRequestId = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshRoutePreview());
  }

  Future<void> _refreshRoutePreview() async {
    final origin = _tripOrigin;
    final destination = _tripDestination;
    final requestId = ++_routePreviewRequestId;

    if (origin == null || destination == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _routePreview = null;
        _loadingRoutePreview = false;
        _routePreviewError = null;
      });
      return;
    }

    setState(() {
      _loadingRoutePreview = true;
      _routePreviewError = null;
    });

    try {
      final preview = await ref
          .read(placeSearchServiceProvider)
          .computeRoutePreview(
            origin: origin,
            destination: destination,
            languageTag: Localizations.localeOf(context).toLanguageTag(),
            travelMode: _travelModeFor(widget.trip),
          );
      if (!mounted || requestId != _routePreviewRequestId) {
        return;
      }

      setState(() {
        _routePreview = preview;
        _loadingRoutePreview = false;
        _routePreviewError = preview == null
            ? 'Google route data is not available for this listing yet.'
            : null;
      });
    } catch (_) {
      if (!mounted || requestId != _routePreviewRequestId) {
        return;
      }

      setState(() {
        _routePreview = null;
        _loadingRoutePreview = false;
        _routePreviewError =
            'The route preview could not be loaded right now. Coordinates are still attached.';
      });
    }
  }

  GeoPoint? get _tripOrigin {
    final latitude = widget.trip.latitude;
    final longitude = widget.trip.longitude;
    if (latitude == null || longitude == null) {
      return null;
    }
    return GeoPoint(latitude: latitude, longitude: longitude);
  }

  GeoPoint? get _tripDestination {
    final latitude = widget.trip.destinationLatitude;
    final longitude = widget.trip.destinationLongitude;
    if (latitude == null || longitude == null) {
      return null;
    }
    return GeoPoint(latitude: latitude, longitude: longitude);
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final departure = DateFormat(
      'EEE d MMM • HH:mm',
    ).format(trip.departureTime);
    final contactName = trip.contactName?.trim();
    final distance = trip.distanceKm == null
        ? null
        : trip.distanceKm! < 1
        ? '${(trip.distanceKm! * 1000).round()} m away'
        : '${trip.distanceKm!.toStringAsFixed(1)} km away';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SheetHandle(),
        const SizedBox(height: 16),
        Text(
          'Trip Listing',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 8),
        _RouteHeadline(from: trip.fromLocation, to: trip.toLocation),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _SheetChip(
              label:
                  _displayVehicleType(trip.vehicleType),
            ),
            _SheetChip(label: departure),
            if (trip.seats > 0) _SheetChip(label: 'Seats ${trip.seats}'),
            if (distance != null) _SheetChip(label: distance),
            if (trip.isReturn || trip.isDriverReturnTrip)
              _SheetChip(
                label: 'Return trip',
                bgColor: AppColors.purple.withValues(alpha: 0.16),
                textColor: AppColors.purple,
              ),
            if (trip.isRecurring)
              _SheetChip(
                label: 'Recurring',
                bgColor: AppColors.accentGlow,
                textColor: AppColors.accent,
              ),
          ],
        ),
        if (_tripOrigin != null && _tripDestination != null) ...[
          const SizedBox(height: 14),
          ScheduleTripMapPreview(
            originLabel: trip.fromLocation,
            destinationLabel: trip.toLocation,
            origin: _tripOrigin,
            destination: _tripDestination,
            preview: _routePreview,
            isLoading: _loadingRoutePreview,
            error: _routePreviewError,
          ),
        ],
        const SizedBox(height: 16),
        if (contactName != null && contactName.isNotEmpty)
          _DetailRow(label: 'Posted by', value: contactName),
        _DetailRow(
          label: 'Route coordinates',
          value: _tripOrigin != null && _tripDestination != null
              ? _routePreview == null
                    ? 'Pinned with Google route lookup'
                    : 'Pinned with Google route preview'
              : 'Text route only',
        ),
        _DetailRow(
          label: 'Chat flow',
          value: 'Price and pickup are agreed on WhatsApp after you connect.',
        ),
        if (trip.priceNote?.trim().isNotEmpty ?? false)
          _DetailRow(label: 'Price note', value: trip.priceNote!.trim()),
        const SizedBox(height: 18),
        _MarketplaceHint(
          text:
              'This app introduces both sides. Final price, exact pickup, and timing are confirmed in WhatsApp.',
        ),
        if (trip.id != null) ...[
          const SizedBox(height: 14),
          ShareCard(
            title: 'Share this trip',
            icon: Icons.electric_rickshaw_rounded,
            subtitle: '${trip.fromLocation} → ${trip.toLocation}',
            shareUrl: DeepLinkConfig.tripUri(trip.id!).toString(),
            shareText:
                'Check out this trip from ${trip.fromLocation} to ${trip.toLocation} on Cool!',
          ),
        ],
        const SizedBox(height: 18),
        if (widget.onOpenWhatsApp != null)
          Align(
            alignment: Alignment.centerRight,
            child: WaButton(
              label: widget.buttonLabel,
              onTap: () {
                Navigator.of(context).pop();
                widget.onOpenWhatsApp!();
              },
            ),
          )
        else
          const _UnavailableHint(
            text: 'WhatsApp contact is not available for this listing yet.',
          ),
      ],
    );
  }
}

class _DriverListingSheetBody extends StatelessWidget {
  const _DriverListingSheetBody({
    required this.driver,
    required this.buttonLabel,
    this.onOpenWhatsApp,
  });

  final DriverInfo driver;
  final String buttonLabel;
  final VoidCallback? onOpenWhatsApp;

  @override
  Widget build(BuildContext context) {
    final distance = driver.distanceKm < 1
        ? '${(driver.distanceKm * 1000).round()} m away'
        : '${driver.distanceKm.toStringAsFixed(1)} km away';
    final lastActive = _formatLastActive(driver.lastActiveAt);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SheetHandle(),
        const SizedBox(height: 16),
        Text(
          'Driver Listing',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.accentGlow,
              child: Text(
                _initialsFor(driver.displayName, fallback: 'DR'),
                style: GoogleFonts.dmSans(
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    driver.displayName,
                    style: GoogleFonts.dmSans(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    driver.vehicleType,
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _SheetChip(label: distance),
            _SheetChip(
              label: driver.isOnline ? 'Online now' : 'Offline',
              bgColor: driver.isOnline
                  ? AppColors.accentGlow
                  : AppColors.surface3,
              textColor: driver.isOnline ? AppColors.accent : AppColors.text2,
            ),
            if (driver.hasReturnTrip)
              _SheetChip(
                label: 'Has return trip',
                bgColor: AppColors.purple.withValues(alpha: 0.16),
                textColor: AppColors.purple,
              ),
            if (driver.isRegularDriver)
              _SheetChip(
                label: 'Regular driver',
                bgColor: AppColors.blueGlow,
                textColor: AppColors.blue,
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (driver.scheduledRoute?.trim().isNotEmpty ?? false)
          _DetailRow(
            label: 'Current route',
            value: driver.scheduledRoute!.trim(),
          ),
        if (driver.baseLocation?.trim().isNotEmpty ?? false)
          _DetailRow(label: 'Area', value: driver.baseLocation!.trim()),
        if (driver.vehicleStatus?.trim().isNotEmpty ?? false)
          _DetailRow(
            label: 'Vehicle status',
            value: _titleCase(driver.vehicleStatus!),
          ),
        _DetailRow(label: 'Last active', value: lastActive),
        _DetailRow(
          label: 'Chat flow',
          value: 'Price and pickup are agreed directly in WhatsApp.',
        ),
        const SizedBox(height: 18),
        _MarketplaceHint(
          text:
              'The app helps you discover nearby drivers. You agree on fare, pickup, and exact timing in WhatsApp.',
        ),
        const SizedBox(height: 18),
        if (onOpenWhatsApp != null)
          Align(
            alignment: Alignment.centerRight,
            child: WaButton(
              label: buttonLabel,
              onTap: () {
                Navigator.of(context).pop();
                onOpenWhatsApp!();
              },
            ),
          )
        else
          const _UnavailableHint(
            text: 'WhatsApp contact is not available for this driver yet.',
          ),
      ],
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 44,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.border2,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class _RouteHeadline extends StatelessWidget {
  const _RouteHeadline({required this.from, required this.to});

  final String from;
  final String to;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RoutePoint(label: from, color: AppColors.accent),
        Padding(
          padding: const EdgeInsets.only(left: 5),
          child: Container(width: 1.5, height: 16, color: AppColors.border2),
        ),
        _RoutePoint(label: to, color: AppColors.orange),
      ],
    );
  }
}

class _RoutePoint extends StatelessWidget {
  const _RoutePoint({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.text3,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.text2,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MarketplaceHint extends StatelessWidget {
  const _MarketplaceHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.blueGlow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.blue.withValues(alpha: 0.24)),
      ),
      child: Text(
        text,
        style: GoogleFonts.dmSans(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.blue,
          height: 1.45,
        ),
      ),
    );
  }
}

class _UnavailableHint extends StatelessWidget {
  const _UnavailableHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.dmSans(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.text2,
      ),
    );
  }
}

class _SheetChip extends StatelessWidget {
  const _SheetChip({
    required this.label,
    this.bgColor = AppColors.surface3,
    this.textColor = AppColors.text2,
  });

  final String label;
  final Color bgColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
      ),
    );
  }
}

String _initialsFor(String value, {required String fallback}) {
  final words = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) {
    return fallback;
  }
  if (words.length == 1) {
    final first = words.first;
    return first.length <= 2
        ? first.toUpperCase()
        : first.substring(0, 2).toUpperCase();
  }
  return '${words.first[0]}${words.last[0]}'.toUpperCase();
}

String _formatLastActive(DateTime? value) {
  if (value == null) {
    return 'Recently';
  }
  final diff = DateTime.now().difference(value);
  if (diff.inMinutes < 1) {
    return 'Just now';
  }
  if (diff.inMinutes < 60) {
    return '${diff.inMinutes} min ago';
  }
  if (diff.inHours < 24) {
    return '${diff.inHours} h ago';
  }
  return DateFormat('d MMM • HH:mm').format(value);
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

MobilityRouteTravelMode _travelModeFor(Trip trip) {
  final normalized = trip.vehicleType.trim().toLowerCase();
  if (normalized == 'moto' || normalized == 'moto taxi') {
    return MobilityRouteTravelMode.twoWheeler;
  }
  return MobilityRouteTravelMode.drive;
}

String _titleCase(String value) {
  final words = value
      .trim()
      .replaceAll('_', ' ')
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .map(
        (word) => '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
      );
  return words.join(' ');
}
