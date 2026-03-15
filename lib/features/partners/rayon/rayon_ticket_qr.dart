import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

const _rayonTicketQrPrefix = 'COOL-TKT:';
const _rayonTicketQrSecret = String.fromEnvironment(
  'TICKET_QR_HMAC_SECRET',
  defaultValue: '',
);
String? _debugTicketQrSecretOverride;

bool isSignedRayonTicketQr(String value) {
  return value.trim().startsWith(_rayonTicketQrPrefix);
}

String buildRayonTicketQrData({
  required String ticketId,
  required String matchId,
  required DateTime purchasedAt,
  String? debugSecretOverride,
}) {
  final secret = _resolveTicketQrSecret(
    debugSecretOverride: debugSecretOverride,
  );
  final timestampMs = purchasedAt.millisecondsSinceEpoch.toString();
  final payload = '$ticketId:$matchId:$timestampMs';
  final digest = Hmac(
    sha256,
    utf8.encode(secret),
  ).convert(utf8.encode(payload));

  return '$_rayonTicketQrPrefix$payload:${digest.toString().substring(0, 12)}';
}

@visibleForTesting
void debugSetRayonTicketQrSecretOverride(String? secret) {
  _debugTicketQrSecretOverride = secret;
}

String _resolveTicketQrSecret({String? debugSecretOverride}) {
  final secret = _rayonTicketQrSecret.trim();
  if (secret.isNotEmpty) {
    return secret;
  }

  final override = (debugSecretOverride ?? _debugTicketQrSecretOverride)
      ?.trim();
  if (override != null && override.isNotEmpty) {
    return override;
  }

  throw StateError('TICKET_QR_HMAC_SECRET is not configured.');
}
