import 'dart:async';

import 'package:flutter/foundation.dart';

import 'momo_sms_permission_service.dart';
import 'momo_sms_parser.dart';

/// Listens for incoming SMS and emits [MomoTransaction]s when a MoMo
/// confirmation message is detected.
///
/// SMS reading has been disabled for initial Play Store release.
/// The listener gracefully no-ops — all methods return safe defaults.
///
/// To re-enable: add `another_telephony` back to pubspec.yaml,
/// add READ_SMS + RECEIVE_SMS to AndroidManifest.xml, and restore
/// the Telephony-based implementation.
class MomoSmsListener {
  MomoSmsListener({
    MomoSmsPermissionService? permissionService,
  }) : _permissionService =
           permissionService ?? MomoSmsPermissionService.instance;

  final MomoSmsPermissionService _permissionService;

  final _controller = StreamController<MomoTransaction>.broadcast();

  /// Stream of parsed MoMo transactions detected from incoming SMS.
  Stream<MomoTransaction> get transactions => _controller.stream;

  bool _listening = false;

  // ── Lifecycle ──────────────────────────────────────────────────────────

  /// Starts listening for incoming SMS.
  ///
  /// Currently disabled (SMS permissions removed for Play Store).
  /// Returns `false` immediately.
  Future<bool> start() async {
    if (_listening) return true;

    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }

    final permissionStatus = await _permissionService.ensureGranted();
    if (permissionStatus != MomoSmsPermissionStatus.supportedGranted) {
      return false;
    }

    // SMS listening disabled — another_telephony removed for Play Store.
    // When re-enabled, register Telephony.listenIncomingSms here.
    _listening = true;
    return true;
  }

  /// Stops listening for incoming SMS and closes the stream.
  void dispose() {
    _listening = false;
    _controller.close();
  }

  // ── Inbox scan (for missed/background transactions) ────────────────────

  /// Scans the SMS inbox for recent MoMo messages.
  ///
  /// Currently returns empty (SMS permissions removed for Play Store).
  Future<List<MomoTransaction>> checkMissedTransactions({
    int lookbackMinutes = 30,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const [];
    }

    final permissionStatus = await _permissionService.getStatus();
    if (permissionStatus != MomoSmsPermissionStatus.supportedGranted) {
      return const [];
    }

    // SMS inbox reading disabled — another_telephony removed for Play Store.
    return const [];
  }
}
