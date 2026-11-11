import 'package:flutter/material.dart';

import '../../../app/theme/collect_colors.dart';
import '../../../app/theme/collect_radius.dart';
import '../../../app/theme/collect_typography.dart';

/// A responsive, accessible detail view for one operational record.
///
/// It deliberately separates decisions and source facts from technical
/// provenance. Values are supplied by the owning feature after its privacy
/// projection; this widget never decides who may access protected information.
class AdminRecordFact {
  const AdminRecordFact({required this.label, required this.value});

  final String label;
  final String value;
}

class AdminRecordFactsPanel extends StatelessWidget {
  const AdminRecordFactsPanel({
    required this.title,
    required this.summary,
    this.supporting = const <AdminRecordFact>[],
    this.technical = const <AdminRecordFact>[],
    super.key,
  });

  final String title;
  final List<AdminRecordFact> summary;
  final List<AdminRecordFact> supporting;
  final List<AdminRecordFact> technical;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      container: true,
      label: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: colors.textPrimary,
              fontWeight: CollectTypography.weightSemibold,
            ),
          ),
          const SizedBox(height: 14),
          _FactGroup(facts: summary),
          if (supporting.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Extracted and linked facts',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: colors.textPrimary,
                fontWeight: CollectTypography.weightSemibold,
              ),
            ),
            const SizedBox(height: 10),
            _FactGroup(facts: supporting),
          ],
          if (technical.isNotEmpty) ...[
            const SizedBox(height: 18),
            Material(
              color: colors.surfaceReadable,
              shape: RoundedRectangleBorder(
                borderRadius: CollectRadius.cardBorder,
                side: BorderSide(color: colors.borderSoft),
              ),
              child: ExpansionTile(
                key: const Key('admin-record-technical-provenance'),
                title: const Text('Technical source provenance'),
                subtitle: const Text('Identifiers, parser metadata and source digests'),
                childrenPadding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                children: [_FactGroup(facts: technical)],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FactGroup extends StatelessWidget {
  const _FactGroup({required this.facts});
  final List<AdminRecordFact> facts;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final textSize = Theme.of(context).textTheme.bodyMedium?.fontSize ?? 14.0;
        final enlarged = MediaQuery.textScalerOf(context).scale(textSize) > 21;
        // Allow facts to use the full width at 320px and during text enlargement.
        final twoColumns = constraints.maxWidth >= 700 && !enlarged;
        final itemWidth = twoColumns
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final fact in facts)
              SizedBox(
                width: itemWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceReadable,
                    border: Border.all(color: colors.borderSoft),
                    borderRadius: CollectRadius.cardBorder,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // The selectable value supplies the full field label
                        // to assistive technology; avoid a duplicate heading.
                        ExcludeSemantics(
                          child: Text(
                            fact.label,
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(color: colors.textSecondary),
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Preserve SelectableText's native screen-reader,
                        // focus, long-press and copy actions. Masking decisions
                        // happen in the owning record's privacy projection.
                        Semantics(
                          label: '${fact.label}:',
                          child: SelectableText(
                            fact.value,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colors.textPrimary,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
