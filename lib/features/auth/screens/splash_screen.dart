import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/brand/app_brand.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_brand_mark.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../providers/auth_provider.dart';

/// Animated splash screen that auto-signs-in anonymously and redirects.
///
/// Shows the Cool logo mark with a staggered fade-in animation while
/// signing in anonymously. The router-level redirect handles the
/// transition to `/home` once a session is established.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _logoController;
  late final Animation<double> _logoFade;
  bool _signInAttempted = false;

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

  void _attemptAnonymousSignIn() {
    if (_signInAttempted) return;
    _signInAttempted = true;

    final authState = ref.read(authProvider);
    // Only sign in if there's no existing session.
    if (authState.session == null) {
      ref.read(authProvider.notifier).signInAnonymously();
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = ref.watch(appBrandProvider);
    final colors = context.coolSemanticColors;
    final radii = context.coolRadii;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    final authState = ref.watch(authProvider);

    final isRestorePending =
        authState.session != null &&
        authState.profileRestoreState == AuthProfileRestoreState.pending;
    final showRestoreFailure =
        authState.session != null &&
        authState.profileRestoreState == AuthProfileRestoreState.failed;

    // Auto sign-in after first frame if no session and not already pending.
    if (authState.session == null &&
        !authState.isLoading &&
        !_signInAttempted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _attemptAnonymousSignIn();
      });
    }

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
                          brand.splashTitle,
                          style: brand.isRayonDominant
                              ? context.coolText.rayonCondensed(
                                  theme.textTheme.headlineSmall,
                                  fontWeight: FontWeight.w900,
                                  color: colors.primaryText,
                                  letterSpacing: 0.2,
                                )
                              : theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colors.primaryText,
                                  letterSpacing: -0.8,
                                ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: space.x5),
                  if (authState.isLoading || isRestorePending)
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
                                    'Connection issue',
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
                                      _signInAttempted = false;
                                      ref
                                          .read(authProvider.notifier)
                                          .signInAnonymously();
                                      _signInAttempted = true;
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
