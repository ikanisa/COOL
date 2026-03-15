import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'cool_button.dart';

/// A gate widget that blocks access to a feature when its kill-switch is active.
///
/// When [enabled] is `true`, renders [child] normally.
/// When [enabled] is `false`, shows a "temporarily unavailable" overlay.
///
/// Usage:
/// ```dart
/// KillSwitchGate(
///   enabled: ref.read(featureFlagsStateProvider).momoEnabled,
///   featureName: 'Mobile Money',
///   child: MomoScreenBody(),
/// )
/// ```
class KillSwitchGate extends StatelessWidget {
  const KillSwitchGate({
    required this.enabled,
    required this.child,
    this.featureName,
    this.message,
    this.onBackPressed,
    super.key,
  });

  /// Whether the feature is enabled. If `false`, the gate blocks access.
  final bool enabled;

  /// The child widget to render when the feature is enabled.
  final Widget child;

  /// Optional feature name shown in the unavailable message.
  final String? featureName;

  /// Optional custom message. Defaults to a generic unavailable message.
  final String? message;

  /// Called when the user presses the back button on the gate.
  /// If null, uses `Navigator.of(context).pop()`.
  final VoidCallback? onBackPressed;

  @override
  Widget build(BuildContext context) {
    if (enabled) {
      return child;
    }

    final displayMessage =
        message ??
        '${featureName ?? 'This feature'} is temporarily unavailable. '
            'Please try again later.';

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.text),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: onBackPressed ?? () => Navigator.of(context).pop(),
        ),
      ),
      body: Semantics(
        liveRegion: true,
        label: displayMessage,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.engineering_rounded,
                    size: 40,
                    color: AppColors.text3,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Temporarily Unavailable',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.text,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  displayMessage,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.text3,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                CoolButton(
                  label: 'Go Back',
                  onTap: onBackPressed ?? () => Navigator.of(context).pop(),
                  variant: CoolButtonVariant.secondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
