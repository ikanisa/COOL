part of 'momo_sms_autoread_service.dart';

typedef MomoSmsPermissionStatusReader = Future<PermissionStatus> Function();
typedef MomoSmsPermissionRequester = Future<PermissionStatus> Function();
typedef MomoSmsAutoreadSupportChecker = bool Function();

enum MomoInboxSyncTrigger { initialPermissionGrant, manual }

class MomoInboxSyncResult {
  const MomoInboxSyncResult({
    required this.scannedMessages,
    required this.uploadedMessages,
    required this.duplicateMessages,
    this.oldestMessageAt,
    this.newestMessageAt,
    this.incremental = false,
  });

  final int scannedMessages;
  final int uploadedMessages;
  final int duplicateMessages;
  final DateTime? oldestMessageAt;
  final DateTime? newestMessageAt;
  final bool incremental;
}

class MomoSmsSyncException implements Exception {
  const MomoSmsSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

String _momoSmsSyncTriggerValue(MomoInboxSyncTrigger trigger) {
  return switch (trigger) {
    MomoInboxSyncTrigger.initialPermissionGrant => 'initial_permission_grant',
    MomoInboxSyncTrigger.manual => 'manual',
  };
}

DateTime? _newerOf(DateTime? left, DateTime? right) {
  if (left == null) {
    return right;
  }
  if (right == null) {
    return left;
  }
  return left.isAfter(right) ? left : right;
}

List<String> _normalizeApprovedSenderTokens(Iterable<String> tokens) {
  return tokens
      .map(_normalizeSenderToken)
      .where((String token) => token.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
}

String _normalizeSenderToken(String raw) {
  return raw.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9]'), '');
}
