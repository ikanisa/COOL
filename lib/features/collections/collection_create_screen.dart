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
      bottomAction: BottomActionSurface(
        children: [
          CollectButton(
            label: _creating ? 'Creating group' : 'Create group',
            icon: CollectIcons.check,
            onPressed: _creating ? null : _create,
            variant: CollectButtonVariant.primary,
            expand: true,
          ),
        ],
      ),
      children: [
        const MinimalStatePanel(
          icon: CollectIcons.sms,
          title: 'Android owner setup.',
          message:
              'Create a group from the Android owner device that receives MoMo confirmations. Collect uses SMS access to verify payments automatically.',
          tone: CollectStatusTone.privacy,
        ),
        FormSectionCard(
          title: 'Group profile',
          message:
              'Members see the group name, description, and public link. Receiver MoMo details are only shown during contribution review.',
          errorTitle: 'Create failed',
          errorMessage: _error,
          children: [
            CollectTextInput(
              controller: _title,
              label: 'Group name',
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              autocorrect: true,
            ),
            CollectTextInput(
              controller: _description,
              label: 'Description',
              maxLines: 3,
              textInputAction: TextInputAction.newline,
              textCapitalization: TextCapitalization.sentences,
              autocorrect: true,
            ),
            CollectTextInput(
              controller: _receiver,
              label: 'Receiver MoMo number',
              helper:
                  'Synced from your profile. Edit only if this group receives on a different number.',
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.telephoneNumber],
            ),
            const InfoSecurityBanner(
              title: 'SMS permission required',
              message:
                  'Collect will ask for Android SMS access so receiver-side MoMo confirmations can update the ledger.',
              tone: CollectStatusTone.privacy,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _create() async {
    final title = _title.text.trim();
    final receiver = _receiver.text.trim();
    if (title.isEmpty || receiver.isEmpty) {
      setState(() {
        _error = title.isEmpty ? 'Name required.' : 'MoMo number required.';
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
