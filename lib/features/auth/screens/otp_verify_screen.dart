import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_market.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_otp_field.dart';
import '../providers/auth_provider.dart';
import '../../../shared/widgets/core_detail_scaffold.dart';

/// OTP verification screen with 6 auto-advancing digit boxes,
/// a resend countdown, and a shake error animation.
class OtpVerifyScreen extends ConsumerStatefulWidget {
  const OtpVerifyScreen({
    required this.phoneNumber,
    this.redirectPath,
    super.key,
  });
  final String phoneNumber;
  final String? redirectPath;

  @override
  ConsumerState<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends ConsumerState<OtpVerifyScreen>
    with SingleTickerProviderStateMixin {
  static const _codeLength = 6;
  static const _resendDuration = 60;

  final _otpController = CoolOtpController();

  String? _errorText;
  int _resendSeconds = _resendDuration;
  Timer? _resendTimer;

  // Shake animation
  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _startResendTimer();

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
  }

  void _startResendTimer() {
    _resendSeconds = _resendDuration;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendSeconds <= 0) {
        t.cancel();
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  Future<void> _verify([String? submittedCode]) async {
    final code = submittedCode ?? _otpController.value;
    if (code.length < _codeLength) return;

    setState(() => _errorText = null);

    await ref.read(authProvider.notifier).verifyOtp(widget.phoneNumber, code);

    if (!mounted) return;

    final authState = ref.read(authProvider);

    if (authState.error != null) {
      // Verification failed
      setState(() => _errorText = authState.error);
      _shakeController.forward(from: 0);
      HapticFeedback.mediumImpact();
    } else if (authState.session != null) {
      context.go(widget.redirectPath ?? AppRoutes.home);
    }
  }

  void _resend() {
    if (_resendSeconds > 0) return;

    ref
        .read(authProvider.notifier)
        .sendOtp(widget.phoneNumber, AppMarket.languageCode);
    _startResendTimer();
    _otpController.clear();
    setState(() => _errorText = null);
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _shakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    final authState = ref.watch(authProvider);

    return CoreDetailScaffold(
      showGlow: true,
      onBack: () =>
          context.go(AppRoutes.otpLocation(redirect: widget.redirectPath)),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: space.x6),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      SizedBox(height: space.x12),

                      Text(
                        'Verify code',
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: colors.primaryText,
                          height: 1.1,
                        ),
                      ),
                      SizedBox(height: space.x3),
                      Text(
                        'Enter the 6-digit code',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: colors.secondaryText,
                        ),
                      ),
                      SizedBox(height: space.x1),
                      Text(
                        widget.phoneNumber,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.accent,
                        ),
                      ),
                      SizedBox(height: space.x10),

                      AnimatedBuilder(
                        animation: _shakeAnimation,
                        builder: (context, child) {
                          final dx =
                              _shakeAnimation.value *
                              8 *
                              _shakeOffset(_shakeController.value);
                          return Transform.translate(
                            offset: Offset(dx, 0),
                            child: child,
                          );
                        },
                        child: CoolOtpField(
                          controller: _otpController,
                          length: _codeLength,
                          onChanged: (_) => setState(() => _errorText = null),
                          onComplete: _verify,
                          error: _errorText,
                        ),
                      ),

                      SizedBox(height: space.x6),

                      if (_resendSeconds > 0)
                        Text(
                          'Resend in ${_resendSeconds}s',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.tertiaryText,
                          ),
                        )
                      else
                        Semantics(
                          button: true,
                          label: 'Resend verification code',
                          child: GestureDetector(
                            onTap: _resend,
                            child: Text(
                              'Resend Code',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: colors.accent,
                              ),
                            ),
                          ),
                        ),

                      const Spacer(),

                      CoolButton(
                        label: 'Verify',
                        onTap: _verify,
                        isLoading: authState.isLoading,
                      ),
                      SizedBox(height: space.x6),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Produces a sin-wave shake offset from 0→1 progress.
  static double _shakeOffset(double progress) {
    return (progress * 3.14159 * 4).remainder(3.14159 * 2) < 3.14159
        ? 1.0
        : -1.0;
  }
}
