import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/cool_palette.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../core/l10n/l10n.dart';

/// Summary card displayed on the review step of Schedule Trip.
class ScheduleTripReviewCard extends StatelessWidget {
  const ScheduleTripReviewCard({
    required this.title,
    required this.subtitle,
    required this.roleFieldLabel,
    required this.roleLabel,
    required this.routeLabel,
    required this.departureLabel,
    required this.vehicleLabel,
    required this.seatsFieldLabel,
    required this.seatsLabel,
    required this.returnLabel,
    required this.recurringLabel,
    required this.detailsFieldLabel,
    required this.detailsLabel,
    required this.previewLabel,
    super.key,
  });

  final String title;
  final String subtitle;
  final String roleFieldLabel;
  final String roleLabel;
  final String routeLabel;
  final String departureLabel;
  final String vehicleLabel;
  final String seatsFieldLabel;
  final String seatsLabel;
  final String returnLabel;
  final String recurringLabel;
  final String detailsFieldLabel;
  final String detailsLabel;
  final String previewLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 16),
          _TripReviewItem(label: roleFieldLabel, value: roleLabel),
          _TripReviewItem(label: context.l10n.route, value: routeLabel),
          _TripReviewItem(label: context.l10n.departure, value: departureLabel),
          _TripReviewItem(label: context.l10n.vehicle, value: vehicleLabel),
          _TripReviewItem(label: seatsFieldLabel, value: seatsLabel),
          _TripReviewItem(label: context.l10n.returnKey, value: returnLabel),
          _TripReviewItem(label: context.l10n.repeat, value: recurringLabel),
          _TripReviewItem(label: detailsFieldLabel, value: detailsLabel),
          _TripReviewItem(label: context.l10n.preview, value: previewLabel, isLast: true),
        ],
      ),
    );
  }
}

class ScheduleTripPostingGuideCard extends StatelessWidget {
  const ScheduleTripPostingGuideCard({
    required this.title,
    required this.subtitle,
    required this.visibilityLabel,
    required this.visibilityValue,
    required this.precisionLabel,
    required this.precisionValue,
    required this.coordinationLabel,
    required this.coordinationValue,
    required this.offlineLabel,
    required this.offlineValue,
    super.key,
  });

  final String title;
  final String subtitle;
  final String visibilityLabel;
  final String visibilityValue;
  final String precisionLabel;
  final String precisionValue;
  final String coordinationLabel;
  final String coordinationValue;
  final String offlineLabel;
  final String offlineValue;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Semantics(
      container: true,
      label:
          'title visibilityLabel visibilityValue precisionLabel'
          '$coordinationLabel: $coordinationValue. $offlineLabel: $offlineValue.',
      child: CoolCard(
        backgroundColor: palette.surface,
        borderColor: palette.accent.withValues(alpha: 0.16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.dmSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: palette.text,
              ),
            ),
            const SizedBox(height: 16),
            _TripReviewItem(label: visibilityLabel, value: visibilityValue),
            _TripReviewItem(label: precisionLabel, value: precisionValue),
            _TripReviewItem(label: coordinationLabel, value: coordinationValue),
            _TripReviewItem(
              label: offlineLabel,
              value: offlineValue,
              isLast: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _TripReviewItem extends StatelessWidget {
  const _TripReviewItem({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: palette.text3,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: palette.text,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}