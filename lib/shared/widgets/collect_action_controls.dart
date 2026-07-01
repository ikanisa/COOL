import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/collect_colors.dart';
import '../../app/theme/collect_motion.dart';
import '../../app/theme/collect_radius.dart';
import '../../app/theme/collect_shadows.dart';
import '../../app/theme/collect_spacing.dart';

class BottomActionSurface extends StatelessWidget {
  const BottomActionSurface({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.glassPanel,
        borderRadius: CollectRadius.cardBorder,
        border: Border.all(color: colors.glassBorder),
        boxShadow: CollectShadows.card(),
      ),
      child: Padding(
        padding: const EdgeInsets.all(CollectSpacing.x4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < children.length; index++) ...[
              children[index],
              if (index != children.length - 1) CollectSpacing.gap12,
            ],
          ],
        ),
      ),
    );
  }
}

enum CollectMomoReceiverMode { momoNumber, momoPayCode }

class CollectMobileInputField extends StatelessWidget {
  const CollectMobileInputField({
    required this.controller,
    required this.icon,
    required this.label,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.maxLines = 1,
    this.textCapitalization = TextCapitalization.none,
    this.autocorrect = false,
    super.key,
  });

  final TextEditingController controller;
  final IconData icon;
  final String label;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final int maxLines;
  final TextCapitalization textCapitalization;
  final bool autocorrect;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.glassControl,
        borderRadius: CollectRadius.controlBorder,
        border: Border.all(color: colors.glassBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CollectSpacing.x3,
          vertical: CollectSpacing.x1,
        ),
        child: Row(
          crossAxisAlignment: maxLines > 1
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            Padding(
              padding: EdgeInsets.only(
                top: maxLines > 1 ? CollectSpacing.x2 : 0,
              ),
              child: Icon(icon, color: colors.textSecondary, size: 22),
            ),
            CollectSpacing.gapW12,
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: keyboardType,
                textInputAction:
                    textInputAction ??
                    (maxLines > 1
                        ? TextInputAction.newline
                        : TextInputAction.next),
                autofillHints: autofillHints,
                maxLines: maxLines,
                textCapitalization: textCapitalization,
                autocorrect: autocorrect,
                decoration: InputDecoration(
                  labelText: label,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CollectMomoReceiverCard extends StatelessWidget {
  const CollectMomoReceiverCard({
    required this.mode,
    required this.onChanged,
    required this.numberController,
    required this.codeController,
    this.numberInputLabel = 'MoMo number',
    this.codeInputLabel = 'MoMo code',
    super.key,
  });

  final CollectMomoReceiverMode mode;
  final ValueChanged<CollectMomoReceiverMode> onChanged;
  final TextEditingController numberController;
  final TextEditingController codeController;
  final String numberInputLabel;
  final String codeInputLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final activeController = mode == CollectMomoReceiverMode.momoPayCode
        ? codeController
        : numberController;
    final activeHint = mode == CollectMomoReceiverMode.momoPayCode
        ? 'Code'
        : '07XXXXXXXX';
    final radius = BorderRadius.circular(30);
    return ClipRRect(
      borderRadius: radius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.glassControl,
          borderRadius: radius,
          border: Border.all(color: colors.glassBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(CollectSpacing.x2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _MomoModeTab(
                      label: 'Number',
                      semanticsLabel: numberInputLabel,
                      selected: mode == CollectMomoReceiverMode.momoNumber,
                      onTap: () =>
                          onChanged(CollectMomoReceiverMode.momoNumber),
                    ),
                  ),
                  CollectSpacing.gapW8,
                  Expanded(
                    child: _MomoModeTab(
                      label: 'Code',
                      semanticsLabel: codeInputLabel,
                      selected: mode == CollectMomoReceiverMode.momoPayCode,
                      onTap: () =>
                          onChanged(CollectMomoReceiverMode.momoPayCode),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: CollectSpacing.x1),
                child: Divider(
                  color: colors.glassBorder,
                  height: CollectSpacing.x4,
                ),
              ),
              SizedBox(
                height: 68,
                child: TextField(
                  key: ValueKey(mode),
                  controller: activeController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  autofillHints: mode == CollectMomoReceiverMode.momoNumber
                      ? const [AutofillHints.telephoneNumber]
                      : null,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(
                      mode == CollectMomoReceiverMode.momoPayCode ? 6 : 12,
                    ),
                  ],
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colors.textPrimary,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                  decoration: InputDecoration(
                    hintText: activeHint,
                    filled: true,
                    fillColor: colors.transparent,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: CollectSpacing.x3,
                      vertical: CollectSpacing.x1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MomoModeTab extends StatelessWidget {
  const _MomoModeTab({
    required this.label,
    required this.semanticsLabel,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String semanticsLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = selected ? colors.textPrimary : colors.textSecondary;
    return Tooltip(
      message: semanticsLabel,
      child: Semantics(
        button: true,
        selected: selected,
        label: semanticsLabel,
        child: ExcludeSemantics(
          child: InkWell(
            onTap: onTap,
            borderRadius: CollectRadius.controlBorder,
            child: AnimatedContainer(
              duration: CollectMotion.duration(context, CollectMotion.fast),
              curve: CollectMotion.standard,
              height: 48,
              decoration: BoxDecoration(
                color: selected
                    ? colors.glassPanel.withValues(alpha: 0.72)
                    : colors.transparent,
                borderRadius: CollectRadius.controlBorder,
              ),
              alignment: Alignment.center,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: foreground,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
