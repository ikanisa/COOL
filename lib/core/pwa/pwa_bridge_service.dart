import 'package:flutter/foundation.dart';

import 'pwa_bridge_service_stub.dart'
    if (dart.library.html) 'pwa_bridge_service_web.dart';

enum PwaInstallPromptResult { accepted, dismissed, unavailable, error }

@immutable
class PwaBridgeState {
  const PwaBridgeState({
    this.canPromptInstall = false,
    this.shouldShowIosInstall = false,
    this.isStandalone = false,
    this.updateAvailable = false,
    this.hasServiceWorker = false,
    this.registrationReady = false,
    this.isInstalled = false,
  });

  final bool canPromptInstall;
  final bool shouldShowIosInstall;
  final bool isStandalone;
  final bool updateAvailable;
  final bool hasServiceWorker;
  final bool registrationReady;
  final bool isInstalled;

  bool get hasInstallCta => canPromptInstall || shouldShowIosInstall;

  PwaBridgeState copyWith({
    bool? canPromptInstall,
    bool? shouldShowIosInstall,
    bool? isStandalone,
    bool? updateAvailable,
    bool? hasServiceWorker,
    bool? registrationReady,
    bool? isInstalled,
  }) {
    return PwaBridgeState(
      canPromptInstall: canPromptInstall ?? this.canPromptInstall,
      shouldShowIosInstall: shouldShowIosInstall ?? this.shouldShowIosInstall,
      isStandalone: isStandalone ?? this.isStandalone,
      updateAvailable: updateAvailable ?? this.updateAvailable,
      hasServiceWorker: hasServiceWorker ?? this.hasServiceWorker,
      registrationReady: registrationReady ?? this.registrationReady,
      isInstalled: isInstalled ?? this.isInstalled,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PwaBridgeState &&
        other.canPromptInstall == canPromptInstall &&
        other.shouldShowIosInstall == shouldShowIosInstall &&
        other.isStandalone == isStandalone &&
        other.updateAvailable == updateAvailable &&
        other.hasServiceWorker == hasServiceWorker &&
        other.registrationReady == registrationReady &&
        other.isInstalled == isInstalled;
  }

  @override
  int get hashCode => Object.hash(
        canPromptInstall,
        shouldShowIosInstall,
        isStandalone,
        updateAvailable,
        hasServiceWorker,
        registrationReady,
        isInstalled,
      );
}

abstract class PwaBridgeService extends ChangeNotifier {
  PwaBridgeState get state;

  Future<PwaInstallPromptResult> promptInstall();

  Future<bool> activateUpdate();

  Future<bool> downloadOffline();
}

PwaBridgeService createPwaBridgeService() => createPlatformPwaBridgeService();
