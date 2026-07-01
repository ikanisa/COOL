import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/collect_components.dart';

class LaunchSplashScreen extends StatefulWidget {
  const LaunchSplashScreen({super.key});

  @override
  State<LaunchSplashScreen> createState() => _LaunchSplashScreenState();
}

class _LaunchSplashScreenState extends State<LaunchSplashScreen> {
  static const _splashMarkAssetPath = CollectRuntimeAssets.splashMarkAssetPath;

  Timer? _timer;
  var _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scheduled) return;
    _scheduled = true;
    final hold = GoRouterState.of(context).uri.queryParameters['holdSplash'];
    if (hold == '1' || hold == 'true') return;
    _timer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) context.go('/auth');
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final textTheme = Theme.of(context).textTheme;
    final foreground = colors.onImagePrimary;
    return Scaffold(
      backgroundColor: colors.transparent,
      body: CollectGradientBackground(
        routePath: '/auth',
        child: SizedBox.expand(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(CollectSpacing.x6),
              child: Column(
                children: [
                  const Spacer(),
                  Semantics(
                    label: 'Collect',
                    image: true,
                    child: ExcludeSemantics(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: foreground.withValues(alpha: 0.10),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: foreground.withValues(alpha: 0.16),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: CollectColors.referenceChromeBlack
                                  .withValues(alpha: 0.28),
                              blurRadius: 42,
                              offset: const Offset(0, 18),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(CollectSpacing.x4),
                          child: Image.asset(
                            _splashMarkAssetPath,
                            width: 88,
                            height: 88,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                            errorBuilder: (context, error, stackTrace) =>
                                const CollectBrandMark(
                                  framed: false,
                                  compact: false,
                                  width: 96,
                                  height: 40,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  CollectSpacing.gap24,
                  Text(
                    'Collect',
                    style: textTheme.displaySmall?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w900,
                      height: 1,
                      letterSpacing: 0,
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 54,
                    child: LinearProgressIndicator(
                      minHeight: 4,
                      borderRadius: CollectRadius.pillBorder,
                      backgroundColor: foreground.withValues(alpha: 0.12),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        CollectColors.brandMintGreen,
                      ),
                    ),
                  ),
                  CollectSpacing.gap32,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
