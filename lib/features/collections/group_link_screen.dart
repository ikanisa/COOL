import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class GroupLinkScreen extends ConsumerStatefulWidget {
  const GroupLinkScreen({required this.slug, super.key});

  final String slug;

  @override
  ConsumerState<GroupLinkScreen> createState() => _GroupLinkScreenState();
}

class _GroupLinkScreenState extends ConsumerState<GroupLinkScreen> {
  late final Future<void> _openGroup = _joinAndOpen();

  Future<void> _joinAndOpen() async {
    final collection = await ref
        .read(collectRepositoryProvider.notifier)
        .joinGroupBySlug(widget.slug);
    if (!mounted) return;
    context.go('/groups/${collection.id}/joined');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _openGroup,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ScreenScaffold(
            title: 'Group link',
            subtitle: widget.slug,
            children: [
              CollectBottomSheet(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InfoSecurityBanner(
                      title: 'Link failed',
                      message: snapshot.error.toString(),
                      tone: CollectStatusTone.danger,
                    ),
                    CollectSpacing.gap16,
                    CollectButton(
                      label: 'Groups',
                      icon: CollectIcons.collections,
                      onPressed: () => context.go('/groups'),
                      expand: true,
                    ),
                    CollectSpacing.gap12,
                    CollectButton(
                      label: 'Link help',
                      icon: CollectIcons.info,
                      onPressed: () => context.go('/c/${widget.slug}/invalid'),
                      variant: CollectButtonVariant.secondary,
                      expand: true,
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        return ScreenScaffold(
          title: 'Opening group',
          subtitle: widget.slug,
          children: const [
            CollectBottomSheet(
              child: Center(child: CircularProgressIndicator.adaptive()),
            ),
          ],
        );
      },
    );
  }
}
