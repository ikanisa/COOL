import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_card.dart';

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
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    return CoolCard(
      backgroundColor: colors.routeSurface,
      borderColor: colors.borderStrong,
      useGradient: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
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
          _TripReviewItem(
            label: context.l10n.preview,
            value: previewLabel,
            isLast: true,
          ),
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
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    return Semantics(
      container: true,
      label:
          '$title. $visibilityLabel: $visibilityValue. $precisionLabel: $precisionValue. '
          '$coordinationLabel: $coordinationValue. $offlineLabel: $offlineValue.',
      child: CoolCard(
        backgroundColor: colors.routeSurface,
        borderColor: colors.borderStrong,
        useGradient: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: colors.primaryText,
                fontWeight: FontWeight.w800,
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
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.tertiaryText,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.primaryText,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
