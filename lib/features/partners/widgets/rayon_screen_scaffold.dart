import 'package:flutter/material.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/rs_colors.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import 'partner_navigation.dart';

class RayonScreenScaffold extends StatelessWidget {
  const RayonScreenScaffold({
    required this.child,
    required this.title,
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
        leading: showBackButton
            ? buildPartnerBackButton(
                context,
                fallbackLocation: fallbackLocation,
                color: chromeColor,
              )
            : null,
        title: Text(
          title,
          style: context.coolText.rayonCondensed(
            const TextStyle(fontSize: 30),
            fontWeight: FontWeight.w900,
            color: chromeColor,
            letterSpacing: 0.3,
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
        primaryColor: RsColors.rsBlue,
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
