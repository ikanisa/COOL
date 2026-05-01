part of 'biopay_scan_screen.dart';

extension _BiopayScanScreenView on _BiopayScanScreenState {
  Widget _buildScannerView(BuildContext context) {
    final adminAccess = ref.watch(adminWorkspaceAccessProvider);
    final enabled = ref.watch(
      featureFlagsStateProvider.select(
        (flags) =>
            flags.isBiopayEnabled(isAdmin: adminAccess.hasPlatformAccess),
      ),
    );
    final isEnroll = widget.mode == BiopayScanMode.enroll;
    final snapshot = _cameraSnapshot;
    final isCameraReady =
        snapshot?.isReady == true &&
        _controller != null &&
        _controller!.value.isInitialized &&
        !_isInitializingCamera;

    final tone = _cameraError != null
        ? BiopayScannerTone.error
        : isCameraReady
        ? _tone
        : (snapshot?.kind == AppAccessStateKind.blockedInSystem ||
                  snapshot?.kind == AppAccessStateKind.disabledInApp
              ? BiopayScannerTone.blocked
              : BiopayScannerTone.searching);

    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _closeScanner();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            if (isCameraReady || !_isInitializingCamera)
              Positioned.fill(
                child: BiopayScannerShell(
                  controller: _controller,
                  isCameraReady: isCameraReady,
                  tone: tone,
                  sampleCount: _capturedEnrollmentFrames,
                  totalSamples: 5,
                  isEnrollMode: isEnroll,
                  footer: _buildScannerFooter(
                    context,
                    enabled: enabled,
                    isCameraReady: isCameraReady,
                  ),
                ),
              ),
            if (_isInitializingCamera)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white54,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          context.l10n.biopayScanCameraLoading,
                          style: context.coolText.manrope(
                            null,
                            color: Colors.white54,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Positioned(
              top: MediaQuery.viewPaddingOf(context).top + CoolSpace.x4,
              left: CoolSpace.x4,
              child: Material(
                color: Colors.black.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  onTap: _closeScanner,
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      CoolIcons.backIos,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
            if (_canSwitchEnrollmentCamera)
              Positioned(
                top: MediaQuery.viewPaddingOf(context).top + CoolSpace.x4,
                right: CoolSpace.x4,
                child: Tooltip(
                  message: _cameraSwitchTooltip,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.42),
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      onTap: _switchEnrollmentCamera,
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        height: 56,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.cameraswitch_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _cameraSwitchLabel,
                              style: context.coolText.manrope(
                                null,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
