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
  final _phone = TextEditingController(text: '+');
  final _otp = TextEditingController();
  final _captchaToken = TextEditingController();
  bool _otpSent = false;

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
      title: _otpSent ? 'Enter WhatsApp OTP' : 'Welcome to Collect',
      subtitle: 'Collect IDs, MoMo intents, and SMS verification.',
      children: [
        const InfoSecurityBanner(
          title: 'What Collect does',
          message:
              'Collect creates group payment intents and matches receiver MoMo SMS automatically.',
          tone: CollectStatusTone.info,
        ),
        CollectCard(
          child: Column(
            children: [
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: collectInputDecoration(
                  context,
                  label: 'WhatsApp phone',
                  helper: 'Use your full international WhatsApp number.',
                ),
              ),
              if (_otpSent) ...[
                CollectSpacing.gap12,
                TextField(
                  controller: _otp,
                  keyboardType: TextInputType.number,
                  decoration: collectInputDecoration(
                    context,
                    label: 'WhatsApp OTP',
                  ),
                ),
              ],
              if (env.authCaptchaEnabled) ...[
                CollectSpacing.gap12,
                TextField(
                  controller: _captchaToken,
                  decoration: collectInputDecoration(
                    context,
                    label:
                        '${env.authCaptchaProvider.isEmpty ? 'CAPTCHA' : env.authCaptchaProvider} verification token',
                  ),
                ),
              ],
              CollectSpacing.gap16,
              CollectButton(
                label: _otpSent ? 'Verify and continue' : 'Send WhatsApp OTP',
                icon: _otpSent ? CollectIcons.shield : CollectIcons.sms,
                onPressed: () async {
                  try {
                    final phone = PhoneNormalizer.normalizeInternational(
                      _phone.text,
                    );
                    final client = ref.read(supabaseClientProvider);
                    final captchaToken = env.authCaptchaEnabled
                        ? _captchaToken.text.trim()
                        : '';
                    if (env.authCaptchaEnabled && captchaToken.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Complete CAPTCHA verification first.'),
                        ),
                      );
                      return;
                    }
                    if (!_otpSent) {
                      if (client != null) {
                        await client.auth.signInWithOtp(
                          phone: phone,
                          channel: OtpChannel.whatsapp,
                          captchaToken: captchaToken.isEmpty
                              ? null
                              : captchaToken,
                        );
                      }
                      if (!mounted) return;
                      setState(() => _otpSent = true);
                      return;
                    }
                    if (client != null) {
                      await client.auth.verifyOTP(
                        phone: phone,
                        token: _otp.text,
                        type: OtpType.sms,
                        captchaToken: captchaToken.isEmpty
                            ? null
                            : captchaToken,
                      );
                    }
                    if (!context.mounted) return;
                    await ref
                        .read(collectRepositoryProvider.notifier)
                        .signInWithOtp(
                          phone: phone,
                          otp: _otp.text.isEmpty ? '000000' : _otp.text,
                        );
                    if (!context.mounted) return;
                    context.go('/auth/success');
                  } catch (_) {
                    if (context.mounted) context.go('/auth/failure');
                  }
                },
                expand: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
