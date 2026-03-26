import 'package:flutter/material.dart';

import 'admin_detail_scaffold.dart';

/// Admin shell tuned for dense workspace and management surfaces.
///
/// Extends [AdminDetailScaffold] with optional [searchBar] and
/// [filterActions] for the common admin dense layout pattern.
class DenseAdminWorkspaceScaffold extends StatelessWidget {
  const DenseAdminWorkspaceScaffold({
    required this.child,
    this.title,
    this.subtitle,
    this.actions,
    this.onBack,
    this.backTooltip,
    this.searchBar,
    this.filterActions,
    this.padding,
    super.key,
  });

  final Widget child;

  /// Optional title rendered at the top of body.
  final Widget? title;

  /// Optional subtitle rendered below [title].
  final Widget? subtitle;

  final List<Widget>? actions;
  final VoidCallback? onBack;
  final String? backTooltip;

  /// Optional search bar rendered between the title block and body.
  final Widget? searchBar;

  /// Optional filter action widgets (e.g. FilterChips) rendered below
  /// the search bar.
  final List<Widget>? filterActions;

  /// Custom padding override.
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    Widget body = child;
    if (searchBar != null || filterActions != null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ?searchBar,
          if (filterActions != null && filterActions!.isNotEmpty) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: filterActions!),
            ),
          ],
          if (searchBar != null || filterActions != null)
            const SizedBox(height: 12),
          Expanded(child: child),
        ],
      );
    }

    return AdminDetailScaffold(
      onBack: onBack,
      backTooltip: backTooltip,
      actions: actions,
      title: title,
      subtitle: subtitle,
      padding: padding,
      child: body,
    );
  }
}
