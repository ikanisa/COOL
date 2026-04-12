import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/brand/app_brand.dart';
import '../../core/theme/cool_foundations.dart';
import 'cool_screen_background.dart';

/// Shared startup surface used across bootstrap and auth loading.
///
/// The layout intentionally matches the native splash color and transparent
/// logo so startup reads as one continuous loading screen.
class StartupLoadingScreen extends StatefulWidget {
  const StartupLoadingScreen({
    required this.statusLabel,
    this.showProgressIndicator = true,
    this.matchNativeSplash = false,
    this.footer,
    this.logo,
    super.key,
  });

  final String statusLabel;
  final bool showProgressIndicator;
  final bool matchNativeSplash;
  final Widget? footer;
  final Widget? logo;

  static const _branding = AppBranding.cool();
  static const nativeSplashBackgroundColor = Color(0xFF0D0A27);
  static const _brandMarkSize = 116.0;
  static const _contentMaxWidth = 360.0;
  static const _indicatorSize = 22.0;
  static const _indicatorRadius = 11.0;

  @override
  State<StartupLoadingScreen> createState() => _StartupLoadingScreenState();
}

class _StartupLoadingScreenState extends State<StartupLoadingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entranceController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );
  late final Animation<double> _logoEntranceOpacity = CurvedAnimation(
    parent: _entranceController,
    curve: const Interval(0.0, 0.45, curve: CoolMotion.enterCurve),
  );
  late final Animation<double> _logoEntranceScale =
      Tween<double>(begin: 0.92, end: 1.0).animate(
        CurvedAnimation(
          parent: _entranceController,
          curve: const Interval(0.0, 0.55, curve: CoolMotion.enterCurve),
        ),
      );
  late final Animation<Offset> _logoEntranceSlide =
      Tween<Offset>(begin: const Offset(0, 0.055), end: Offset.zero).animate(
        CurvedAnimation(
          parent: _entranceController,
          curve: const Interval(0.0, 0.55, curve: CoolMotion.enterCurve),
        ),
      );
  late final Animation<double> _detailEntranceOpacity = CurvedAnimation(
    parent: _entranceController,
    curve: const Interval(0.18, 0.75, curve: CoolMotion.enterCurve),
  );

  bool _didStartMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (CoolMotion.isReducedMotion(context)) {
      _pulseController.stop();
      _entranceController.value = 1;
      return;
    }
    if (_didStartMotion) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
      return;
    }
    _didStartMotion = true;
    _pulseController.repeat(reverse: true);
    _entranceController.forward();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    final reducedMotion = CoolMotion.isReducedMotion(context);
    final content = Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: space.x6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: StartupLoadingScreen._contentMaxWidth,
              ),
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  _entranceController,
                  _pulseController,
                ]),
                builder: (context, _) {
                  final pulseT = reducedMotion
                      ? 0.5
                      : Curves.easeInOut.transform(_pulseController.value);
                  final logoPulseScale = 0.985 + (pulseT * 0.03);
                  final logoFloatOffset = (pulseT - 0.5) * 6;
                  final indicatorOpacity = 0.62 + (pulseT * 0.38);
                  final indicatorScale = 0.96 + (pulseT * 0.06);
                  final haloOpacity = widget.matchNativeSplash
                      ? 0.0
                      : 0.035 + (pulseT * 0.025);

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FadeTransition(
                        opacity: _logoEntranceOpacity,
                        child: SlideTransition(
                          position: _logoEntranceSlide,
                          child: Transform.translate(
                            offset: Offset(0, -logoFloatOffset),
                            child: Transform.scale(
                              scale: _logoEntranceScale.value * logoPulseScale,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  if (haloOpacity > 0)
                                    IgnorePointer(
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: RadialGradient(
                                            radius: 0.78,
                                            colors: [
                                              StartupLoadingScreen
                                                  ._branding
                                                  .secondaryColor
                                                  .withValues(
                                                    alpha: haloOpacity,
                                                  ),
                                              Colors.transparent,
                                            ],
                                          ),
                                        ),
                                        child: const SizedBox.square(
                                          dimension:
                                              StartupLoadingScreen
                                                  ._brandMarkSize +
                                              56,
                                        ),
                                      ),
                                    ),
                                  widget.logo ??
                                      const _StartupBrandMark(
                                        branding:
                                            StartupLoadingScreen._branding,
                                        size:
                                            StartupLoadingScreen._brandMarkSize,
                                      ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: space.x6),
                      FadeTransition(
                        opacity: _detailEntranceOpacity,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.showProgressIndicator)
                              Opacity(
                                opacity: indicatorOpacity,
                                child: Transform.scale(
                                  scale: indicatorScale,
                                  child: SizedBox(
                                    width: StartupLoadingScreen._indicatorSize,
                                    height: StartupLoadingScreen._indicatorSize,
                                    child: CupertinoActivityIndicator(
                                      radius:
                                          StartupLoadingScreen._indicatorRadius,
                                      color: colors.accent,
                                    ),
                                  ),
                                ),
                              ),
                            SizedBox(height: space.x3),
                            Semantics(
                              liveRegion: true,
                              child: AnimatedSwitcher(
                                duration: CoolMotion.resolve(
                                  context,
                                  const Duration(milliseconds: 260),
                                ),
                                switchInCurve: CoolMotion.resolveCurve(
                                  context,
                                  CoolMotion.enterCurve,
                                ),
                                switchOutCurve: CoolMotion.resolveCurve(
                                  context,
                                  CoolMotion.exitCurve,
                                ),
                                transitionBuilder: (child, animation) {
                                  final fade = CurvedAnimation(
                                    parent: animation,
                                    curve: CoolMotion.resolveCurve(
                                      context,
                                      CoolMotion.enterCurve,
                                    ),
                                    reverseCurve: CoolMotion.resolveCurve(
                                      context,
                                      CoolMotion.exitCurve,
                                    ),
                                  );
                                  return FadeTransition(
                                    opacity: fade,
                                    child: SlideTransition(
                                      position: Tween<Offset>(
                                        begin: const Offset(0, 0.12),
                                        end: Offset.zero,
                                      ).animate(fade),
                                      child: child,
                                    ),
                                  );
                                },
                                child: Text(
                                  widget.statusLabel,
                                  key: ValueKey(widget.statusLabel),
                                  textAlign: TextAlign.center,
                                  style: context.coolText.mono(
                                    theme.textTheme.bodySmall,
                                    fontWeight: FontWeight.w500,
                                    color: colors.secondaryText,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ),
                            ),
                            if (widget.footer != null) ...[
                              SizedBox(height: space.x6),
                              widget.footer!,
                            ],
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.matchNativeSplash) {
      return ColoredBox(
        color: StartupLoadingScreen.nativeSplashBackgroundColor,
        child: content,
      );
    }

    return CoolScreenBackground(
      primaryColor: StartupLoadingScreen._branding.primaryColor,
      secondaryColor: StartupLoadingScreen._branding.secondaryColor,
      showGlow: false,
      child: content,
    );
  }
}

class _StartupBrandMark extends StatelessWidget {
  const _StartupBrandMark({required this.branding, required this.size});

  final AppBranding branding;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: branding.logoSemanticLabel,
      image: true,
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        height: size,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Image.asset(
            branding.splashLogoAssetPath,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),
    );
  }
}
