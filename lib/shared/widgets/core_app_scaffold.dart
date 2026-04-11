import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_floating_header_sliver.dart';
import '../../../shared/widgets/cool_screen_background.dart';

class CoreAppScaffold extends StatelessWidget {
  const CoreAppScaffold({
    required this.child,
    this.title = '',
    this.titleWidget,
    this.actions,
    this.showBackButton = true,
    this.showHomeButton = true,
    this.fallbackLocation = AppRoutes.home,
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
            context.go(AppRoutes.home);
          },
        ),
      );
    }

    return Scaffold(
      backgroundColor: colors.appBackground,
      body: CoolScreenBackground(
        primaryColor: colors.accent,
        secondaryColor: colors.accentGold,
        child: SafeArea(
          top: false,
          child: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              CoolFloatingHeaderSliver(
                automaticallyImplyLeading: false,
                leading: showBackButton
                    ? IconButton(
                        icon: Icon(
                          Icons.arrow_back_rounded,
                          color: chromeColor,
                        ),
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
                      style: context.coolText.headline(
                        Theme.of(context).textTheme.headlineLarge,
                        fontWeight: FontWeight.w600,
                        color: chromeColor,
                      ),
                    ),
                actions: resolvedActions,
              ),
            ],
            body: scrollable
                ? SingleChildScrollView(padding: padding, child: child)
                : child,
          ),
        ),
      ),
    );
  }
}
