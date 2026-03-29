import 'package:flutter/material.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/rs_colors.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../features/rayon/widgets/partner_navigation.dart';

class CoreAppScaffold extends StatelessWidget {
  const CoreAppScaffold({
    required this.child,
    this.title = '',
    this.titleWidget,
    this.actions,
    this.showBackButton = true,
    this.showHomeButton = true,
    this.fallbackLocation = AppRoutes.rayonHome,
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
    return Scaffold(
      backgroundColor: colors.appBackground,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 84,
        flexibleSpace: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.appBackground.withValues(alpha: 0.88),
            border: Border(
              bottom: BorderSide(color: colors.border.withValues(alpha: 0.8)),
            ),
          ),
        ),
        leading: showBackButton
            ? buildPartnerBackButton(
                context,
                fallbackLocation: fallbackLocation,
                color: chromeColor,
              )
            : null,
        title: titleWidget ??
            Text(
              title,
              style: context.coolText.rayonCondensed(
                const TextStyle(fontSize: 32),
                fontWeight: FontWeight.w900,
                color: chromeColor,
                letterSpacing: 0.8,
              ),
            ),
        actions: buildPartnerAppBarActions(
          context,
          actions: actions,
          showHomeButton: showHomeButton,
          homeColor: chromeColor,
        ),
      ),
      body: CoolScreenBackground(
        primaryColor: RsColors.rsRed,
        secondaryColor: RsColors.rsGold,
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
