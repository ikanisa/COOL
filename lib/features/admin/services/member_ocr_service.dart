import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Parsed member entry from Gemini OCR.
class ParsedMemberEntry {
  const ParsedMemberEntry({required this.name, required this.phone});

  factory ParsedMemberEntry.fromJson(Map<String, dynamic> json) {
    return ParsedMemberEntry(
      name: json['name']?.toString().trim() ?? '',
      phone: json['phone']?.toString().trim() ?? '',
    );
  }

  final String name;
  final String phone;

  bool get isValid => name.isNotEmpty && phone.isNotEmpty;

  Map<String, String> toMemberPayload() => {
        'phone': phone,
        'display_name': name,
      };
}

/// Result of a member list OCR parse operation.
class MemberOcrResult {
  const MemberOcrResult({
    required this.members,
    required this.count,
    this.error,
  });

  final List<ParsedMemberEntry> members;
  final int count;
  final String? error;

  bool get hasError => error != null;
}

/// Service that uploads an image/PDF to the `parse-member-list` edge function
/// and returns structured member data parsed by Gemini Vision.
class MemberOcrService {
  MemberOcrService({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  /// Parses a member list image.
  ///
  /// [imageBytes] is the raw image data (JPEG, PNG, or PDF).
  /// [mimeType] should be `image/jpeg`, `image/png`, or `application/pdf`.
  ///
  /// Returns a [MemberOcrResult] with the parsed members.
  Future<MemberOcrResult> parseMemberListImage({
    required Uint8List imageBytes,
    String mimeType = 'image/jpeg',
  }) async {
    try {
      final base64Image = base64Encode(imageBytes);

      final response = await _client.functions.invoke(
        'parse-member-list',
        body: <String, dynamic>{
          'image_base64': base64Image,
          'mime_type': mimeType,
        },
      );

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        return const MemberOcrResult(
          members: [],
          count: 0,
          error: 'Invalid response from OCR service',
        );
      }

      if (data['success'] != true) {
        return MemberOcrResult(
          members: const [],
          count: 0,
          error: data['message']?.toString() ?? 'OCR parsing failed',
        );
      }

      final rawMembers = data['members'];
      if (rawMembers is! List) {
        return const MemberOcrResult(members: [], count: 0);
      }

      final members = rawMembers
          .whereType<Map<String, dynamic>>()
          .map(ParsedMemberEntry.fromJson)
          .where((m) => m.isValid)
          .toList(growable: false);

      return MemberOcrResult(
        members: members,
        count: members.length,
      );
    } catch (e) {
      return MemberOcrResult(
        members: const [],
        count: 0,
        error: e.toString(),
      );
    }
  }
}
