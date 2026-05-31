import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _momo = TextEditingController(text: '+250788123456');
  bool _synced = false;

  @override
  void dispose() {
    _momo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(collectRepositoryProvider).currentProfile;
    if (!_synced && profile?.momoNumber?.trim().isNotEmpty == true) {
      _momo.text = profile!.momoNumber!;
      _synced = true;
    }
    return ScreenScaffold(
      title: 'Profile',
      subtitle:
          'Collect ID ${profile == null ? 'created after login' : profile.publicId}',
      children: [
        const InfoSecurityBanner(
          title: 'Collect ID only',
          message:
              'Collect uses your 6-digit ID for matching. Real names are not requested or shown.',
          tone: CollectStatusTone.privacy,
        ),
        CollectCard(
          child: Column(
            children: [
              TextField(
                controller: _momo,
                keyboardType: TextInputType.phone,
                decoration: collectInputDecoration(
                  context,
                  label: 'MoMo number',
                  helper:
                      'Used as the default receiver number for groups you create.',
                ),
              ),
              CollectSpacing.gap16,
              CollectButton(
                label: 'Save profile',
                icon: CollectIcons.check,
                onPressed: () async {
                  await ref
                      .read(collectRepositoryProvider.notifier)
                      .updateProfile(momoNumber: _momo.text);
                  if (!context.mounted) return;
                  context.go('/home');
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
