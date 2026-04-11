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
  final l10n = context.l10n;
  final errorMessage = state._cameraError ?? state._pipelineError;

  if (!enabled) {
    return CoolCard(
      backgroundColor: Colors.black.withValues(alpha: 0.66),
      borderColor: Colors.white.withValues(alpha: 0.12),
      useGradient: false,
      child: Text(
        l10n.biopayUnavailable,
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
          CoolButton(label: l10n.biopayEnableCamera, onTap: state._requestCameraAccess),
          SizedBox(height: space.x2),
          CoolButton(
            label: l10n.biopayManageAccess,
            variant: CoolButtonVariant.secondary,
            onTap: () => ProfileAppAccessSheet.show(context),
          ),
          if (errorMessage != null) ...[
            SizedBox(height: space.x3),
            Text(
              errorMessage,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.danger,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: space.x2),
            CoolButton(
              label: l10n.retry,
              variant: CoolButtonVariant.secondary,
              onTap: () => state._retryPipeline(),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            errorMessage,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.danger,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: space.x3),
          CoolButton(
            label: l10n.retry,
            onTap: () => state._retryPipeline(),
          ),
        ],
      ),
    );
  }

  return null;
}
