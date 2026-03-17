import 'package:cool_app/core/models/geo_point.dart';
import 'package:cool_app/core/theme/cool_palette.dart';
import 'package:cool_app/features/mobility/models/mobility_route_preview.dart';
import 'package:cool_app/shared/widgets/cool_card.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
    final palette = context.coolPalette;
    final hasAnyPoint = origin != null || destination != null;

    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Route summary',
                style: GoogleFonts.dmSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: palette.text,
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
          const SizedBox(height: 8),
          Text(
            preview == null ? 'Resolve both points' : 'Review before posting',
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: palette.text2,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: palette.surface3,
              borderRadius: BorderRadius.circular(18),
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
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: palette.text2,
                      height: 1.45,
                    ),
                  ),
          ),
          if (error?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 10),
            Text(
              error!.trim(),
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: palette.orange,
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
        const SizedBox(height: 12),
        _RouteStopRow(
          icon: Icons.place_outlined,
          label: context.l10n.dropoff,
          value: destinationLabel,
        ),
        if (preview != null) ...[
          const SizedBox(height: 16),
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
    final palette = context.coolPalette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: palette.text2),
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
                  color: palette.text3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value.trim().isEmpty ? 'Not set yet' : value.trim(),
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: palette.text,
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
    final palette = context.coolPalette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: palette.accent),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: palette.text,
            ),
          ),
        ],
      ),
    );
  }
}