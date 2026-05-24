import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/env/app_env.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class InviteScreen extends ConsumerStatefulWidget {
  const InviteScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  ConsumerState<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends ConsumerState<InviteScreen> {
  final _target = TextEditingController();
  String _role = 'member';
  CollectionInvite? _lastInvite;

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final env = ref.watch(appEnvProvider);
    final baseUrl = env.publicUrl.isEmpty
        ? 'https://collect.rw'
        : env.publicUrl;
    final invite = _lastInvite;
    final link = invite == null ? null : '$baseUrl/i/${invite.inviteToken}';

    return ScreenScaffold(
      title: 'Invite members',
      subtitle:
          'Invite by Rwanda phone number or 6-digit Collect user ID. Contact-book access is not requested.',
      children: [
        const InfoSecurityBanner(
          title: 'Private invite',
          message:
              'Invite tokens are private. Phone numbers are normalized and matched securely.',
          tone: CollectStatusTone.privacy,
        ),
        CollectCard(
          child: Column(
            children: [
              TextField(
                controller: _target,
                decoration: collectInputDecoration(
                  context,
                  label: 'Phone number or user ID',
                ),
              ),
              CollectSpacing.gap12,
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: collectInputDecoration(
                  context,
                  label: 'Invite role',
                ),
                items: const [
                  DropdownMenuItem(value: 'member', child: Text('Member')),
                  DropdownMenuItem(
                    value: 'contributor',
                    child: Text('Contributor'),
                  ),
                  DropdownMenuItem(value: 'viewer', child: Text('Viewer')),
                  DropdownMenuItem(value: 'receiver', child: Text('Receiver')),
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                ],
                onChanged: (value) => setState(() => _role = value ?? _role),
              ),
              CollectSpacing.gap16,
              CollectButton(
                label: 'Generate invite link',
                icon: CollectIcons.share,
                onPressed: () async {
                  final invite = await ref
                      .read(collectRepositoryProvider.notifier)
                      .createInvite(
                        collectionId: widget.collectionId,
                        target: _target.text,
                        role: _role,
                      );
                  setState(() => _lastInvite = invite);
                },
                expand: true,
              ),
            ],
          ),
        ),
        if (invite != null && link != null)
          CollectCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CollectStatusChip(
                  label: invite.role,
                  tone: CollectStatusTone.info,
                ),
                CollectSpacing.gap12,
                Text(
                  'Prepared for ${invite.invitedTarget ?? 'invited member'}.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                CollectSpacing.gap8,
                SelectableText(link),
                CollectSpacing.gap16,
                CollectButton(
                  label: 'Copy invite link',
                  icon: CollectIcons.copy,
                  onPressed: () => copyToClipboard(
                    context,
                    link,
                    message: 'Invite link copied.',
                  ),
                  variant: CollectButtonVariant.secondary,
                  expand: true,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
