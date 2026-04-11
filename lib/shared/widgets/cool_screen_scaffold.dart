import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/cool_foundations.dart';
import 'cool_floating_header_sliver.dart';
import 'cool_screen_background.dart';

class CoolScreenScaffold extends StatelessWidget {
  const CoolScreenScaffold({
    required this.child,
    this.title,
    this.actions,
    this.showBackButton = true,
    this.padding = CoolSpace.scaffoldPadding,
    super.key,
  });

  final Widget child;
  final String? title;
  final List<Widget>? actions;
  final bool showBackButton;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return CoolScreenBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = CoolResponsive.maxContentWidthForWidth(
                constraints.maxWidth,
              );
              return NestedScrollView(
                headerSliverBuilder: (context, innerBoxIsScrolled) => [
                  CoolFloatingHeaderSliver(
                    automaticallyImplyLeading: false,
                    leading: showBackButton
                        ? IconButton(
                            onPressed: () => context.pop(),
                            tooltip: MaterialLocalizations.of(
                              context,
                            ).backButtonTooltip,
                            icon: Icon(
                              Icons.arrow_back_rounded,
                              color: colors.primaryText,
                            ),
                          )
                        : null,
                    actions: actions,
                  ),
                ],
                body: SingleChildScrollView(
                  padding: padding,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (title != null) ...[
                            Semantics(
                              header: true,
                              child: Text(
                                title!,
                                style: theme.textTheme.headlineLarge?.copyWith(
                                  color: colors.primaryText,
                                ),
                              ),
                            ),
                            const SizedBox(height: CoolSpace.x7),
                          ],
                          child,
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
