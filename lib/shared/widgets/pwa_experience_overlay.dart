import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/pwa_providers.dart';
import '../../core/pwa/pwa_bridge_service.dart';
import '../../core/theme/cool_foundations.dart';
import 'cool_button.dart';
import 'cool_card.dart';
import 'ios_install_prompt.dart';

class PwaExperienceOverlay extends ConsumerStatefulWidget {
  const PwaExperienceOverlay({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<PwaExperienceOverlay> createState() =>
      _PwaExperienceOverlayState();
}

class _PwaExperienceOverlayState extends ConsumerState<PwaExperienceOverlay> {
  static const _installCtaDelay = Duration(seconds: 12);

  bool _dismissedInstallCard = false;
  bool _dismissedUpdateCard = false;
  bool _installCtaEligible = false;
  Timer? _installCtaTimer;

  @override
  void initState() {
    super.initState();
    _installCtaTimer = Timer(_installCtaDelay, () {
      if (!mounted) {
        return;
      }
      setState(() {
        _installCtaEligible = true;
      });
    });
  }

  @override
  void dispose() {
    _installCtaTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pwaBridge = ref.watch(pwaBridgeServiceProvider);

    return AnimatedBuilder(
      animation: pwaBridge,
      builder: (context, _) {
        final state = pwaBridge.state;
        final showUpdateCard = state.updateAvailable && !_dismissedUpdateCard;
        final showInstallCard =
            !showUpdateCard &&
            _installCtaEligible &&
            state.hasInstallCta &&
            !_dismissedInstallCard &&
            !state.isInstalled;

        if (!showUpdateCard && !showInstallCard) {
          return widget.child;
        }

        return Stack(
          children: [
            widget.child,
            Positioned(
              left: CoolSpace.x4,
              right: CoolSpace.x4,
              bottom: CoolSpace.x4,
              child: SafeArea(
                top: false,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: showUpdateCard
                        ? _PwaUpdateCard(
                            onDismiss: () {
                              setState(() {
                                _dismissedUpdateCard = true;
                              });
                            },
                            onRefresh: () async {
                              final activated = await pwaBridge.activateUpdate();
                              if (!activated && mounted) {
                                setState(() {
                                  _dismissedUpdateCard = true;
                                });
                              }
                            },
                          )
                        : _PwaInstallCard(
                            state: state,
                            onDismiss: () {
                              setState(() {
                                _dismissedInstallCard = true;
                              });
                            },
                            onPrimaryAction: () async {
                              if (state.canPromptInstall) {
                                await pwaBridge.promptInstall();
                                return;
                              }

                              if (!mounted) {
                                return;
                              }
                              await IosInstallPrompt.show(context);
                            },
                          ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PwaInstallCard extends StatelessWidget {
  const _PwaInstallCard({
    required this.state,
    required this.onPrimaryAction,
    required this.onDismiss,
  });

  final PwaBridgeState state;
  final Future<void> Function() onPrimaryAction;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final title = state.canPromptInstall
        ? 'Install COOL'
        : 'Add COOL to Home Screen';
    final message = state.canPromptInstall
        ? 'Install the app for faster admin access and standalone launch.'
        : 'Use Safari share actions to install the admin PWA on iPhone or iPad.';
    final primaryLabel = state.canPromptInstall ? 'Install' : 'How to install';

    return CoolCard(
      backgroundColor: colors.cardSurfaceStrong,
      borderColor: colors.borderStrong,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: CoolSpace.x2),
          Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.secondaryText,
              height: 1.45,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: CoolSpace.x4),
          Row(
            children: [
              Expanded(
                child: CoolButton(
                  label: primaryLabel,
                  onTap: () {
                    unawaited(onPrimaryAction());
                  },
                ),
              ),
              const SizedBox(width: CoolSpace.x2),
              Expanded(
                child: CoolButton(
                  label: 'Later',
                  variant: CoolButtonVariant.secondary,
                  onTap: onDismiss,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PwaUpdateCard extends StatelessWidget {
  const _PwaUpdateCard({
    required this.onRefresh,
    required this.onDismiss,
  });

  final Future<void> Function() onRefresh;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return CoolCard(
      backgroundColor: colors.cardSurfaceStrong,
      borderColor: colors.borderStrong,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Update ready',
            style: theme.textTheme.titleLarge?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: CoolSpace.x2),
          Text(
            'Refresh to load the latest admin workspace and app assets.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.secondaryText,
              height: 1.45,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: CoolSpace.x4),
          Row(
            children: [
              Expanded(
                child: CoolButton(
                  label: 'Refresh',
                  onTap: () {
                    unawaited(onRefresh());
                  },
                ),
              ),
              const SizedBox(width: CoolSpace.x2),
              Expanded(
                child: CoolButton(
                  label: 'Later',
                  variant: CoolButtonVariant.secondary,
                  onTap: onDismiss,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
