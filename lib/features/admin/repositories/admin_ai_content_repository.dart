import 'package:supabase_flutter/supabase_flutter.dart';

final class AdminAiContentGenerationConfig {
  const AdminAiContentGenerationConfig({
    required this.isEnabled,
    this.intervalHours,
    this.lastGeneratedAt,
  });

  factory AdminAiContentGenerationConfig.fromJson(Map<String, dynamic> json) {
    return AdminAiContentGenerationConfig(
      isEnabled: json['is_enabled'] as bool? ?? false,
      intervalHours: json['interval_hours'] as int?,
      lastGeneratedAt: json['last_generated_at'] != null
          ? DateTime.tryParse(json['last_generated_at'].toString())
          : null,
    );
  }

  final bool isEnabled;
  final int? intervalHours;
  final DateTime? lastGeneratedAt;
}

final class AdminAiContentGenerationResult {
  const AdminAiContentGenerationResult({
    required this.success,
    this.title,
    this.reason,
  });

  factory AdminAiContentGenerationResult.fromJson(Map<String, dynamic> json) {
    return AdminAiContentGenerationResult(
      success: json['success'] as bool? ?? false,
      title: json['title']?.toString(),
      reason: json['reason']?.toString(),
    );
  }

  final bool success;
  final String? title;
  final String? reason;
}

class AdminAiContentRepository {
  AdminAiContentRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  Future<AdminAiContentGenerationConfig?> fetchGenerationConfig() async {
    final rows = await _client
        .from('ai_content_generation_config')
        .select()
        .limit(1);
    if (rows.isEmpty) {
      return null;
    }

    return AdminAiContentGenerationConfig.fromJson(
      Map<String, dynamic>.from(rows.first as Map),
    );
  }

  Future<void> setGenerationEnabled(bool enabled) async {
    await _client
        .from('ai_content_generation_config')
        .update({
          'is_enabled': enabled,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'updated_by': _client.auth.currentUser?.id,
        })
        .not('id', 'is', null);
  }

  Future<AdminAiContentGenerationResult> triggerManualGeneration() async {
    final response = await _client.functions.invoke(
      'generate-ai-content',
      queryParameters: <String, String>{'manual': 'true'},
    );
    final data = response.data;
    if (data is Map) {
      return AdminAiContentGenerationResult.fromJson(
        Map<String, dynamic>.from(data),
      );
    }

    return const AdminAiContentGenerationResult(
      success: false,
      reason: 'Invalid generation response.',
    );
  }
}
