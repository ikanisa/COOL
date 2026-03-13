import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';

void popOrGo(BuildContext context, String fallbackLocation) {
  if (context.canPop()) {
    context.pop();
    return;
  }

  context.go(fallbackLocation);
}

IconButton buildPartnerBackButton(
  BuildContext context, {
  required String fallbackLocation,
  IconData icon = Icons.arrow_back_rounded,
  Color? color,
}) {
  return IconButton(
    onPressed: () => popOrGo(context, fallbackLocation),
    icon: Icon(icon),
    color: color,
    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
  );
}

IconButton buildPartnerHomeButton(BuildContext context, {Color? color}) {
  return IconButton(
    onPressed: () => context.go(AppRoutes.home),
    icon: const Icon(Icons.home_rounded),
    color: color ?? AppColors.rsWhite,
    tooltip: 'Home',
  );
}

List<Widget> buildPartnerAppBarActions(
  BuildContext context, {
  List<Widget>? actions,
  bool showHomeButton = true,
  Color? homeColor,
}) {
  return <Widget>[
    ...?actions,
    if (showHomeButton) buildPartnerHomeButton(context, color: homeColor),
  ];
}
