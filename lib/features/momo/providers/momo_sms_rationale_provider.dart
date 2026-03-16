import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Coordinator that allows background services to request the UI to show
/// a rationale dialog before a system permission request.
class MomoSmsRationaleNotifier extends ChangeNotifier {
  Completer<bool>? _pendingRequest;

  /// Whether a rationale request is currently pending.
  bool get isRequestPending => _pendingRequest != null;

  /// Requests the UI to show a rationale dialog.
  /// 
  /// Returns a [Future] that completes with `true` if the user accepted
  /// the rationale, or `false` if they dismissed/denied it.
  Future<bool> requestRationale() {
    if (_pendingRequest != null) {
      return _pendingRequest!.future;
    }

    _pendingRequest = Completer<bool>();
    notifyListeners();
    return _pendingRequest!.future;
  }

  /// Completes the pending rationale request with the given [result].
  void completeRequest(bool result) {
    if (_pendingRequest == null) {
      return;
    }

    _pendingRequest!.complete(result);
    _pendingRequest = null;
    notifyListeners();
  }
}

/// Provider for the [MomoSmsRationaleNotifier].
final momoSmsRationaleProvider = ChangeNotifierProvider<MomoSmsRationaleNotifier>((ref) {
  return MomoSmsRationaleNotifier();
});
