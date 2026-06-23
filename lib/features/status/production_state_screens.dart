import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/models/collect_models.dart';
import '../../shared/providers/collect_app_state.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/utils/support_contact.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';
import '../collections/group_share_service.dart';

export 'onboarding_status_screens.dart';
export 'access_state_screens.dart';
export 'payment_status_screens.dart';
export 'device_privacy_screens.dart';
export 'account_legal_screens.dart';
export 'group_members_screen.dart';

class ProfileReadinessScreen extends ConsumerWidget {
  const ProfileReadinessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readiness = ref.watch(profileReadinessProvider);
    return ScreenScaffold(
      title: readiness.readyForGroupCreation
          ? 'Profile ready'
          : 'Finish profile',
      children: [
        if (readiness.collectId != null)
          CollectIdDisplay(publicId: readiness.collectId!),
        _ReadinessRows(
          rows: [
            _ReadinessRow(
              label: readiness.collectId == null
                  ? 'Profile'
                  : readiness.collectId!,
              ready: readiness.hasProfile,
            ),
            _ReadinessRow(label: 'MoMo saved', ready: readiness.hasMomoNumber),
          ],
        ),
        CollectButton(
          label: readiness.readyForGroupCreation
              ? 'Open groups'
              : 'Add MoMo number',
          icon: readiness.readyForGroupCreation
              ? CollectIcons.collections
              : CollectIcons.momo,
          onPressed: () => context.go(
            readiness.readyForGroupCreation ? '/groups' : '/settings/profile',
          ),
          expand: true,
        ),
      ],
    );
  }
}

class GroupCreatedSuccessScreen extends ConsumerWidget {
  const GroupCreatedSuccessScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collection = _safeCollection(ref, collectionId);
    return ScreenScaffold(
      title: 'Group created',
      children: [
        _StateHero(
          icon: CollectIcons.check,
          title: collection?.title ?? 'Group ready.',
          tone: CollectStatusTone.success,
        ),
        CollectButton(
          label: 'Share',
          icon: CollectIcons.share,
          onPressed: collection == null
              ? null
              : () => shareGroupDeepLink(
                  context: context,
                  ref: ref,
                  collection: collection,
                ),
          expand: true,
        ),
        CollectButton(
          label: 'Open group',
          icon: CollectIcons.collections,
          onPressed: () => context.go('/groups/$collectionId'),
          variant: CollectButtonVariant.secondary,
          expand: true,
        ),
      ],
    );
  }
}

class JoinGroupConfirmationScreen extends ConsumerWidget {
  const JoinGroupConfirmationScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collection = _safeCollection(ref, collectionId);
    return ScreenScaffold(
      title: 'Group joined',
      children: [
        CollectBottomSheet(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StateHero(
                icon: CollectIcons.check,
                title: collection?.title ?? 'Joined.',
                tone: CollectStatusTone.success,
              ),
              CollectSpacing.gap16,
              CollectButton(
                label: 'Open group',
                icon: CollectIcons.collections,
                onPressed: () => context.go('/groups/$collectionId'),
                expand: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class SharedLinkProblemScreen extends StatelessWidget {
  const SharedLinkProblemScreen({required this.expired, super.key});

  final bool expired;

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: expired ? 'Link expired' : 'Link unavailable',
      children: [
        _StateHero(
          icon: CollectIcons.error,
          title: expired ? 'Link expired.' : 'Link unavailable.',
          tone: CollectStatusTone.danger,
        ),
        const InfoSecurityBanner(
          title: 'Receiver privacy',
          message:
              'Invalid and expired public links never reveal receiver information. Receiver setup stays inside the contribution review step.',
          tone: CollectStatusTone.privacy,
        ),
        CollectButton(
          label: 'Scan QR',
          icon: CollectIcons.qr,
          onPressed: () => context.go('/groups/scan'),
          expand: true,
        ),
        CollectButton(
          label: 'Open groups',
          icon: CollectIcons.collections,
          onPressed: () => context.go('/groups'),
          variant: CollectButtonVariant.secondary,
          expand: true,
        ),
        if (expired)
          CollectButton(
            label: 'Request fresh link',
            icon: CollectIcons.sync,
            onPressed: () => context.go('/share/expired/request'),
            variant: CollectButtonVariant.secondary,
            expand: true,
          ),
        const CollectButton(
          label: 'Get help',
          icon: CollectIcons.support,
          onPressed: openCollectWhatsAppSupport,
          variant: CollectButtonVariant.subtle,
          expand: true,
        ),
      ],
    );
  }
}

class _StateHero extends StatelessWidget {
  const _StateHero({
    required this.icon,
    required this.title,
    this.tone = CollectStatusTone.info,
  });

  final IconData icon;
  final String title;
  final CollectStatusTone tone;

  @override
  Widget build(BuildContext context) {
    return CollectCard(
      padding: CollectSpacing.cardPaddingComfortable,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CollectStatusChip(label: title, tone: tone, icon: icon),
          CollectSpacing.gap20,
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
        ],
      ),
    );
  }
}

class _ReadinessRows extends StatelessWidget {
  const _ReadinessRows({required this.rows});

  final List<_ReadinessRow> rows;

  @override
  Widget build(BuildContext context) {
    return CollectCard(
      child: Column(
        children: [
          for (final row in rows)
            CollectListTile(
              leading: row.ready ? CollectIcons.check : CollectIcons.warning,
              title: row.label,
              trailing: CollectStatusChip(
                label: row.ready ? 'Ready' : 'Needs action',
                tone: row.ready
                    ? CollectStatusTone.success
                    : CollectStatusTone.warning,
              ),
            ),
        ],
      ),
    );
  }
}

class _ReadinessRow {
  const _ReadinessRow({required this.label, required this.ready});

  final String label;
  final bool ready;
}

CollectCollection? _safeCollection(WidgetRef ref, String collectionId) {
  return ref
      .read(collectRepositoryProvider.notifier)
      .maybeCollectionById(collectionId);
}
