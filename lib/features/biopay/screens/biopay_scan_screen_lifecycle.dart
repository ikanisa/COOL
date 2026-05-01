part of 'biopay_scan_screen.dart';

extension _BiopayScanScreenLifecycle on _BiopayScanScreenState {
  Future<void> _stopTrace(
    String name, {
    Map<String, int>? metrics,
    Map<String, String>? attributes,
  }) {
    return ref
        .read(performanceServiceProvider)
        .stopTrace(name, metrics: metrics, attributes: attributes);
  }

  void _finishStartupTrace({required String phase, String? error}) {
    if (_startupTraceCompleted) {
      return;
    }
    _startupTraceCompleted = true;
    unawaited(
      _stopTrace(
        'biopay_scan_startup',
        attributes: <String, String>{
          'mode': widget.mode.name,
          'phase': phase,
          if (error != null && error.isNotEmpty) 'error': error,
        },
      ),
    );
  }

  Future<void> _processFrame(CameraImage frame) =>
      _processBiopayFrame(this, frame);

  void _applyAnalysisFeedback(
    BiopayFaceFrameAnalysis analysis,
    int stableFramesRequired,
  ) => _applyBiopayAnalysisFeedback(this, analysis, stableFramesRequired);

  Future<void> _handleEnrollmentEmbedding(Float32List embedding) =>
      _handleBiopayEnrollmentEmbedding(this, embedding);

  Future<void> _handleMatchEmbedding(Float32List embedding) =>
      _handleBiopayMatchEmbedding(this, embedding);

  void _setScannerState({
    required BiopayScannerTone tone,
    required String statusLabel,
    required String helperText,
  }) => _setBiopayScannerState(
    this,
    tone: tone,
    statusLabel: statusLabel,
    helperText: helperText,
  );

  BiopayScannerTone _scannerToneForLiveness(
    BiopayLivenessFeedbackLevel level,
  ) => _scannerToneForBiopayLiveness(level);

  Widget? _buildScannerFooter(
    BuildContext context, {
    required bool enabled,
    required bool isCameraReady,
  }) => _buildBiopayScannerFooter(
    this,
    context,
    enabled: enabled,
    isCameraReady: isCameraReady,
  );
}
