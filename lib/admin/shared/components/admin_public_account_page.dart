import 'package:flutter/material.dart';

import '../../../app/theme/collect_colors.dart';
import '../../../app/theme/collect_runtime_assets.dart';
import '../../../app/theme/collect_theme.dart';
import '../../../app/theme/collect_universal_tokens.dart';

class AdminPublicAccountPage extends StatelessWidget {
  const AdminPublicAccountPage({
    required this.title,
    required this.subtitle,
    required this.child,
    super.key,
  });
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Public account tasks use the observed dark Business entry family without
    // changing the operator's workspace theme or authenticated settings cards.
    final highContrast =
        MediaQuery.highContrastOf(context) ||
        context.collectUniversalTokens.highContrast;
    final baseTheme = highContrast
        ? CollectTheme.highContrastDark()
        : CollectTheme.dark();
    const colors = CollectColors.dark;
    final radius = BorderRadius.circular(12);
    final restingBorder = OutlineInputBorder(
      borderRadius: radius,
      borderSide: highContrast
          ? BorderSide(color: colors.focusRing, width: 2)
          : BorderSide.none,
    );
    final theme = baseTheme.copyWith(
      inputDecorationTheme: baseTheme.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: Color.alphaBlend(
          colors.textPrimary.withValues(alpha: 0.12),
          colors.surfaceMuted,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        border: restingBorder,
        enabledBorder: restingBorder,
        disabledBorder: restingBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(
            color: colors.focusRing,
            width: highContrast ? 3 : 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: colors.dangerForeground, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: colors.dangerForeground, width: 3),
        ),
        labelStyle: baseTheme.textTheme.bodyLarge?.copyWith(
          color: colors.textSecondary,
        ),
        errorMaxLines: 3,
      ),
    );
    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: colors.authCanvas,
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.alphaBlend(
                  CollectColors.referenceAssetNavy.withValues(alpha: 0.55),
                  colors.authCanvas,
                ),
                colors.authCanvas,
              ],
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final side = constraints.maxWidth < 600 ? 20.0 : 40.0;
                final topGap = (constraints.maxHeight * 0.14)
                    .clamp(32.0, 112.0)
                    .toDouble();
                return SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(side, 24, side, 32),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight > 56
                          ? constraints.maxHeight - 56
                          : 0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Semantics(
                            label: 'Collect Admin',
                            image: true,
                            child: ExcludeSemantics(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Image.asset(
                                    CollectRuntimeAssets.officialLogo,
                                    width: 36,
                                    height: 36,
                                    fit: BoxFit.contain,
                                    excludeFromSemantics: true,
                                  ),
                                  const SizedBox(width: 12),
                                  Flexible(
                                    child: Text(
                                      'Collect Admin',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: topGap),
                        Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 400),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Semantics(
                                  header: true,
                                  child: Text(
                                    title,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineSmall,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  subtitle,
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(color: colors.textSecondary),
                                ),
                                const SizedBox(height: 28),
                                child,
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
