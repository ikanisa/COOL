import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_market.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_button.dart';
import '../providers/auth_provider.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/widgets/cool_screen_background.dart';

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

  void _clearInputError() {
    if (!_hasError && _errorText == null) {
      return;
    }

    setState(() {
      _hasError = false;
      _errorText = null;
    });
  }

  void _focusBox(int index) {
    _focusNodes[index].requestFocus();
    _controllers[index].selection = TextSelection.collapsed(
      offset: _controllers[index].text.length,
    );
  }

  KeyEventResult _handleBackspace(int index, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.backspace) {
      return KeyEventResult.ignored;
    }

    if (_controllers[index].text.isNotEmpty || index == 0) {
      return KeyEventResult.ignored;
    }

    final previousIndex = index - 1;
    final previousController = _controllers[previousIndex];
    if (previousController.text.isNotEmpty) {
      previousController.clear();
    }
    _focusBox(previousIndex);
    _clearInputError();
    return KeyEventResult.handled;
  }

  Future<void> _verify() async {
    final code = _code;
    if (code.length < _codeLength) return;

    _clearInputError();

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

    ref
        .read(authProvider.notifier)
        .sendOtp(widget.phoneNumber, AppMarket.languageCode);
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
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    final authState = ref.watch(authProvider);

    return CoolScreenBackground(
      showGlow: true,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            tooltip: context.l10n.back,
            onPressed: () => context.go(
              AppRoutes.otpLocation(redirect: widget.redirectPath),
            ),
            icon: Icon(Icons.arrow_back_rounded, color: colors.primaryText),
          ),
        ),
        body: SafeArea(
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

                        // ── Title ─────────────────────────────────────────
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
                          SizedBox(height: space.x3),
                          Text(
                            _errorText!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.danger,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],

                        SizedBox(height: space.x6),

                        // ── Resend ────────────────────────────────────────
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

                        // ── CTA ───────────────────────────────────────────
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
      ),
    );
  }

  // ── Individual OTP box ────────────────────────────────────────────

  Widget _buildBox(int index) {
    final colors = context.coolSemanticColors;
    final radii = context.coolRadii;
    final theme = Theme.of(context);
    final hasFocus = _focusNodes[index].hasFocus;
    final borderColor = _hasError
        ? colors.danger
        : hasFocus
        ? colors.accent
        : colors.border;

    return Focus(
      onKeyEvent: (_, event) => _handleBackspace(index, event),
      child: SizedBox(
        width: 50,
        height: 58,
        child: Semantics(
          textField: true,
          label: 'Digit ${index + 1}/$_codeLength',
          hint: 'Enter a single digit',
          child: TextField(
            controller: _controllers[index],
            focusNode: _focusNodes[index],
            textAlign: TextAlign.center,
            maxLength: 1,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.primaryText,
              fontFamily: 'monospace',
            ),
            cursorColor: colors.accent,
            decoration: InputDecoration(
              counterText: '',
              filled: true,
              fillColor: colors.cardSurface,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(radii.sm)),
                borderSide: BorderSide(color: borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(radii.sm)),
                borderSide: BorderSide(color: borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(radii.sm)),
                borderSide: BorderSide(
                  color: _hasError ? colors.danger : colors.accent,
                  width: 1.5,
                ),
              ),
            ),
            onChanged: (value) {
              _clearInputError();
              if (value.isNotEmpty && index < _codeLength - 1) {
                _focusBox(index + 1);
              }
              // Auto-submit when all filled.
              if (_code.length == _codeLength) {
                _verify();
              }
            },
          ),
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