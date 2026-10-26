import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Public protocol identity, never an authentication secret. It binds the
/// cookie Admin's request alias to the canonical principal and original key.
String canonicalAdminRequestId(String principalId, String key) {
  if (!RegExp(
        r'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$',
      ).hasMatch(principalId) ||
      !RegExp(r'^[A-Za-z0-9_.-]{8,200}$').hasMatch(key)) {
    throw const FormatException('Invalid canonical request identity.');
  }
  final value = sha256
      .convert(utf8.encode('collect-admin:$principalId:$key'))
      .toString();
  return '${value.substring(0, 8)}-${value.substring(8, 12)}-4${value.substring(13, 16)}-8${value.substring(17, 20)}-${value.substring(20, 32)}';
}
