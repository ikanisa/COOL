import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/supabase_client_provider.dart';

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

final calendarSuggestionsProvider = FutureProvider<List<TripSuggestion>>((ref) async {
  final supabase = ref.read(supabaseClientProvider);

  try {
    // Execute Edge Function that securely fetches from GWS APIs using a Service Account 
    // and returns them structurally parsed via Gemini.
    final response = await supabase.functions.invoke('fetch-workspace-calendar');

    if (response.status == 200) {
      final jsonResponse = response.data as Map<String, dynamic>;
      
      if (jsonResponse['success'] == true && jsonResponse['data'] != null) {
        final dataList = jsonResponse['data'] as List<dynamic>;
        return dataList
            .map((item) => TripSuggestion.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    }
  } catch (e) {
    // Silent degradation returning empty list; calendar is treated as a progressive enhancement.
    return [];
  }

  return [];
});
