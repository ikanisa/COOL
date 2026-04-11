import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/cool_foundations.dart';
import '../../core/theme/cool_layout.dart';
import 'cool_floating_header_sliver.dart';
import 'cool_screen_background.dart';

/// Standard shell for non-tab detail routes.
///
/// The app bar hides on scroll-down and snaps back on scroll-up,
/// maximising content real-estate on forms and detail screens.
///
/// **Background ownership**: this scaffold is the single owner of
/// [CoolScreenBackground]. Child content must NOT wrap itself in another
/// background layer.
class CoreDetailScaffold extends StatelessWidget {
  const CoreDetailScaffold({
    required this.child,
    this.title,
    this.subtitle,
    this.actions,
    this.showBackButton = true,
    this.showHomeButton = false,
    this.showGlow = true,
    this.onBack,
    this.onHome,
    this.primaryColor,
    this.secondaryColor,
    this.backTooltip,
    this.homeTooltip,
    this.padding,
    this.bottomClearance = 96.0,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    super.key,
  });

  /// The primary body content.
  final Widget child;

  /// Optional title rendered at the top of body when provided.
  final Widget? title;

  /// Optional subtitle rendered below [title] when provided.
  final Widget? subtitle;

  final List<Widget>? actions;
  final bool showBackButton;
  final bool showHomeButton;
  final bool showGlow;
  final VoidCallback? onBack;
  final VoidCallback? onHome;
  final Color? primaryColor;
  final Color? secondaryColor;
  final String? backTooltip;
  final String? homeTooltip;

  /// Custom padding override. When null, defaults to
  /// [CoolSpace.scaffoldPadding] if [title] is non-null, otherwise no
  /// padding is applied (caller owns it).
  final EdgeInsets? padding;

  /// Bottom clearance added when [title] is non-null. Defaults to 96.
  final double bottomClearance;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;

  @override
  Widget build(BuildContext context) {
    final hasHeader = title != null || subtitle != null;
    final resolvedPadding =
        padding ??
        (hasHeader
            ? CoolLayout.rootPagePadding.copyWith(bottom: bottomClearance)
            : null);
    final resolvedBackTooltip =
        backTooltip ?? MaterialLocalizations.of(context).backButtonTooltip;
    final resolvedHomeTooltip = homeTooltip ?? context.l10n.home;
    final resolvedActions = <Widget>[
      if (showHomeButton)
        Semantics(
          button: true,
          label: resolvedHomeTooltip,
          child: IconButton(
            onPressed: onHome,
            tooltip: resolvedHomeTooltip,
            icon: const Icon(CoolIcons.home),
          ),
        ),
      ...?actions,
    ];
    final effectiveActions = resolvedActions.isEmpty ? null : resolvedActions;

    return CoolScreenBackground(
      primaryColor: primaryColor,
      secondaryColor: secondaryColor,
      showGlow: showGlow,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: floatingActionButton,
        floatingActionButtonLocation: floatingActionButtonLocation,
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            CoolFloatingHeaderSliver(
              automaticallyImplyLeading: false,
              leading: showBackButton
                  ? Semantics(
                      button: true,
                      label: resolvedBackTooltip,
                      child: IconButton(
                        onPressed:
                            onBack ?? () => Navigator.of(context).maybePop(),
                        tooltip: resolvedBackTooltip,
                        icon: const Icon(CoolIcons.back),
                      ),
                    )
                  : null,
              actions: effectiveActions,
            ),
          ],
          body: Padding(
            padding: resolvedPadding ?? EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ?title,
                if (subtitle != null) ...[
                  const SizedBox(height: CoolSpace.x2),
                  subtitle!,
                ],
                if (hasHeader) const SizedBox(height: CoolSpace.x5),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
