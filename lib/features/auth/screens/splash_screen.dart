import 'dart:async';

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

/// Animated splash screen
///
/// Auto-signs-in anonymously.
/// The router-level redirect handles transition to `/home` once
/// a session is established.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _logoController;
  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;
  late final AnimationController _textController;
  late final Animation<double> _textFade;
  Timer? _subtitleDelayTimer;
  bool _signInAttempted = false;

  @override
  void initState() {
    super.initState();

    // Logo: 600ms fade + scale
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _logoFade = CurvedAnimation(parent: _logoController, curve: Curves.easeOut);
    _logoScale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutCubic),
    );

    // Subtitle text: 400ms fade, delayed 300ms after logo
    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _textFade = CurvedAnimation(parent: _textController, curve: Curves.easeOut);

    _logoController.forward().then((_) {
      if (mounted) {
        _subtitleDelayTimer = Timer(const Duration(milliseconds: 300), () {
          if (mounted) _textController.forward();
        });
      }
    });
  }

  @override
  void dispose() {
    _subtitleDelayTimer?.cancel();
    _logoController.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _attemptAnonymousSignIn() {
    if (_signInAttempted) return;
    _signInAttempted = true;
    debugPrint('[Splash] ➜ Attempting anonymous sign-in');

    final authState = ref.read(authProvider);
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
    final showStartupFailure =
        authState.session == null && authState.error != null;
    final shouldAutoSignIn =
        authState.session == null &&
        !authState.isLoading &&
        !_signInAttempted;

    debugPrint(
      '[Splash] build '
      'session=${authState.session != null} '
      'loading=${authState.isLoading} '
      'restore=${authState.profileRestoreState} '
      'error=${authState.error != null} '
      'attempted=$_signInAttempted '
      'auto=$shouldAutoSignIn',
    );

    // Auto sign-in after first frame.
    if (shouldAutoSignIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _attemptAnonymousSignIn();
      });
    }

    return CoolScreenBackground(
      showGlow: true,
      primaryColor: brand.primaryColor,
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
                  FadeTransition(
                    opacity: _logoFade,
                    child: ScaleTransition(
                      scale: _logoScale,
                      child: Column(
                        children: [
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              color: colors.cardSurface,
                              borderRadius: BorderRadius.circular(radii.xl),
                              boxShadow: CoolShadows.claymorphicCard(
                                glowColor: colors.accent,
                              ),
                            ),
                            padding: EdgeInsets.all(space.x4),
                            child: const Center(child: CoolBrandMark(size: 52)),
                          ),
                          SizedBox(height: space.x4),

                          Text(
                            brand.splashTitle,
                            textAlign: TextAlign.center,
                            style: context.coolText.displayCondensed(
                              theme.textTheme.headlineMedium,
                              fontWeight: FontWeight.w700,
                              color: colors.primaryText,
                              letterSpacing: 2.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: space.x3),

                  FadeTransition(
                    opacity: _textFade,
                    child: Text(
                      brand.welcomeSubtitle,
                      textAlign: TextAlign.center,
                      style: context.coolText.mono(
                        theme.textTheme.bodySmall,
                        fontWeight: FontWeight.w400,
                        color: colors.secondaryText,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),

                  SizedBox(height: space.x6),

                  if (authState.isLoading || isRestorePending)
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CupertinoActivityIndicator(
                        radius: 11,
                        color: brand.primaryColor,
                      ),
                    ),

                  AnimatedSwitcher(
                    duration: CoolMotion.medium,
                    child: !(showRestoreFailure || showStartupFailure)
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
                                  Row(
                                    children: [
                                      Icon(
                                        _isTimeoutError(authState.error)
                                            ? Icons.wifi_off_rounded
                                            : Icons.cloud_off_rounded,
                                        size: 20,
                                        color: colors.warning,
                                      ),
                                      SizedBox(width: space.x2),
                                      Expanded(
                                        child: Text(
                                          _isTimeoutError(authState.error)
                                              ? 'Network timeout'
                                              : 'Connection issue',
                                          style: theme.textTheme.titleSmall?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: colors.primaryText,
                                          ),
                                        ),
                                      ),
                                    ],
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
                                    variant: CoolButtonVariant.clay,
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

  static bool _isTimeoutError(String? error) {
    if (error == null) return false;
    final lower = error.toLowerCase();
    return lower.contains('timed out') ||
        lower.contains('timeout') ||
        lower.contains('network');
  }
}
