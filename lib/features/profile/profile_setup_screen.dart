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
  bool _saving = false;
  bool _saved = false;
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
      subtitle: profile == null ? 'Sign in to create a Collect ID.' : null,
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
        else ...[
          if (_saved)
            const InfoSecurityBanner(
              title: 'Profile saved',
              message: 'Your MoMo account is ready for group activity.',
              tone: CollectStatusTone.success,
            ),
          FormSectionCard(
            title: 'Linked MoMo',
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
          ),
          CollectIdDisplay(
            publicId: profile.publicId,
            onCopy: () => copyToClipboard(
              context,
              profile.publicId,
              message: 'Collect ID copied.',
            ),
          ),
        ],
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
    return BottomActionSurface(
      children: [
        CollectButton(
          label: _saving ? 'Saving' : 'Save MoMo number',
          icon: CollectIcons.check,
          onPressed: _saving ? null : _saveMomoNumber,
          expand: true,
        ),
        CollectButton(
          label: 'Device permissions',
          icon: CollectIcons.tune,
          onPressed: () => context.go('/permissions/device'),
          variant: CollectButtonVariant.secondary,
          expand: true,
        ),
        CollectButton(
          label: 'Back to settings',
          icon: CollectIcons.chevron,
          onPressed: () => context.go('/settings'),
          variant: CollectButtonVariant.subtle,
          expand: true,
        ),
      ],
    );
  }

  Future<void> _saveMomoNumber() async {
    if (_momo.text.trim().isEmpty) {
      setState(() => _error = 'Enter your MTN MoMo number.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repository = ref.read(collectRepositoryProvider.notifier);
      await repository.updateProfile(momoNumber: _momo.text);
      if (!mounted) return;
      final pendingSlug = ref.read(pendingSharedGroupSlugProvider)?.trim();
      if (pendingSlug != null && pendingSlug.isNotEmpty) {
        final collection = await repository.joinGroupBySlug(pendingSlug);
        ref.read(pendingSharedGroupSlugProvider.notifier).state = null;
        if (!mounted) return;
        context.go('/groups/${collection.id}/joined');
        return;
      }
      setState(() {
        _saved = true;
        _saving = false;
        _error = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _saving = false;
        });
      }
    }
  }
}
