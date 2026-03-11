import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_button.dart';
import '../providers/auth_provider.dart';

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

  final _controllers = List.generate(
    _codeLength,
    (_) => TextEditingController(),
  );
  final _focusNodes = List.generate(_codeLength, (_) => FocusNode());

  bool _hasError = false;
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

    // Auto-focus first box.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[0].requestFocus();
    });
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

  String get _code => _controllers.map((c) => c.text).join();

  Future<void> _verify() async {
    final code = _code;
    if (code.length < _codeLength) return;

    setState(() {
      _hasError = false;
      _errorText = null;
    });

    await ref.read(authProvider.notifier).verifyOtp(widget.phoneNumber, code);

    if (!mounted) return;

    final authState = ref.read(authProvider);

    if (authState.error != null) {
      // Verification failed
      setState(() {
        _hasError = true;
        _errorText = authState.error;
      });
      _shakeController.forward(from: 0);
      HapticFeedback.mediumImpact();
    } else if (authState.session != null) {
      context.go(widget.redirectPath ?? AppRoutes.home);
    }
  }

  void _resend() {
    if (_resendSeconds > 0) return;

    final locale = Localizations.localeOf(context).languageCode;
    final language = locale == 'fr' ? 'fr' : 'en';

    ref.read(authProvider.notifier).sendOtp(widget.phoneNumber, language);
    _startResendTimer();
    for (final c in _controllers) {
      c.clear();
    }
    _focusNodes[0].requestFocus();
    setState(() {
      _hasError = false;
      _errorText = null;
    });
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _shakeController.dispose();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in _focusNodes) {
      n.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.go(
            AppRoutes.otpLocation(redirect: widget.redirectPath),
          ),
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.text),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const SizedBox(height: 48),

                      // ── Title ─────────────────────────────────────────
                      Text(
                        'Verify',
                        style: GoogleFonts.dmSans(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.phoneNumber,
                        style: GoogleFonts.dmSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: AppColors.accent,
                        ),
                      ),
                      const SizedBox(height: 40),

                      // ── OTP boxes ─────────────────────────────────────
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
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(_codeLength, _buildBox),
                        ),
                      ),

                      // ── Error ─────────────────────────────────────────
                      if (_errorText != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _errorText!,
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            color: AppColors.red,
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // ── Resend ────────────────────────────────────────
                      _resendSeconds > 0
                          ? Text(
                              'Resend in ${_resendSeconds}s',
                              style: GoogleFonts.dmSans(
                                fontSize: 13,
                                color: AppColors.text3,
                              ),
                            )
                          : GestureDetector(
                              onTap: _resend,
                              child: Text(
                                'Resend Code',
                                style: GoogleFonts.dmSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.accent,
                                ),
                              ),
                            ),

                      const Spacer(),

                      // ── CTA ───────────────────────────────────────────
                      CoolButton(
                        label: 'Verify',
                        onTap: _verify,
                        isLoading: authState.isLoading,
                      ),
                      const SizedBox(height: 24),
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

  // ── Individual OTP box ────────────────────────────────────────────

  Widget _buildBox(int index) {
    final hasFocus = _focusNodes[index].hasFocus;
    final borderColor = _hasError
        ? AppColors.red
        : hasFocus
        ? AppColors.accent
        : AppColors.border;

    return SizedBox(
      width: 50,
      height: 58,
      child: TextField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        textAlign: TextAlign.center,
        maxLength: 1,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: GoogleFonts.dmMono(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: AppColors.text,
        ),
        cursorColor: AppColors.accent,
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: AppColors.surface2,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: borderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: _hasError ? AppColors.red : AppColors.accent,
              width: 1.5,
            ),
          ),
        ),
        onChanged: (value) {
          setState(() {
            _hasError = false;
            _errorText = null;
          });
          if (value.isNotEmpty && index < _codeLength - 1) {
            _focusNodes[index + 1].requestFocus();
          }
          // Auto-submit when all filled.
          if (_code.length == _codeLength) {
            _verify();
          }
        },
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
