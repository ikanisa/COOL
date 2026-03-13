import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_card.dart';

/// Summary card displayed on the review step of Schedule Trip.
class ScheduleTripReviewCard extends StatelessWidget {
  const ScheduleTripReviewCard({
    required this.roleLabel,
    required this.routeLabel,
    required this.departureLabel,
    required this.vehicleLabel,
    required this.seatsLabel,
    required this.returnLabel,
    required this.recurringLabel,
    required this.detailsLabel,
    required this.previewLabel,
    super.key,
  });

  final String roleLabel;
  final String routeLabel;
  final String departureLabel;
  final String vehicleLabel;
  final String seatsLabel;
  final String returnLabel;
  final String recurringLabel;
  final String detailsLabel;
  final String previewLabel;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Review',
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Check the main trip details before posting.',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: AppColors.text2,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          _TripReviewItem(label: 'Role', value: roleLabel),
          _TripReviewItem(label: 'Route', value: routeLabel),
          _TripReviewItem(label: 'Departure', value: departureLabel),
          _TripReviewItem(label: 'Vehicle', value: vehicleLabel),
          _TripReviewItem(label: 'Seats', value: seatsLabel),
          _TripReviewItem(label: 'Return', value: returnLabel),
          _TripReviewItem(label: 'Repeat', value: recurringLabel),
          _TripReviewItem(label: 'Details', value: detailsLabel),
          _TripReviewItem(label: 'Preview', value: previewLabel, isLast: true),
        ],
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
                color: AppColors.text3,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
