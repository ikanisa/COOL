import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';
import '../../core/theme/cool_layout.dart';
import 'cool_screen_background.dart';

/// Standard shell for primary tab-root surfaces (Home, Groups, MoMo, etc).
///
/// This owns the shared background treatment and neutral app bar chrome while
/// leaving the route body free to choose the right scroll container.
///
/// **Background ownership**: this scaffold is the single owner of
/// [CoolScreenBackground]. Child content must NOT wrap itself in another
/// background layer.
class CoreTabRootScaffold extends StatelessWidget {
  const CoreTabRootScaffold({
    required this.child,
    this.title,
    this.subtitle,
    this.actions,
    this.showGlow = true,
    this.primaryColor,
    this.secondaryColor,
    this.padding,
    this.addBottomNavClearance = true,
    super.key,
  });

  /// The primary body content.
  final Widget child;

  /// Optional title rendered above [child] when provided.
  final Widget? title;

  /// Optional subtitle rendered below [title] when provided.
  final Widget? subtitle;

  /// App bar trailing actions.
  final List<Widget>? actions;

  /// Whether the radial glow is rendered in the background.
  final bool showGlow;

  /// Optional background glow overrides used for partner-dominant variants.
  final Color? primaryColor;
  final Color? secondaryColor;

  /// Custom padding override. When null, defaults to
  /// [CoolLayout.rootPagePadding] if [title] is non-null, otherwise no
  /// padding is applied (caller owns it).
  final EdgeInsets? padding;

  /// Whether to add bottom-nav clearance at the bottom of the scroll area.
  /// Defaults to true for root tab screens that sit above the bottom nav.
  final bool addBottomNavClearance;

  @override
  Widget build(BuildContext context) {
    final hasHeader = title != null || subtitle != null;
    final defaultPadding = hasHeader
        ? (addBottomNavClearance
              ? CoolLayout.rootPagePadding
              : CoolLayout.rootPagePadding.copyWith(bottom: 0))
        : null;
    final resolvedPadding = padding ?? defaultPadding;

    Widget body;
    if (hasHeader) {
      body = Padding(
        padding: resolvedPadding ?? EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ?title,
            if (subtitle != null) ...[
              const SizedBox(height: CoolSpace.x2),
              subtitle!,
            ],
            const SizedBox(height: CoolSpace.x6),
            Expanded(child: child),
          ],
        ),
      );
    } else if (resolvedPadding != null) {
      body = Padding(padding: resolvedPadding, child: child);
    } else {
      body = child;
    }

    return CoolScreenBackground(
      primaryColor: primaryColor,
      secondaryColor: secondaryColor,
      showGlow: showGlow,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: actions,
        ),
        body: body,
      ),
    );
  }
}
