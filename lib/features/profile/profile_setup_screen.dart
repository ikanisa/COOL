import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/security/phone_normalizer.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/providers/collect_app_state.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _momo = TextEditingController();
  bool _synced = false;
  int _step = 0;
  String? _error;

  @override
  void dispose() {
    _momo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(collectRepositoryProvider).currentProfile;
    if (!_synced && profile?.momoNumber?.trim().isNotEmpty == true) {
      _momo.text =
          PhoneNormalizer.tryNormalizeMtnMomoLocal(profile!.momoNumber!) ??
          profile.momoNumber!;
      _synced = true;
    }
    return ScreenScaffold(
      title: 'Profile setup',
      subtitle: profile == null
          ? 'Sign in to create a Collect ID.'
          : 'Step ${_step + 1} of 3',
      bottomAction: _bottomAction(context, profile),
      children: [
        if (profile == null)
          const MinimalStatePanel(
            icon: CollectIcons.profile,
            title: 'Sign in first.',
            message:
                'Collect creates your private 6-digit ID after WhatsApp verification.',
            tone: CollectStatusTone.warning,
          )
        else if (_step == 0)
          Column(
            children: [
              CollectIdDisplay(
                publicId: profile.publicId,
                onCopy: () => copyToClipboard(
                  context,
                  profile.publicId,
                  message: 'Collect ID copied.',
                ),
              ),
              const InfoSecurityBanner(
                title: 'Private identity',
                message:
                    'Use this Collect ID for group contributions. Collect does not ask members for display names or avatars.',
                tone: CollectStatusTone.privacy,
              ),
            ],
          )
        else if (_step == 1)
          FormSectionCard(
            title: 'Add MoMo number',
            errorTitle: 'Profile not saved',
            errorMessage: _error,
            children: [
              CollectTextInput(
                controller: _momo,
                label: 'MoMo number',
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.telephoneNumber],
              ),
            ],
          )
        else
          const MinimalStatePanel(
            icon: CollectIcons.tune,
            title: 'Stay ready for group activity.',
            message:
                'Notifications and SMS access help Collect show payment progress, confirmations, and owner ledger updates.',
            tone: CollectStatusTone.info,
          ),
      ],
    );
  }

  Widget _bottomAction(BuildContext context, CollectProfile? profile) {
    if (profile == null) {
      return BottomActionSurface(
        children: [
          CollectButton(
            label: 'Sign in',
            icon: CollectIcons.sms,
            onPressed: () => context.go('/auth'),
            expand: true,
          ),
        ],
      );
    }
    if (_step == 0) {
      return BottomActionSurface(
        children: [
          CollectButton(
            label: 'Continue',
            icon: CollectIcons.arrowForward,
            onPressed: () => setState(() => _step = 1),
            expand: true,
          ),
        ],
      );
    }
    if (_step == 1) {
      return BottomActionSurface(
        children: [
          CollectButton(
            label: 'Save MoMo number',
            icon: CollectIcons.check,
            onPressed: _saveMomoNumber,
            expand: true,
          ),
        ],
      );
    }
    return BottomActionSurface(
      children: [
        CollectButton(
          label: 'Device permissions',
          icon: CollectIcons.tune,
          onPressed: () => context.go('/permissions/device'),
          expand: true,
        ),
        CollectButton(
          label: 'Finish setup',
          icon: CollectIcons.check,
          onPressed: () {
            final pendingSlug = ref.read(pendingSharedGroupSlugProvider);
            if (pendingSlug?.trim().isNotEmpty == true) {
              context.go('/c/$pendingSlug');
            } else {
              context.go('/home');
            }
          },
          variant: CollectButtonVariant.secondary,
          expand: true,
        ),
      ],
    );
  }

  Future<void> _saveMomoNumber() async {
    try {
      await ref
          .read(collectRepositoryProvider.notifier)
          .updateProfile(momoNumber: _momo.text);
      if (!mounted) return;
      setState(() {
        _step = 2;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }
}
