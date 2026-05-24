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
  final _name = TextEditingController();
  final _momo = TextEditingController(text: '+250788123456');
  final _avatar = TextEditingController();
  String _default = 'anonymous';

  @override
  void dispose() {
    _name.dispose();
    _momo.dispose();
    _avatar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(collectRepositoryProvider).currentProfile;
    return ScreenScaffold(
      title: 'Profile',
      subtitle:
          'Your public ID is ${profile == null ? 'created after login' : profile.publicId}. Phone and MOMO numbers are never shown publicly.',
      children: [
        const InfoSecurityBanner(
          title: 'Public identity',
          message:
              'Choose how your support appears. Anonymous and public ID modes never reveal phone or MOMO numbers.',
          tone: CollectStatusTone.privacy,
        ),
        CollectCard(
          child: Column(
            children: [
              TextField(
                controller: _name,
                decoration: collectInputDecoration(
                  context,
                  label: 'Display name',
                ),
              ),
              CollectSpacing.gap12,
              TextField(
                controller: _momo,
                keyboardType: TextInputType.phone,
                decoration: collectInputDecoration(
                  context,
                  label: 'MOMO number',
                  helper: 'Stored for receiver matching, never public.',
                ),
              ),
              CollectSpacing.gap12,
              TextField(
                controller: _avatar,
                keyboardType: TextInputType.url,
                decoration: collectInputDecoration(
                  context,
                  label: 'Avatar image URL, optional',
                  helper:
                      'Only shown publicly when your default identity is your display name.',
                ),
              ),
              CollectSpacing.gap12,
              DropdownButtonFormField<String>(
                initialValue: _default,
                decoration: collectInputDecoration(
                  context,
                  label: 'Default public identity',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'anonymous',
                    child: Text('Anonymous supporter'),
                  ),
                  DropdownMenuItem(
                    value: 'public_id',
                    child: Text('User public ID'),
                  ),
                  DropdownMenuItem(
                    value: 'display_name',
                    child: Text('Display name'),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => _default = value ?? _default),
              ),
              CollectSpacing.gap16,
              CollectButton(
                label: 'Save profile',
                icon: CollectIcons.check,
                onPressed: () async {
                  await ref
                      .read(collectRepositoryProvider.notifier)
                      .updateProfile(
                        displayName: _name.text,
                        momoNumber: _momo.text,
                        anonymityDefault: _default,
                        avatarUrl: _avatar.text,
                      );
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
