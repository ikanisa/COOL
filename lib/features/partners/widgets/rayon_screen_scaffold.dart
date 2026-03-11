import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_screen_background.dart';

class RayonScreenScaffold extends StatelessWidget {
  const RayonScreenScaffold({
    required this.child,
    required this.title,
    this.actions,
    this.showBackButton = true,
    this.padding = const EdgeInsets.fromLTRB(18, 18, 18, 96),
    this.scrollable = true,
    super.key,
  });

  final Widget child;
  final String title;
  final List<Widget>? actions;
  final bool showBackButton;
  final EdgeInsets padding;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: showBackButton
            ? IconButton(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back_rounded),
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
        actions: actions,
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
