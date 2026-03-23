import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/cool_foundations.dart';
import 'cool_button.dart';

/// A gate widget that blocks access to a feature when its kill-switch is active.
class KillSwitchGate extends StatelessWidget {
  const KillSwitchGate({
    required this.enabled,
    required this.child,
    this.featureName,
    this.message,
    this.onBackPressed,
    super.key,
  });

  final bool enabled;
  final Widget child;
  final String? featureName;
  final String? message;
  final VoidCallback? onBackPressed;

  @override
  Widget build(BuildContext context) {
    if (enabled) {
      return child;
    }

    final colors = context.coolSemanticColors;
    final displayMessage =
        message ??
        '${featureName ?? 'This feature'} is temporarily unavailable. '
            'Please try again later.';

    return Scaffold(
      backgroundColor: colors.appBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: colors.primaryText),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: onBackPressed ?? () => Navigator.of(context).pop(),
        ),
      ),
      body: Semantics(
        liveRegion: true,
        label: displayMessage,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: CoolSpace.x7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: colors.operationalSurface,
                    borderRadius: const BorderRadius.all(
                      Radius.circular(CoolRadii.md),
                    ),
                  ),
                  child: Icon(
                    Icons.engineering_rounded,
                    size: 40,
                    color: colors.tertiaryText,
                  ),
                ),
                const SizedBox(height: CoolSpace.x6),
                Text(
                  'Temporarily Unavailable',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: CoolSpace.x3),
                Text(
                  displayMessage,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.tertiaryText,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: CoolSpace.x7),
                CoolButton(
                  label: context.l10n.goBack,
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
