import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_glass_header_surface.dart';
import '../../../shared/widgets/cool_screen_background.dart';

class CoreAppScaffold extends StatelessWidget {
  const CoreAppScaffold({
    required this.child,
    this.title = '',
    this.titleWidget,
    this.actions,
    this.showBackButton = true,
    this.showHomeButton = true,
    this.fallbackLocation = AppRoutes.splash,
    this.padding = const EdgeInsets.fromLTRB(18, 18, 18, 96),
    this.scrollable = true,
    super.key,
  });

  final Widget child;
  final String title;
  final Widget? titleWidget;
  final List<Widget>? actions;
  final bool showBackButton;
  final bool showHomeButton;
  final String fallbackLocation;
  final EdgeInsets padding;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final chromeColor = colors.accentForeground;

    final resolvedActions = <Widget>[...?actions];
    if (showHomeButton) {
      resolvedActions.add(
        IconButton(
          icon: Icon(Icons.home_filled, color: chromeColor),
          onPressed: () {
            while (context.canPop()) {
              context.pop();
            }
            context.go(AppRoutes.splash);
          },
        ),
      );
    }

    return Scaffold(
      backgroundColor: colors.appBackground,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 84,
        flexibleSpace: const CoolGlassHeaderSurface(),
        leading: showBackButton
            ? IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: chromeColor),
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go(fallbackLocation);
                  }
                },
              )
            : null,
        title:
            titleWidget ??
            Text(
              title,
              style: context.coolText.displayCondensed(
                const TextStyle(fontSize: 32),
                fontWeight: FontWeight.w900,
                color: chromeColor,
                letterSpacing: 0.8,
              ),
            ),
        actions: resolvedActions,
      ),
      body: CoolScreenBackground(
        primaryColor: colors.accent,
        secondaryColor: colors.accentGold,
        child: SafeArea(
          top: false,
          child: scrollable
              ? SingleChildScrollView(padding: padding, child: child)
              : child,
        ),
      ),
    );
  }
}
