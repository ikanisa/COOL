import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_brand_mark.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../providers/auth_provider.dart';

/// Animated splash screen that checks auth state and redirects.
///
/// Shows the Cool logo mark with a staggered fade-in animation while
/// router-level auth restoration decides the next route.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _logoController;
  late final Animation<double> _logoFade;

  @override
  void initState() {
    super.initState();

    // Logo fade-in: 500ms
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _logoFade = CurvedAnimation(parent: _logoController, curve: Curves.easeOut);

    _logoController.forward();
  }

  @override
  void dispose() {
    _logoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final radii = context.coolRadii;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    final authState = ref.watch(authProvider);
    final showRestoreFailure =
        authState.session != null &&
        authState.profileRestoreState == AuthProfileRestoreState.failed;

    return CoolScreenBackground(
      showGlow: true,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: space.x6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Brand mark ────────────────────────────────────────
                  FadeTransition(
                    opacity: _logoFade,
                    child: Column(
                      children: [
                        SizedBox(
                          width: 112,
                          child: CoolCard(
                            padding: EdgeInsets.all(space.x4),
                            borderRadius: radii.xl,
                            backgroundColor: colors.cardSurface,
                            child: const AspectRatio(
                              aspectRatio: 1,
                              child: Center(child: CoolBrandMark(size: 68)),
                            ),
                          ),
                        ),
                        SizedBox(height: space.x3),
                        Text(
                          'Cool',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colors.primaryText,
                            letterSpacing: -0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: space.x5),
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CupertinoActivityIndicator(
                      radius: 11,
                      color: colors.accent,
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: CoolMotion.medium,
                    child: !showRestoreFailure
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: EdgeInsets.only(top: space.x7),
                            child: CoolCard(
                              key: const ValueKey('restore_failure_card'),
                              padding: EdgeInsets.all(space.x4),
                              borderRadius: radii.md,
                              backgroundColor: colors.cardSurface,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'We could not restore',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: colors.primaryText,
                                    ),
                                  ),
                                  SizedBox(height: space.x2),
                                  Text(
                                    authState.error ??
                                        'Check your connection and try again.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.secondaryText,
                                      height: 1.45,
                                    ),
                                  ),
                                  SizedBox(height: space.x4),
                                  CoolButton(
                                    label: context.l10n.retry,
                                    onTap: () {
                                      ref
                                          .read(authProvider.notifier)
                                          .restoreCurrentUser();
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
