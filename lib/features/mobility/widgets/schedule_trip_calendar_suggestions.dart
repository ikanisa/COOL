import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/engagement_providers.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_card.dart';
import '../providers/calendar_suggestions_provider.dart';

class ScheduleTripCalendarSuggestions extends ConsumerWidget {
  const ScheduleTripCalendarSuggestions({
    required this.onSuggestionSelected,
    super.key,
  });

  final ValueChanged<String> onSuggestionSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final suggestionsAsync = ref.watch(calendarSuggestionsProvider);

    return suggestionsAsync.when(
      data: (suggestions) {
        if (suggestions.isEmpty) return const SizedBox.shrink();

        return CoolCard(
          backgroundColor: colors.routeSurface,
          borderColor: colors.borderStrong,
          useGradient: false,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.calendar_month_rounded,
                    size: 20,
                    color: colors.accent,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Upcoming events',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colors.primaryText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colors.chipSelectedBackground,
                      borderRadius: BorderRadius.circular(CoolRadii.sm),
                      border: Border.all(color: colors.border),
                    ),
                    child: Text(
                      'Calendar',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.secondaryText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: suggestions.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final suggestion = suggestions[index];
                    return Material(
                      color: colors.cardSurfaceStrong,
                      borderRadius: BorderRadius.circular(CoolRadii.md),
                      child: InkWell(
                        onTap: () {
                          ref
                              .read(engagementTrackerProvider)
                              .trackCalendarSuggestionSelected(
                                suggestionTitle: suggestion.title,
                              );
                          onSuggestionSelected(suggestion.promptText);
                        },
                        borderRadius: BorderRadius.circular(CoolRadii.md),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: colors.cardSurfaceStrong,
                            borderRadius: BorderRadius.circular(CoolRadii.md),
                            border: Border.all(color: colors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                suggestion.title,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colors.primaryText,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Icon(
                                    Icons.schedule,
                                    size: 12,
                                    color: colors.tertiaryText,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    suggestion.timeLabel,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.tertiaryText,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}
