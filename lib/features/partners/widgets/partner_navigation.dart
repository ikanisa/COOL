import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';

void popOrGo(BuildContext context, String fallbackLocation) {
  if (context.canPop()) {
    context.pop();
    return;
  }

  context.go(fallbackLocation);
}

Widget buildPartnerBackButton(
  BuildContext context, {
  required String fallbackLocation,
  IconData icon = Icons.arrow_back_rounded,
  Color? color,
}) {
  return Semantics(
    button: true,
    label: MaterialLocalizations.of(context).backButtonTooltip,
    child: IconButton(
      onPressed: () => popOrGo(context, fallbackLocation),
      icon: Icon(icon),
      color: color,
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
    ),
  );
}

Widget buildPartnerHomeButton(BuildContext context, {Color? color}) {
  return Semantics(
    button: true,
    label: context.l10n.partnersHomeTooltip,
    child: IconButton(
      onPressed: () => context.go(AppRoutes.home),
      icon: const Icon(Icons.home_rounded),
      color: color ?? AppColors.rsWhite,
      tooltip: context.l10n.partnersHomeTooltip,
    ),
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
