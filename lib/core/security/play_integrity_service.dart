import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PlayIntegrityUnavailable implements Exception {
  const PlayIntegrityUnavailable(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'PlayIntegrityUnavailable($code, $message)';
}

class PlayIntegrityVerdict {
  const PlayIntegrityVerdict({
    required this.status,
    required this.action,
    required this.requestHash,
    required this.packageName,
    required this.appVerdict,
    required this.deviceVerdicts,
    required this.licensingVerdict,
    required this.timestampMillis,
  });

  factory PlayIntegrityVerdict.fromMap(Map<dynamic, dynamic> map) {
    return PlayIntegrityVerdict(
      status: (map['status'] as String?) ?? 'unknown',
      action: (map['action'] as String?) ?? 'unknown',
      requestHash: (map['request_hash'] as String?) ?? '',
      packageName: (map['package_name'] as String?) ?? '',
      appVerdict: (map['app_verdict'] as String?) ?? 'UNKNOWN',
      deviceVerdicts: [
        for (final item in (map['device_verdicts'] as List<dynamic>? ?? const []))
          if (item is String) item,
      ],
      licensingVerdict: (map['licensing_verdict'] as String?) ?? 'UNKNOWN',
      timestampMillis: (map['timestamp_millis'] as int?) ?? 0,
    );
  }

  final String status;
  final String action;
  final String requestHash;
  final String packageName;
  final String appVerdict;
  final List<String> deviceVerdicts;
  final String licensingVerdict;
  final int timestampMillis;

  bool get passed => status == 'pass';
}

class PlayIntegrityService {
  const PlayIntegrityService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('collect/play_integrity');

  final MethodChannel _channel;

  String buildRequestHash({
    required String action,
    required String subjectId,
    required String nonce,
  }) {
    final payload = jsonEncode({
      'action': action,
      'subject_id': subjectId,
      'nonce': nonce,
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
        error.message ?? 'Play Integrity token request failed',
      );
    }
  }

  Future<PlayIntegrityVerdict?> verifyWithServer({
    required SupabaseClient supabase,
    required String action,
    required String requestHash,
    required String integrityToken,
  }) async {
    final response = await supabase.functions.invoke(
      'verify-play-integrity',
      body: {
        'action': action,
        'request_hash': requestHash,
        'integrity_token': integrityToken,
      },
    );
    final data = response.data;
    if (data is Map<dynamic, dynamic>) {
      return PlayIntegrityVerdict.fromMap(data);
    }
    return null;
  }
}
