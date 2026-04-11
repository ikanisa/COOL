import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/cool_foundations.dart';
import 'cool_brand_mark.dart';
import 'cool_screen_background.dart';

/// Shared startup surface used across bootstrap and auth loading.
///
/// The layout intentionally matches the native splash color and transparent
/// logo so startup reads as one continuous loading screen.
class StartupLoadingScreen extends ConsumerWidget {
  const StartupLoadingScreen({
    required this.statusLabel,
    this.showProgressIndicator = true,
    this.footer,
    this.logo,
    super.key,
  });

  final String statusLabel;
  final bool showProgressIndicator;
  final Widget? footer;
  final Widget? logo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final theme = Theme.of(context);

    return CoolScreenBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: space.x6),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    logo ?? const CoolBrandMark(size: 128),
                    SizedBox(height: space.x6),
                    if (showProgressIndicator)
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: CupertinoActivityIndicator(
                          radius: 11,
                          color: colors.accent,
                        ),
                      ),
                    SizedBox(height: space.x3),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        statusLabel,
                        textAlign: TextAlign.center,
                        style: context.coolText.mono(
                          theme.textTheme.bodySmall,
                          fontWeight: FontWeight.w500,
                          color: colors.secondaryText,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    if (footer != null) ...[
                      SizedBox(height: space.x6),
                      footer!,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

