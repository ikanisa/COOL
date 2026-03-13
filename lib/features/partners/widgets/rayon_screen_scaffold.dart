import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
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
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: showBackButton
            ? buildPartnerBackButton(
                context,
                fallbackLocation: fallbackLocation,
              )
            : null,
        title: Text(
          title,
          style: GoogleFonts.barlowCondensed(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: AppColors.rsWhite,
            letterSpacing: 0.2,
          ),
        ),
        actions: buildPartnerAppBarActions(
          context,
          actions: actions,
          showHomeButton: showHomeButton,
        ),
      ),
      body: CoolScreenBackground(
        primaryColor: AppColors.rsBlue,
        secondaryColor: AppColors.rsGold,
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
