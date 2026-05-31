import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';
import 'group_creation_platform.dart';

class CollectionCreateScreen extends ConsumerStatefulWidget {
  const CollectionCreateScreen({super.key});

  @override
  ConsumerState<CollectionCreateScreen> createState() =>
      _CollectionCreateScreenState();
}

class _CollectionCreateScreenState
    extends ConsumerState<CollectionCreateScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _receiver = TextEditingController();
  bool _syncedProfileMomo = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _receiver.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(collectRepositoryProvider).currentProfile;
    if (!_syncedProfileMomo &&
        _receiver.text.trim().isEmpty &&
        profile?.momoNumber?.trim().isNotEmpty == true) {
      _receiver.text = profile!.momoNumber!;
      _syncedProfileMomo = true;
    }
    final canCreate = canCreateGroupsOnThisPlatform();
    return ScreenScaffold(
      title: 'Create group',
      subtitle: 'Name the group and confirm the receiver MoMo number.',
      children: [
        const InfoSecurityBanner(
          title: 'Android SMS access',
          message:
              'On Android, creating your first group starts SMS access consent so receiver MoMo notifications can be parsed automatically.',
          tone: CollectStatusTone.privacy,
        ),
        CollectCard(
          child: Column(
            children: [
              TextField(
                controller: _title,
                decoration: collectInputDecoration(
                  context,
                  label: 'Group name',
                ),
              ),
              CollectSpacing.gap12,
              TextField(
                controller: _description,
                maxLines: 3,
                decoration: collectInputDecoration(
                  context,
                  label: 'Description, optional',
                ),
              ),
              CollectSpacing.gap12,
              TextField(
                controller: _receiver,
                keyboardType: TextInputType.phone,
                decoration: collectInputDecoration(
                  context,
                  label: 'Receiver MoMo number',
                  helper:
                      'Synced from your profile. You can edit it for this group.',
                ),
              ),
              CollectSpacing.gap16,
              CollectButton(
                label: 'Create group',
                icon: CollectIcons.check,
                onPressed: canCreate
                    ? _create
                    : () => showAndroidGroupCreationOnlyDialog(context),
                variant: canCreate
                    ? CollectButtonVariant.primary
                    : CollectButtonVariant.secondary,
                expand: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _create() async {
    final smsAccessGranted =
        await ref.read(collectRepositoryProvider.notifier).setSmsAccess(true);
    if (!smsAccessGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SMS access is required to create a group.'),
        ),
      );
      return;
    }
    final collection = await ref
        .read(collectRepositoryProvider.notifier)
        .createCollection(
          title: _title.text.isEmpty ? 'Untitled group' : _title.text,
          description: _description.text,
          receiverMomoNumber: _receiver.text,
        );
    if (!mounted) return;
    context.go('/groups/${collection.id}');
  }
}
