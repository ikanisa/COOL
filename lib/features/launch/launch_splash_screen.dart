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
        child: SizedBox.expand(
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final textScale = MediaQuery.textScalerOf(context).scale(1);
                final compact = constraints.maxHeight < 640 || textScale > 1.3;
                final content = Padding(
                  padding: EdgeInsets.all(
                    compact ? CollectSpacing.x4 : CollectSpacing.x6,
                  ),
                  child: Column(
                    children: [
                      const Spacer(),
                      Semantics(
                        label: 'Collect official logo',
                        image: true,
                        child: ExcludeSemantics(
                          child: SizedBox.square(
                            dimension: compact ? 88 : 112,
                            child: Image.asset(
                              CollectRuntimeAssets.officialLogo,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ),
                      ),
                      compact ? CollectSpacing.gap16 : CollectSpacing.gap24,
                      Text(
                        'Collect',
                        textAlign: TextAlign.center,
                        style: textTheme.displaySmall?.copyWith(
                          color: foreground,
                          fontWeight: CollectTypography.weightBold,
                          height: CollectTypography.leadingSolid,
                          letterSpacing: CollectTypography.trackingDefault,
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
                      compact ? CollectSpacing.gap16 : CollectSpacing.gap32,
                    ],
                  ),
                );
                return SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(child: content),
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
