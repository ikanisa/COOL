import 'package:flutter/material.dart';
import '../repositories/collect_repository.dart';
import 'collect_components.dart';

/// Paged histories retain a visible retry path, including after a revision change.
class CollectHistoryFooter extends StatelessWidget {
  const CollectHistoryFooter({
    required this.feed,
    required this.onMore,
    required this.onRefresh,
    super.key,
  });
  final MemberHistoryState feed;
  final VoidCallback onMore;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    if (feed.page?.nextCursor == null) return const SizedBox.shrink();
    final changed = feed.error?.startsWith('History changed') == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CollectSpacing.x3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (feed.error != null) ...[
            Text(feed.error!, textAlign: TextAlign.center),
            CollectSpacing.gap8,
          ],
          CollectButton(
            label: feed.loading
                ? 'Loading'
                : changed
                ? 'Refresh'
                : feed.error != null
                ? 'Retry'
                : 'Load more',
            onPressed: feed.loading
                ? null
                : changed
                ? onRefresh
                : onMore,
          ),
        ],
      ),
    );
  }
}
