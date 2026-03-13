import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_brand_mark.dart';
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
    final authState = ref.watch(authProvider);
    final showRestoreFailure =
        authState.session != null &&
        authState.profileRestoreState == AuthProfileRestoreState.failed;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
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
                      Container(
                        width: 112,
                        height: 112,
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: AppColors.border),
                        ),
                        alignment: Alignment.center,
                        child: const CoolBrandMark(size: 68),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Cool',
                        style: GoogleFonts.dmSans(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                          letterSpacing: -0.8,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CupertinoActivityIndicator(
                    radius: 11,
                    color: AppColors.accent,
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: !showRestoreFailure
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: 28),
                          child: Container(
                            key: const ValueKey('restore_failure_card'),
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: AppColors.surface2,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'We could not restore your profile',
                                  style: GoogleFonts.dmSans(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.text,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  authState.error ??
                                      'Check your connection and try again.',
                                  style: GoogleFonts.dmSans(
                                    fontSize: 13,
                                    height: 1.45,
                                    color: AppColors.text2,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                CoolButton(
                                  label: 'Retry',
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
    );
  }
}
