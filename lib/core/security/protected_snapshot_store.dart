import 'dart:convert';
import 'package:flutter/services.dart';

/// Optional recovery cache, never the ledger. Web/unsupported hosts do not fall
/// back to plaintext. The native layer owns keys and persists only ciphertext.
class ProtectedSnapshotStore {
  const ProtectedSnapshotStore();
  static const _channel = MethodChannel('collect/secure_snapshot');
  static const maximumBytes = 1024 * 1024;
  static final _owner = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  Future<String?> read(String ownerId) async {
    if (!_owner.hasMatch(ownerId)) return null;
    try {
      final result = await _channel.invokeMethod<String>('read', {
        'owner_id': ownerId.toLowerCase(),
      });
      if (result != null && utf8.encode(result).length > maximumBytes) {
        throw const FormatException(
          'Protected snapshot exceeds the cache limit',
        );
      }
      return result;
    } on MissingPluginException {
      return null;
    }
  }

  Future<bool> write(String ownerId, String value) async {
    if (!_owner.hasMatch(ownerId) || utf8.encode(value).length > maximumBytes) {
      throw const FormatException('Invalid protected snapshot');
    }
    try {
      return await _channel.invokeMethod<bool>('write', {
            'owner_id': ownerId.toLowerCase(),
            'value': value,
          }) ==
          true;
    } on MissingPluginException {
      // No persistent financial cache on a platform lacking protected storage.
      return false;
    }
  }

  Future<void> clear() async {
    try {
      if (await _channel.invokeMethod<bool>('clear') != true) {
        throw StateError('Protected snapshot could not be cleared');
      }
    } on MissingPluginException {
      // Unsupported hosts never persist a snapshot through this bridge.
    }
  }
}
