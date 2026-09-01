import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PlayIntegrityUnavailable implements Exception {
  const PlayIntegrityUnavailable(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

class PlayIntegrityVerdict {
  const PlayIntegrityVerdict({
    required this.status,
    required this.nativeCapability,
    required this.capabilityExpiresAt,
  });

  factory PlayIntegrityVerdict.fromMap(Map<dynamic, dynamic> map) {
    return PlayIntegrityVerdict(
      status: (map['status'] as String?) ?? 'unknown',
      nativeCapability: map['native_capability'] as String?,
      capabilityExpiresAt: DateTime.tryParse(
        (map['capability_expires_at'] as String?) ?? '',
      ),
    );
  }

  final String status;
  final String? nativeCapability;
  final DateTime? capabilityExpiresAt;

  bool get hasUsableNativeCapability =>
      status == 'pass' &&
      nativeCapability?.isNotEmpty == true &&
      capabilityExpiresAt?.isAfter(DateTime.now().toUtc()) == true;
}

class PlayIntegrityService {
  const PlayIntegrityService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('collect/play_integrity');

  final MethodChannel _channel;

  String buildGroupCreationRequestHash({
    required String subjectId,
    required String nonce,
    required String receiverMomoNumberHash,
    required bool smsPermissionGranted,
    required bool smsAccessEnabled,
    required Map<String, Object?> groupRequest,
  }) {
    final payload = jsonEncode({
      'action': 'group.create',
      'subject_id': subjectId,
      'nonce': nonce,
      'receiver_momo_number_hash': receiverMomoNumberHash,
      'sms_permission_granted': smsPermissionGranted,
      'sms_access_enabled': smsAccessEnabled,
      'group_request': groupRequest,
    });
    return sha256.convert(utf8.encode(payload)).toString();
  }

  Future<String?> requestStandardToken({required String requestHash}) async {
    try {
      return await _channel.invokeMethod<String>('requestStandardToken', {
        'request_hash': requestHash,
      });
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      if (error.code == 'play_integrity_not_configured') return null;
      throw PlayIntegrityUnavailable(
        error.code,
        error.message ?? 'Play Integrity token request failed.',
      );
    }
  }

  Future<PlayIntegrityVerdict?> verifyWithServer({
    required SupabaseClient supabase,
    required String requestHash,
    required String integrityToken,
    required String subjectId,
    required String nonce,
    required String receiverMomoNumberHash,
    required Map<String, Object?> groupRequest,
  }) async {
    final response = await supabase.functions.invoke(
      'verify-play-integrity',
      body: {
        'action': 'group.create',
        'request_hash': requestHash,
        'integrity_token': integrityToken,
        'subject_id': subjectId,
        'nonce': nonce,
        'receiver_momo_number_hash': receiverMomoNumberHash,
        'sms_permission_granted': true,
        'sms_access_enabled': true,
        'group_request': groupRequest,
      },
    );
    final data = response.data;
    return data is Map<dynamic, dynamic>
        ? PlayIntegrityVerdict.fromMap(data)
        : null;
  }
}
