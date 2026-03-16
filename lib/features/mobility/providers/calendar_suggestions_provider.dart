import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/engagement_providers.dart';
import '../../../core/providers/supabase_client_provider.dart';
import 'mobility_location_provider.dart';

class TripSuggestion {
  const TripSuggestion({
    required this.title,
    required this.promptText,
    required this.timeLabel,
  });

  final String title;
  final String promptText;
  final String timeLabel;

  factory TripSuggestion.fromJson(Map<String, dynamic> json) {
    return TripSuggestion(
      title: json['title'] as String? ?? 'Upcoming event',
      promptText: json['promptText'] as String? ?? '',
      timeLabel: json['timeLabel'] as String? ?? '',
    );
  }
}

final calendarSuggestionsProvider =
    FutureProvider<List<TripSuggestion>>((ref) async {
  final supabase = ref.read(supabaseClientProvider);
  final locationState = ref.read(mobilityLocationProvider);

  try {
    // Execute Edge Function that securely fetches from GWS APIs using a Service Account
    // and returns them structurally parsed via Gemini.
    final response = await supabase.functions.invoke(
      'fetch-workspace-calendar',
      body: {
        'latitude': locationState.position?.latitude,
        'longitude': locationState.position?.longitude,
        'timezone': DateTime.now().timeZoneName,
      },
    );

    if (response.status == 200) {
      final jsonResponse = response.data as Map<String, dynamic>;
      
      if (jsonResponse['success'] == true && jsonResponse['data'] != null) {
        final dataList = jsonResponse['data'] as List<dynamic>;
        return dataList
            .map((item) => TripSuggestion.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    }
  } catch (e, stack) {
    // Calendar is progressive enhancement — return empty on failure, but log
    // so failures are observable in Crashlytics.
    ref.read(crashlyticsServiceProvider).recordError(
      e,
      stackTrace: stack,
      reason: 'calendar_suggestions_fetch_failed',
    );
    return [];
  }

  return [];
});
