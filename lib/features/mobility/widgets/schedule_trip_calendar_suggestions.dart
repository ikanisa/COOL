import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/providers/engagement_providers.dart';
import '../../../core/theme/cool_palette.dart';
import '../../../shared/widgets/cool_card.dart';
import '../providers/calendar_suggestions_provider.dart';

class ScheduleTripCalendarSuggestions extends ConsumerWidget {
  const ScheduleTripCalendarSuggestions({
    required this.onSuggestionSelected,
    super.key,
  });

  /// The full prompt string to inject into the text box and optionally parse
  final ValueChanged<String> onSuggestionSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.coolPalette;
    final suggestionsAsync = ref.watch(calendarSuggestionsProvider);

    return suggestionsAsync.when(
      data: (suggestions) {
        if (suggestions.isEmpty) return const SizedBox.shrink();

        final palette = context.coolPalette;
        return CoolCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.calendar_month_rounded,
                      size: 20, color: palette.accent),
                  const SizedBox(width: 8),
                  Text(
                    'Upcoming Events',
                    style: GoogleFonts.dmSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: palette.text,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: palette.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Calendar',
                      style: GoogleFonts.dmSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: palette.accent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 70,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: suggestions.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final s = suggestions[index];
                    return InkWell(
                      onTap: () {
                        ref.read(engagementTrackerProvider)
                            .trackCalendarSuggestionSelected(
                          suggestionTitle: s.title,
                        );
                        onSuggestionSelected(s.promptText);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: palette.surface3,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: palette.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              s.title,
                              style: GoogleFonts.dmSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: palette.text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(Icons.schedule,
                                    size: 12, color: palette.text3),
                                const SizedBox(width: 4),
                                Text(
                                  s.timeLabel,
                                  style: GoogleFonts.dmSans(
                                    fontSize: 12,
                                    color: palette.text3,
                                  ),
                                ),
                              ],
                            ),
                          ],
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
