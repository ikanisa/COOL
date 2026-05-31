import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';
import '../status/production_state_screens.dart';
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
  bool _creating = false;
  String? _error;

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
    if (profile == null || profile.momoNumber?.trim().isNotEmpty != true) {
      return const ProfileReadinessScreen();
    }
    if (!_syncedProfileMomo &&
        _receiver.text.trim().isEmpty &&
        profile.momoNumber?.trim().isNotEmpty == true) {
      _receiver.text = profile.momoNumber!;
      _syncedProfileMomo = true;
    }
    final canCreate = canCreateGroupsOnThisPlatform();
    if (!canCreate) {
      return const IphoneCreateUnavailableScreen();
    }
    return ScreenScaffold(
      title: 'Create group',
      children: [
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
                  label: 'Description',
                ),
              ),
              CollectSpacing.gap12,
              TextField(
                controller: _receiver,
                keyboardType: TextInputType.phone,
                decoration: collectInputDecoration(
                  context,
                  label: 'MoMo number',
                ),
              ),
              if (_error != null) ...[
                CollectSpacing.gap12,
                InfoSecurityBanner(
                  title: 'Create failed',
                  message: _error!,
                  tone: CollectStatusTone.danger,
                ),
              ],
              CollectSpacing.gap16,
              CollectButton(
                label: _creating ? 'Creating group' : 'Create group',
                icon: CollectIcons.check,
                onPressed: _creating ? null : _create,
                variant: CollectButtonVariant.primary,
                expand: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _create() async {
    final title = _title.text.trim();
    final receiver = _receiver.text.trim();
    if (title.isEmpty || receiver.isEmpty) {
      setState(() {
        _error = title.isEmpty ? 'Name required.' : 'Receiver required.';
      });
      return;
    }
    setState(() {
      _creating = true;
      _error = null;
    });
    final smsAccessGranted = await ref
        .read(collectRepositoryProvider.notifier)
        .setSmsAccess(true);
    if (!smsAccessGranted) {
      if (!mounted) return;
      context.go('/permissions/sms-denied');
      return;
    }
    try {
      final collection = await ref
          .read(collectRepositoryProvider.notifier)
          .createCollection(
            title: title,
            description: _description.text,
            receiverMomoNumber: receiver,
          );
      if (!mounted) return;
      context.go('/groups/${collection.id}/created');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = error.toString();
      });
    }
  }
}
