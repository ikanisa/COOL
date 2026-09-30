import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'durable_sms_receipt.dart';

class SmsAccessEnvelope {
  const SmsAccessEnvelope({
    required this.id,
    required this.ownerUserId,
    required this.rawSender,
    required this.rawBody,
    required this.receivedAtDevice,
  });

  factory SmsAccessEnvelope.fromMap(Map<dynamic, dynamic> map) {
    return SmsAccessEnvelope(
      id: (map['id'] as String?) ?? '',
      ownerUserId: (map['owner_user_id'] as String?) ?? '',
      rawSender: (map['raw_sender'] as String?) ?? 'android_sms',
      rawBody: (map['raw_body'] as String?) ?? '',
      receivedAtDevice: (map['received_at_device'] as String?) ?? '',
    );
  }

  final String id;
  final String ownerUserId;
  final String rawSender;
  final String rawBody;
  final String receivedAtDevice;
}

class SmsAccessStatus {
  const SmsAccessStatus({
    required this.supported,
    required this.declared,
    required this.enabled,
    this.consentEnabled = false,
    this.bridgeAvailable = true,
    required this.granted,
    required this.requestedBefore,
    required this.shouldShowRationale,
    required this.permanentlyDenied,
    required this.queueOverflowed,
    this.queueUnavailable = false,
  });

  const SmsAccessStatus.unavailable()
    : supported = false,
      declared = false,
      enabled = false,
      consentEnabled = false,
      bridgeAvailable = false,
      granted = false,
      requestedBefore = false,
      shouldShowRationale = false,
      permanentlyDenied = false,
      queueOverflowed = false,
      queueUnavailable = false;

  factory SmsAccessStatus.fromMap(Map<dynamic, dynamic> map) {
    bool value(String key) => map[key] == true;
    return SmsAccessStatus(
      supported: value('supported'),
      declared: value('declared'),
      enabled: value('enabled'),
      consentEnabled: value('consent_enabled'),
      bridgeAvailable: true,
      granted: value('granted'),
      requestedBefore: value('requested_before'),
      shouldShowRationale: value('should_show_rationale'),
      permanentlyDenied: value('permanently_denied'),
      queueOverflowed: value('queue_overflowed'),
      queueUnavailable: value('queue_unavailable'),
    );
  }

  final bool supported;
  final bool declared;
  final bool enabled;

  /// Stored native capture flag, even if Android permission is temporarily off.
  final bool consentEnabled;
  final bool bridgeAvailable;
  final bool granted;
  final bool requestedBefore;
  final bool shouldShowRationale;
  final bool permanentlyDenied;
  final bool queueOverflowed;
  final bool queueUnavailable;
}

class SmsAccessChannel {
  const SmsAccessChannel();

  static bool get requiresNativeBridge =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static const MethodChannel _channel = MethodChannel('collect/sms_access');
  static const EventChannel _events = EventChannel('collect/sms_access/events');

  /// Metadata-only queue invalidations. Raw SMS stays behind the consent-gated
  /// method channel and is read only when an authenticated drain begins.
  Stream<void> get pendingSmsEvents => _events
      .receiveBroadcastStream()
      .where((event) => event is Map && event['type'] == 'pending_sms')
      .map((_) {});

  Future<bool> setEnabled(bool enabled, {String? ownerUserId}) async {
    try {
      return await _channel.invokeMethod<bool>('setEnabled', {
            'enabled': enabled,
            'owner_user_id': ownerUserId,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isEnabled') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> suspendUnlessOwner(String? currentUserId) async {
    try {
      return await _channel.invokeMethod<bool>('suspendUnlessOwner', {
            'current_user_id': currentUserId,
          }) ??
          false;
    } on MissingPluginException {
      return !requiresNativeBridge;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<SmsAccessStatus> status() async {
    try {
      final result = await _channel.invokeMapMethod<dynamic, dynamic>('status');
      return result == null
          ? const SmsAccessStatus.unavailable()
          : SmsAccessStatus.fromMap(result);
    } on MissingPluginException {
      return const SmsAccessStatus.unavailable();
    } on PlatformException catch (error) {
      final details = error.details;
      return details is Map
          ? SmsAccessStatus.fromMap(details)
          : const SmsAccessStatus.unavailable();
    } catch (_) {
      return const SmsAccessStatus.unavailable();
    }
  }

  Future<List<SmsAccessEnvelope>> readPendingSms({
    required String ownerUserId,
  }) async {
    if (ownerUserId.trim().isEmpty) {
      throw StateError('An authenticated receipt owner is required.');
    }
    final result = await _channel.invokeListMethod<Object?>('readPendingSms', {
      'owner_user_id': ownerUserId,
    });
    if (result == null) throw StateError('Secure receipt queue unavailable.');
    final envelopes = <SmsAccessEnvelope>[];
    for (final row in result) {
      if (row is! Map) {
        throw const FormatException('Secure receipt queue needs review.');
      }
      final envelope = SmsAccessEnvelope.fromMap(row);
      if (envelope.id.isEmpty ||
          envelope.ownerUserId != ownerUserId ||
          envelope.rawBody.trim().isEmpty) {
        throw const FormatException('Secure receipt queue needs review.');
      }
      envelopes.add(envelope);
    }
    return List.unmodifiable(envelopes);
  }

  Future<bool> acknowledgeDurableReceipt(DurableSmsReceipt receipt) async {
    try {
      return await _channel.invokeMethod<bool>('ackPendingSms', {
            'owner_user_id': receipt.ownerUserId,
            'ids': [receipt.envelopeId],
            'body_hashes': {receipt.envelopeId: receipt.bodySha256},
            'contract_version': 2,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @Deprecated(
    'Use acknowledgeDurableReceipt with a validated server acknowledgement.',
  )
  Future<bool> acknowledgePendingSms(Iterable<String> ids) async => ids.isEmpty;

  Future<bool> openAppSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openAppSettings') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
