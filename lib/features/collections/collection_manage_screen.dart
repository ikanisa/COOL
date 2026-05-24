import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class CollectionManageScreen extends ConsumerWidget {
  const CollectionManageScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(collectRepositoryProvider.notifier);
    final collection = repo.collectionById(collectionId);

    return ScreenScaffold(
      title: 'Manage collection',
      subtitle: collection.title,
      children: [
        CollectCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: CollectSpacing.x2,
                runSpacing: CollectSpacing.x2,
                children: [
                  CollectStatusChip(
                    label: collection.visibility.replaceAll('_', ' '),
                    tone: statusToneFromText(collection.visibility),
                  ),
                  CollectStatusChip(
                    label: collection.publicStatus.replaceAll('_', ' '),
                    tone: statusToneFromText(collection.publicStatus),
                  ),
                ],
              ),
              CollectSpacing.gap16,
              CollectListTile(
                leading: CollectIcons.public,
                title: 'Request public listing',
                subtitle:
                    'Admin approval is required before this appears in Public.',
                trailing: CollectButton(
                  label: 'Request',
                  onPressed: collection.publicStatus == 'private'
                      ? () async {
                          await ref
                              .read(collectRepositoryProvider.notifier)
                              .requestPublic(collectionId);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Public listing request sent for admin review.',
                              ),
                            ),
                          );
                        }
                      : null,
                ),
              ),
              CollectListTile(
                leading: CollectIcons.people,
                title: 'Invite members',
                subtitle: 'Invite by phone number or 6-digit Collect ID.',
                onTap: () => context.go('/collections/$collectionId/invite'),
              ),
              CollectListTile(
                leading: CollectIcons.ledger,
                title: 'Ledger and review queue',
                subtitle: 'Confirmed support and ambiguous MOMO events.',
                onTap: () => context.go('/collections/$collectionId/ledger'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
