import 'package:flutter/material.dart';

import 'core_detail_scaffold.dart';

/// Standard detail shell for admin-facing routes.
///
/// Thin wrapper over [CoreDetailScaffold] with admin defaults:
/// - `showGlow = false` (neutral admin surface)
/// - Wires through title/subtitle for consistent heading blocks.
class AdminDetailScaffold extends StatelessWidget {
  const AdminDetailScaffold({
    required this.child,
    this.title,
    this.subtitle,
    this.actions,
    this.onBack,
    this.showBackButton = true,
    this.showGlow = false,
    this.backTooltip,
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
  final bool showBackButton;
  final bool showGlow;
  final String? backTooltip;

  /// Custom padding override. Passed through to [CoreDetailScaffold].
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return CoreDetailScaffold(
      showGlow: showGlow,
      showBackButton: showBackButton,
      onBack: onBack,
      backTooltip: backTooltip,
      actions: actions,
      title: title,
      subtitle: subtitle,
      padding: padding,
      child: child,
    );
  }
}
