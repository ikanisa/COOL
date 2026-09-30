import 'package:flutter/material.dart';

import 'collect_components.dart';

/// Focused confirmation pattern from the owner's DESK-026 cohort. Product
/// wording and consequences remain at the call site; dismissal never commits.
Future<bool> showCollectConfirmationSheet({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final returnFocus = FocusManager.instance.primaryFocus;
  final result = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: context.collectColors.transparent,
    barrierColor: CollectColors.publicBlack.withValues(alpha: 0.64),
    sheetAnimationStyle: CollectMotion.animationStyle(context),
    builder: (sheetContext) {
      final colors = sheetContext.collectColors;
      final stackActions =
          MediaQuery.textScalerOf(sheetContext).scale(1) >= 1.3 ||
          MediaQuery.sizeOf(sheetContext).width < 360;
      final cancel = CollectButton(
        label: cancelLabel,
        variant: CollectButtonVariant.secondary,
        onPressed: () => Navigator.of(sheetContext).pop(false),
        expand: true,
      );
      final confirm = CollectButton(
        label: confirmLabel,
        variant: destructive
            ? CollectButtonVariant.danger
            : CollectButtonVariant.primary,
        onPressed: () => Navigator.of(sheetContext).pop(true),
        expand: true,
      );
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: SingleChildScrollView(
          child: CollectBottomSheet(
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeSemantics(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.textMuted,
                        borderRadius: CollectRadius.pillBorder,
                      ),
                    ),
                  ),
                  CollectSpacing.gap20,
                  Semantics(
                    namesRoute: true,
                    header: true,
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: Theme.of(sheetContext).textTheme.titleLarge,
                    ),
                  ),
                  CollectSpacing.gap12,
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: Theme.of(sheetContext).textTheme.bodyMedium
                        ?.copyWith(color: colors.textSecondary),
                  ),
                  CollectSpacing.gap24,
                  if (stackActions) ...[
                    confirm,
                    CollectSpacing.gap12,
                    cancel,
                  ] else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: cancel),
                        CollectSpacing.gapW12,
                        Expanded(child: confirm),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
  if (context.mounted && returnFocus?.context != null) {
    returnFocus!.requestFocus();
  }
  return result ?? false;
}
