import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_market.dart';
import '../../../core/config/country_catalog.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/utils/phone_validator.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../providers/auth_provider.dart';
import '../providers/whatsapp_otp_provider.dart';

part 'whatsapp_otp_parts.dart';

/// Full-screen WhatsApp OTP verification.
///
/// Returns `true` when the user successfully verifies and logs in.
/// Returns `false` or `null` when the user dismisses.
class WhatsAppOtpScreen extends ConsumerStatefulWidget {
  const WhatsAppOtpScreen({super.key, this.initialPhone});

  final String? initialPhone;

  /// Show as a full-screen route pushed on top of current navigator.
  static Future<bool?> show(BuildContext context, {String? initialPhone}) {
    return Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => WhatsAppOtpScreen(initialPhone: initialPhone),
      ),
    );
  }

  @override
  ConsumerState<WhatsAppOtpScreen> createState() => _WhatsAppOtpScreenState();
}

class _WhatsAppOtpScreenState extends ConsumerState<WhatsAppOtpScreen> {
  final _phoneController = TextEditingController();
  final _otpControllers = List.generate(6, (_) => TextEditingController());
  final _otpFocusNodes = List.generate(6, (_) => FocusNode());
  bool _isVerifyingCode = false;
  Timer? _retryTimer;
  int _retryCountdown = 0;

  @override
  void initState() {
    super.initState();
    // Reset OTP state on open.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref.read(whatsAppOtpStateProvider.notifier).reset();
      final initialPhone = _normalizeInitialPhone(widget.initialPhone);
      if (initialPhone.isNotEmpty) {
        _phoneController.text = initialPhone;
      }
    });
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _phoneController.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  CoolCountry get _country =>
      CoolCountryCatalog.resolve(country: AppMarket.countryCode);

  String _normalizeInitialPhone(String? phone) {
    final trimmed = phone?.trim() ?? '';
    if (trimmed.isEmpty) {
      return '';
    }

    if (_country.isoCode == 'RW') {
      final local = PhoneValidator.toRwandanLocal(trimmed);
      if (local != null) {
        return local;
      }
    }

    return trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  }

  void _syncRetryCountdown(int? retryAfterSeconds) {
    _retryTimer?.cancel();
    if (!mounted || retryAfterSeconds == null || retryAfterSeconds <= 0) {
      if (_retryCountdown != 0) {
        setState(() => _retryCountdown = 0);
      }
      return;
    }

    setState(() => _retryCountdown = retryAfterSeconds);
    _retryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_retryCountdown <= 1) {
        timer.cancel();
        setState(() => _retryCountdown = 0);
        return;
      }
      setState(() => _retryCountdown -= 1);
    });
  }

  void _clearOtpInputs() {
    for (final controller in _otpControllers) {
      controller.clear();
    }
    if (mounted) {
      setState(() {});
    }
  }

  /// Distributes a multi-digit pasted OTP code across the 6 input boxes.
  void _distributeOtpDigits(String digits) {
    final chars = digits.replaceAll(RegExp(r'[^0-9]'), '').split('');
    for (var i = 0; i < 6; i++) {
      _otpControllers[i].text = i < chars.length ? chars[i] : '';
    }
    // Place cursor after the last filled box, or on the last box.
    final focusIndex = (chars.length - 1).clamp(0, 5);
    _otpFocusNodes[focusIndex].requestFocus();
    setState(() {});
    // Auto-verify when all 6 are filled.
    final full = _otpControllers.every((c) => c.text.trim().isNotEmpty);
    if (full) {
      _verifyCode();
    }
  }

  void _sendCode() {
    // FN-01: Guard against double-sends during countdown sync lag.
    if (_retryCountdown > 0) {
      return;
    }
    final otpState = ref.read(whatsAppOtpStateProvider);
    if (otpState.isLoading) {
      return;
    }
    final raw = _phoneController.text.trim();
    final validationError = PhoneValidator.validateOtpPhone(raw, _country);
    if (validationError != null) {
      CoolToast.error(context, validationError);
      return;
    }
    final e164 = PhoneValidator.buildOtpE164Phone(raw, _country);
    ref.read(whatsAppOtpStateProvider.notifier).sendCode(e164);
  }

  Future<void> _verifyCode() async {
    if (_isVerifyingCode || ref.read(whatsAppOtpStateProvider).isLoading) {
      return;
    }

    final code = _otpControllers.map((c) => c.text.trim()).join();
    if (code.length != 6) {
      CoolToast.error(context, context.l10n.otpEnterAllDigits);
      return;
    }

    _isVerifyingCode = true;
    try {
      final result = await ref
          .read(whatsAppOtpStateProvider.notifier)
          .verifyCode(code);

      if (!mounted) {
        return;
      }

      if (result.isVerified) {
        // Establish the session in AuthNotifier.
        final signedIn = await ref
            .read(authProvider.notifier)
            .signInWithOtpSession(
              accessToken: result.accessToken!,
              refreshToken: result.refreshToken!,
            );

        if (!mounted) {
          return;
        }

        if (!signedIn) {
          CoolToast.error(
            context,
            ref.read(authProvider).error ?? context.l10n.otpSessionOpenFailed,
          );
          return;
        }

        CoolToast.success(context, context.l10n.otpPhoneVerified);
        Navigator.of(context, rootNavigator: true).pop(true);
      }
    } finally {
      _isVerifyingCode = false;
    }
  }

  void _goBack() {
    final otpState = ref.read(whatsAppOtpStateProvider);
    if (otpState.step == WhatsAppOtpStep.verifyCode) {
      ref.read(whatsAppOtpStateProvider.notifier).goBackToPhone();
      _clearOtpInputs();
    } else {
      Navigator.of(context, rootNavigator: true).pop(false);
    }
  }

  void _resendCode(WhatsAppOtpState otpState) {
    if (otpState.phone.isEmpty || otpState.isLoading || _retryCountdown > 0) {
      return;
    }
    _clearOtpInputs();
    ref.read(whatsAppOtpStateProvider.notifier).sendCode(otpState.phone);
  }

  @override
  Widget build(BuildContext context) {
    final otpState = ref.watch(whatsAppOtpStateProvider);
    final colors = context.coolSemanticColors;

    ref.listen<WhatsAppOtpState>(whatsAppOtpStateProvider, (prev, next) {
      if (next.retryAfterSeconds != prev?.retryAfterSeconds) {
        _syncRetryCountdown(next.retryAfterSeconds);
      }
    });

    return CoolScreenBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: CoolSpace.x5),
            child: otpState.step == WhatsAppOtpStep.enterPhone
                ? _buildPhoneStep(otpState, colors)
                : _buildVerifyStep(otpState, colors),
          ),
        ),
      ),
    );
  }

  void _refreshOtpInputs() {
    if (mounted) {
      setState(() {});
    }
  }
}
