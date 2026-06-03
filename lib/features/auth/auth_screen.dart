import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/env/app_env.dart';
import '../../core/security/phone_normalizer.dart';
import '../../core/supabase/supabase_module.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _phone = TextEditingController(text: '+250');
  final _otp = TextEditingController();
  final _captchaToken = TextEditingController();
  bool _otpSent = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _otp.dispose();
    _captchaToken.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final env = ref.watch(appEnvProvider);
    return ScreenScaffold(
      title: _otpSent ? 'Verify WhatsApp' : 'Collect',
      subtitle: _otpSent
          ? 'Enter the code sent to ${_phone.text.trim()}.'
          : 'Sign in with your WhatsApp number.',
      bottomAction: BottomActionSurface(
        children: [
          CollectButton(
            label: _submitting
                ? 'Checking'
                : _otpSent
                ? 'Verify and continue'
                : 'Send WhatsApp code',
            icon: _otpSent ? CollectIcons.shield : CollectIcons.sms,
            onPressed: _submitting ? null : () => _submit(env),
            expand: true,
          ),
          if (_otpSent)
            CollectButton(
              label: 'Use another number',
              icon: CollectIcons.tune,
              onPressed: _submitting
                  ? null
                  : () => setState(() {
                      _otpSent = false;
                      _otp.clear();
                      _error = null;
                    }),
              variant: CollectButtonVariant.secondary,
              expand: true,
            ),
        ],
      ),
      children: [
        MinimalStatePanel(
          icon: _otpSent ? CollectIcons.shield : CollectIcons.momo,
          title: _otpSent
              ? 'Enter your 6-digit code.'
              : 'MoMo groups, verified by SMS.',
          message: _otpSent
              ? 'Collect uses this code to secure your Collect ID and payment activity.'
              : 'Collect links your WhatsApp sign-in to a private Collect ID for group contributions.',
          tone: CollectStatusTone.privacy,
        ),
        FormSectionCard(
          errorTitle: 'Authentication failed',
          errorMessage: _error,
          children: [
            CollectTextInput(
              controller: _phone,
              label: 'WhatsApp phone',
              helper: 'Use international format, for example +250788123456.',
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.telephoneNumber],
            ),
            if (_otpSent) ...[
              OtpCodeField(controller: _otp),
              Text(
                'You can request a fresh code after 45 seconds.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (env.authCaptchaEnabled)
              CollectTextInput(
                controller: _captchaToken,
                label:
                    '${env.authCaptchaProvider.isEmpty ? 'CAPTCHA' : env.authCaptchaProvider} verification token',
                textInputAction: TextInputAction.done,
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _submit(AppEnv env) async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final phone = PhoneNormalizer.normalizeInternational(_phone.text);
      final client = ref.read(supabaseClientProvider);
      final captchaToken = env.authCaptchaEnabled
          ? _captchaToken.text.trim()
          : '';
      if (env.authCaptchaEnabled && captchaToken.isEmpty) {
        throw const FormatException('Complete CAPTCHA verification first.');
      }
      if (!_otpSent) {
        if (client != null) {
          await client.auth.signInWithOtp(
            phone: phone,
            channel: OtpChannel.whatsapp,
            captchaToken: captchaToken.isEmpty ? null : captchaToken,
          );
        }
        if (!mounted) return;
        setState(() {
          _otpSent = true;
          _submitting = false;
        });
        return;
      }
      if (client != null) {
        await client.auth.verifyOTP(
          phone: phone,
          token: _otp.text,
          type: OtpType.sms,
          captchaToken: captchaToken.isEmpty ? null : captchaToken,
        );
      }
      if (!mounted) return;
      await ref
          .read(collectRepositoryProvider.notifier)
          .signInWithOtp(phone: phone, otp: _otp.text);
      if (!mounted) return;
      context.go('/auth/success');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _submitting = false;
      });
    }
  }
}
