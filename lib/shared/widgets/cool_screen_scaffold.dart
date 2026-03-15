import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/cool_palette.dart';

class CoolScreenScaffold extends StatelessWidget {
  const CoolScreenScaffold({
    required this.child,
    this.title,
    this.actions,
    this.showBackButton = true,
    this.padding = const EdgeInsets.fromLTRB(18, 0, 18, 96),
    super.key,
  });

  final Widget child;
  final String? title;
  final List<Widget>? actions;
  final bool showBackButton;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading:
            showBackButton
                ? IconButton(
                  onPressed: () => context.pop(),
                  icon: Icon(Icons.arrow_back_rounded, color: palette.text),
                )
                : null,
        actions: actions,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null) ...[
                Text(
                  title!,
                  style: GoogleFonts.dmSans(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    color: palette.text,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 24),
              ],
              child,
            ],
          ),
        ),
      ),
    );
  }
}
