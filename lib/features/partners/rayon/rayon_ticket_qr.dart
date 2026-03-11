import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

const _rayonTicketQrPrefix = 'COOL-TKT:';
const _rayonTicketQrSecret = String.fromEnvironment(
  'TICKET_QR_HMAC_SECRET',
  defaultValue: '',
);

/// Fallback secret used only in debug/test mode when the real secret is
/// not provided via --dart-define. In release mode we always require the
/// real secret.
const _debugFallbackSecret = 'debug-ticket-qr-hmac-placeholder';

bool isSignedRayonTicketQr(String value) {
  return value.trim().startsWith(_rayonTicketQrPrefix);
}

String buildRayonTicketQrData({
  required String ticketId,
  required String matchId,
  required DateTime purchasedAt,
}) {
  final secret = _resolveTicketQrSecret();
  final timestampMs = purchasedAt.millisecondsSinceEpoch.toString();
  final payload = '$ticketId:$matchId:$timestampMs';
  final digest = Hmac(
    sha256,
    utf8.encode(secret),
  ).convert(utf8.encode(payload));

  return '$_rayonTicketQrPrefix$payload:${digest.toString().substring(0, 12)}';
}

String _resolveTicketQrSecret() {
  final secret = _rayonTicketQrSecret.trim();
  if (secret.isNotEmpty) {
    return secret;
  }

  if (kDebugMode) {
    return _debugFallbackSecret;
  }

  throw StateError('TICKET_QR_HMAC_SECRET is not configured.');
}

