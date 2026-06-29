import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/providers/collect_app_state.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;

  @override
  Widget build(BuildContext context) {
    const steps = [
      (
        icon: CollectIcons.shield,
        title: 'MoMo groups, verified by SMS.',
        message:
            'Create or join a group, contribute through MoMo, and let Collect post confirmed payments to the ledger with your private Collect ID.',
        tone: CollectStatusTone.privacy,
      ),
      (
        icon: CollectIcons.privacy,
        title: 'Private by default.',
        message:
            'Public screens use Collect IDs, safe amounts, and status labels. Credentials, private message content, and receiver evidence stay off public surfaces.',
        tone: CollectStatusTone.privacy,
      ),
      (
        icon: CollectIcons.tune,
        title: 'Set up only what is needed.',
        message:
            'WhatsApp sign-in, MoMo profile, and Android owner SMS access are requested only when the flow needs them.',
        tone: CollectStatusTone.info,
      ),
    ];
    final current = steps[_step];
    return ScreenScaffold(
      title: 'Collect',
      subtitle: 'Step ${_step + 1} of ${steps.length}',
      bottomAction: BottomActionSurface(
        children: [
          CollectButton(
            label: _step == steps.length - 1 ? 'Get started' : 'Continue',
            icon: _step == steps.length - 1
                ? CollectIcons.arrowForward
                : CollectIcons.check,
            onPressed: () {
              if (_step < steps.length - 1) {
                setState(() => _step += 1);
                return;
              }
              ref.read(onboardingCompleteProvider.notifier).state = true;
              context.go('/auth');
            },
            expand: true,
          ),
          if (_step > 0)
            CollectButton(
              label: 'Back',
              icon: CollectIcons.chevron,
              variant: CollectButtonVariant.secondary,
              onPressed: () => setState(() => _step -= 1),
              expand: true,
            ),
        ],
      ),
      children: [
        CollectWizardProgress(
          labels: const ['Product', 'Privacy', 'Setup'],
          currentStep: _step,
        ),
        MinimalStatePanel(
          icon: current.icon,
          title: current.title,
          message: current.message,
          tone: current.tone,
          titleMaxLines: 2,
          messageMaxLines: 3,
          contentMaxWidth: 430,
        ),
        const _StepList(
          steps: [
            'Sign in with WhatsApp',
            'Confirm your Collect ID',
            'Link MoMo',
            'Join or create a group',
            'Pay through MoMo USSD',
          ],
        ),
      ],
    );
  }
}

class LegalConsentScreen extends ConsumerWidget {
  const LegalConsentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accepted = ref.watch(legalConsentAcceptedProvider);
    final foreground = context.collectColors.onImagePrimary;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: context.collectColors.transparent,
      body: CollectGradientBackground(
        routePath: '/onboarding/legal',
        child: SafeArea(
          child: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(
                  CollectSpacing.x5,
                  CollectSpacing.x5,
                  CollectSpacing.x5,
                  140,
                ),
                children: [
                  const ScreenHeader(title: 'Terms and privacy'),
                  SizedBox(height: MediaQuery.sizeOf(context).height * 0.14),
                  Text(
                    'Before you continue',
                    style: textTheme.displaySmall?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w900,
                      height: 1,
                      letterSpacing: 0,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  CollectSpacing.gap16,
                  Text(
                    'By continuing, you agree to Collect terms and privacy policy.',
                    style: textTheme.titleMedium?.copyWith(
                      color: foreground.withValues(alpha: 0.72),
                      fontWeight: FontWeight.w700,
                      height: 1.16,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    CollectSpacing.x4,
                    CollectSpacing.x2,
                    CollectSpacing.x4,
                    CollectSpacing.x4,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: CollectColors.referenceChromeBlack.withValues(
                        alpha: 0.72,
                      ),
                      borderRadius: CollectRadius.cardLargeBorder,
                      border: Border.all(
                        color: foreground.withValues(alpha: 0.16),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: CollectColors.referenceChromeBlack.withValues(
                            alpha: 0.32,
                          ),
                          blurRadius: 34,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(CollectSpacing.x4),
                      child: CollectButton(
                        label: accepted ? 'Continue' : 'Accept and continue',
                        icon: CollectIcons.check,
                        onPressed: () {
                          ref
                                  .read(legalConsentAcceptedProvider.notifier)
                                  .state =
                              true;
                          ref.read(onboardingCompleteProvider.notifier).state =
                              true;
                          context.go('/auth');
                        },
                        expand: true,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepList extends StatelessWidget {
  const _StepList({required this.steps});

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    return CollectCard(
      child: Column(
        children: [
          for (var index = 0; index < steps.length; index++)
            CollectListTile(
              leading: CollectIcons.check,
              title: steps[index],
              trailing: Text(
                '${index + 1}'.padLeft(2, '0'),
                style: CollectTypography.mono(context.collectColors.textMuted),
              ),
            ),
        ],
      ),
    );
  }
}
