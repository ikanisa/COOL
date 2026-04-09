part of 'biopay_scan_screen.dart';

void _setBiopayScannerState(
  _BiopayScanScreenState state, {
  required BiopayScannerTone tone,
  required String statusLabel,
  required String helperText,
}) {
  if (!state.mounted) {
    return;
  }
  final needsUpdate =
      state._tone != tone ||
      state._statusLabel != statusLabel ||
      state._helperText != helperText;
  if (!needsUpdate) {
    return;
  }
  state._updateScannerState(() {
    state._tone = tone;
    state._statusLabel = statusLabel;
    state._helperText = helperText;
  });
}

BiopayScannerTone _scannerToneForBiopayLiveness(
  BiopayLivenessFeedbackLevel level,
) {
  return switch (level) {
    BiopayLivenessFeedbackLevel.searching => BiopayScannerTone.searching,
    BiopayLivenessFeedbackLevel.ready => BiopayScannerTone.ready,
    BiopayLivenessFeedbackLevel.blocked => BiopayScannerTone.blocked,
  };
}

Widget? _buildBiopayScannerFooter(
  _BiopayScanScreenState state,
  BuildContext context, {
  required bool enabled,
  required bool isCameraReady,
}) {
  final theme = Theme.of(context);
  final colors = context.coolSemanticColors;
  final space = context.coolSpace;
  final errorMessage = state._cameraError ?? state._pipelineError;

  if (!enabled) {
    return CoolCard(
      backgroundColor: Colors.black.withValues(alpha: 0.66),
      borderColor: Colors.white.withValues(alpha: 0.12),
      useGradient: false,
      child: Text(
        'BioPay unavailable',
        style: theme.textTheme.labelLarge?.copyWith(
          color: colors.warning,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  if (!isCameraReady) {
    return CoolCard(
      backgroundColor: Colors.black.withValues(alpha: 0.66),
      borderColor: Colors.white.withValues(alpha: 0.12),
      useGradient: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CoolButton(label: 'Enable Camera', onTap: state._requestCameraAccess),
          SizedBox(height: space.x2),
          CoolButton(
            label: 'Manage Access',
            variant: CoolButtonVariant.secondary,
            onTap: () => ProfileAppAccessSheet.show(context),
          ),
          if (errorMessage != null) ...[
            SizedBox(height: space.x3),
            Text(
              errorMessage,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  if (errorMessage != null) {
    return CoolCard(
      backgroundColor: Colors.black.withValues(alpha: 0.66),
      borderColor: Colors.white.withValues(alpha: 0.12),
      useGradient: false,
      child: Text(
        errorMessage,
        style: theme.textTheme.bodySmall?.copyWith(
          color: colors.danger,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  return null;
}
