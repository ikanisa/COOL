import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/collect_app_state.dart';
import 'collect_components.dart';

class ScreenScaffold extends ConsumerWidget {
  const ScreenScaffold({
    required this.title,
    required this.children,
    this.subtitle,
    this.actions = const [],
    this.topChrome,
    this.hero,
    this.banner,
    this.persistentPill,
    this.bottomAction,
    this.onRefresh,
    this.scrollController,
    this.sliver,
    this.showHeader = true,
    this.compact = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? topChrome;
  final Widget? hero;
  final Widget? banner;
  final Widget? persistentPill;
  final Widget? bottomAction;
  final RefreshCallback? onRefresh;
  final ScrollController? scrollController;

  /// Lazy content following the small, static [children] section.
  final Widget? sliver;
  final List<Widget> children;
  final bool showHeader;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offlineSnapshot = ref.watch(offlineSnapshotStatusProvider);
    final stalePill = offlineSnapshot.usingStaleCache
        ? Semantics(
            liveRegion: true,
            label: offlineSnapshot.label,
            child: CollectStatusChip(
              label: offlineSnapshot.label,
              tone: CollectStatusTone.warning,
              icon: CollectIcons.sync,
            ),
          )
        : null;
    return ScreenScaffoldLayout(
      title: title,
      subtitle: subtitle,
      actions: actions,
      topChrome: topChrome,
      hero: hero,
      banner: banner,
      persistentPill: persistentPill ?? stalePill,
      bottomAction: bottomAction,
      onRefresh: onRefresh,
      scrollController: scrollController,
      sliver: sliver,
      showHeader: showHeader,
      compact: compact,
      children: children,
    );
  }
}
