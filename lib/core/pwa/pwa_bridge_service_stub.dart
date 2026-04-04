import 'pwa_bridge_service.dart';

PwaBridgeService createPlatformPwaBridgeService() => _StubPwaBridgeService();

class _StubPwaBridgeService extends PwaBridgeService {
  @override
  PwaBridgeState get state => const PwaBridgeState();

  @override
  Future<bool> activateUpdate() async => false;

  @override
  Future<bool> downloadOffline() async => false;

  @override
  Future<PwaInstallPromptResult> promptInstall() async {
    return PwaInstallPromptResult.unavailable;
  }
}
