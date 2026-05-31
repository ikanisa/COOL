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
  final _momo = TextEditingController();
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
      subtitle: profile == null ? null : '#${profile.publicId}',
      children: [
        CollectCard(
          child: Column(
            children: [
              TextField(
                controller: _momo,
                keyboardType: TextInputType.phone,
                decoration: collectInputDecoration(
                  context,
                  label: 'MoMo number',
                ),
              ),
              CollectSpacing.gap16,
              CollectButton(
                label: 'Save',
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
