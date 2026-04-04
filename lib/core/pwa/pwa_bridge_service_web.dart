import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'pwa_bridge_service.dart';

PwaBridgeService createPlatformPwaBridgeService() => _WebPwaBridgeService();

class _WebPwaBridgeService extends PwaBridgeService {
  _WebPwaBridgeService() {
    _state = PwaBridgeState(hasServiceWorker: _hasServiceWorker);
    _eventListener = ((web.Event _) {
      unawaited(_refreshFromBridge());
    }).toJS;
    web.window.addEventListener('cool-pwa-statechange', _eventListener);
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_refreshFromBridge());
    });
    scheduleMicrotask(() {
      unawaited(_refreshFromBridge());
    });
  }

  late final JSFunction _eventListener;
  late final Timer _pollTimer;
  late PwaBridgeState _state;

  @override
  PwaBridgeState get state => _state;

  bool get _hasServiceWorker =>
      web.window.navigator.has('serviceWorker') &&
      web.window.navigator['serviceWorker'] != null;

  JSObject? get _bridge {
    if (!web.window.has('coolPwa')) {
      return null;
    }
    return web.window['coolPwa'] as JSObject?;
  }

  Future<void> _refreshFromBridge() async {
    final bridge = _bridge;
    if (bridge == null) {
      _setState(PwaBridgeState(hasServiceWorker: _hasServiceWorker));
      return;
    }

    try {
      final rawState = bridge.callMethod<JSAny?>('getState'.toJS);
      final data = rawState?.dartify();
      if (data is Map<Object?, Object?>) {
        _setState(
          PwaBridgeState(
            canPromptInstall: data['canPromptInstall'] == true,
            shouldShowIosInstall:
                data['isIosSafari'] == true && data['isStandalone'] != true,
            isStandalone: data['isStandalone'] == true,
            updateAvailable: data['updateAvailable'] == true,
            hasServiceWorker: data['hasServiceWorker'] == true,
            registrationReady: data['registrationReady'] == true,
            isInstalled: data['isInstalled'] == true,
          ),
        );
        return;
      }
    } catch (_) {
      // Fall back to a minimal capability state when the bridge is unavailable.
    }

    _setState(PwaBridgeState(hasServiceWorker: _hasServiceWorker));
  }

  void _setState(PwaBridgeState nextState) {
    if (_state == nextState) {
      return;
    }
    _state = nextState;
    notifyListeners();
  }

  Future<Object?> _invokeBridgeMethod(String methodName) async {
    final bridge = _bridge;
    if (bridge == null) {
      return null;
    }

    final result = bridge.callMethod<JSAny?>(methodName.toJS);
    if (result == null) {
      return null;
    }

    final resolved = await (result as JSPromise<JSAny?>).toDart;
    return resolved?.dartify();
  }

  @override
  Future<bool> activateUpdate() async {
    try {
      return await _invokeBridgeMethod('activateUpdate') == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> downloadOffline() async {
    try {
      return await _invokeBridgeMethod('downloadOffline') == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<PwaInstallPromptResult> promptInstall() async {
    try {
      final data = await _invokeBridgeMethod('promptInstall');
      if (data is Map<Object?, Object?>) {
        return switch (data['outcome']) {
          'accepted' => PwaInstallPromptResult.accepted,
          'dismissed' => PwaInstallPromptResult.dismissed,
          'unavailable' => PwaInstallPromptResult.unavailable,
          _ => PwaInstallPromptResult.dismissed,
        };
      }
      return PwaInstallPromptResult.unavailable;
    } catch (_) {
      return PwaInstallPromptResult.error;
    }
  }

  @override
  void dispose() {
    _pollTimer.cancel();
    web.window.removeEventListener('cool-pwa-statechange', _eventListener);
    super.dispose();
  }
}
