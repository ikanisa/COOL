import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'collect_components.dart';

class ScreenScaffold extends ConsumerWidget {
  const ScreenScaffold({
    required this.title,
    required this.children,
    this.subtitle,
    this.actions = const [],
    this.persistentPill,
    this.bottomAction,
    this.onRefresh,
    this.showHeader = true,
    this.compact = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? persistentPill;
  final Widget? bottomAction;
  final RefreshCallback? onRefresh;
  final List<Widget> children;
  final bool showHeader;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ScreenScaffoldLayout(
      title: title,
      subtitle: subtitle,
      actions: actions,
      persistentPill: persistentPill,
      bottomAction: bottomAction,
      onRefresh: onRefresh,
      showHeader: showHeader,
      compact: compact,
      children: children,
    );
  }
}
