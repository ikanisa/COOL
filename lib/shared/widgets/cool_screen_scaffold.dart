import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';

class CoolScreenScaffold extends StatelessWidget {
  const CoolScreenScaffold({
    required this.child,
    this.title,
    this.actions,
    this.showBackButton = true,
    this.padding = const EdgeInsets.fromLTRB(18, 18, 18, 96),
    super.key,
  });

  final Widget child;
  final String? title;
  final List<Widget>? actions;
  final bool showBackButton;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: title == null
          ? null
          : AppBar(
              automaticallyImplyLeading: false,
              leading: showBackButton
                  ? Semantics(
                      button: true,
                      label: MaterialLocalizations.of(
                        context,
                      ).backButtonTooltip,
                      child: IconButton(
                        onPressed: () => context.pop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    )
                  : null,
              title: Text(title!),
              actions: actions,
            ),
      body: SafeArea(
        top: title == null,
        child: SingleChildScrollView(padding: padding, child: child),
      ),
    );
  }
}
