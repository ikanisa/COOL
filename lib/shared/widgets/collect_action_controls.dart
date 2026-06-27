import 'package:flutter/material.dart';

import '../../app/theme/collect_colors.dart';
import '../../app/theme/collect_icons.dart';
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

class CollectMomoReceiverModeToggle extends StatelessWidget {
  const CollectMomoReceiverModeToggle({
    required this.mode,
    required this.onChanged,
    super.key,
  });

  final CollectMomoReceiverMode mode;
  final ValueChanged<CollectMomoReceiverMode> onChanged;

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
        padding: const EdgeInsets.all(CollectSpacing.x1),
        child: Row(
          children: [
            Expanded(
              child: _CollectMomoReceiverModeButton(
                label: 'MoMo Number',
                icon: CollectIcons.momo,
                selected: mode == CollectMomoReceiverMode.momoNumber,
                onTap: () => onChanged(CollectMomoReceiverMode.momoNumber),
              ),
            ),
            CollectSpacing.gapW8,
            Expanded(
              child: _CollectMomoReceiverModeButton(
                label: 'MoMo Code',
                icon: CollectIcons.qr,
                selected: mode == CollectMomoReceiverMode.momoPayCode,
                onTap: () => onChanged(CollectMomoReceiverMode.momoPayCode),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollectMomoReceiverModeButton extends StatelessWidget {
  const _CollectMomoReceiverModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = selected ? colors.onAccent : colors.textSecondary;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          borderRadius: CollectRadius.controlBorder,
          onTap: onTap,
          child: AnimatedContainer(
            duration: CollectMotion.duration(context, CollectMotion.fast),
            curve: CollectMotion.standard,
            height: 46,
            decoration: BoxDecoration(
              color: selected ? colors.actionColor : colors.transparent,
              borderRadius: CollectRadius.controlBorder,
              border: Border.all(
                color: selected ? colors.actionColor : colors.glassBorder,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: CollectSpacing.x2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: foreground, size: 19),
                CollectSpacing.gapW8,
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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
    required this.controller,
    this.numberInputLabel = 'MoMo number',
    this.codeInputLabel = 'MoMo code',
    super.key,
  });

  final CollectMomoReceiverMode mode;
  final ValueChanged<CollectMomoReceiverMode> onChanged;
  final TextEditingController controller;
  final String numberInputLabel;
  final String codeInputLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final isCode = mode == CollectMomoReceiverMode.momoPayCode;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.glassControl,
        borderRadius: CollectRadius.controlBorder,
        border: Border.all(color: colors.glassBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(CollectSpacing.x1),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _CollectMomoReceiverModeSegment(
                    label: 'MoMo Number',
                    icon: CollectIcons.momo,
                    selected: !isCode,
                    onTap: () => onChanged(CollectMomoReceiverMode.momoNumber),
                  ),
                ),
                CollectSpacing.gapW8,
                Expanded(
                  child: _CollectMomoReceiverModeSegment(
                    label: 'MoMo Code',
                    icon: CollectIcons.qr,
                    selected: isCode,
                    onTap: () => onChanged(CollectMomoReceiverMode.momoPayCode),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CollectSpacing.x3,
                CollectSpacing.x1,
                CollectSpacing.x3,
                CollectSpacing.x1,
              ),
              child: Row(
                children: [
                  Icon(
                    isCode ? CollectIcons.qr : CollectIcons.momo,
                    color: colors.textSecondary,
                    size: 22,
                  ),
                  CollectSpacing.gapW12,
                  Expanded(
                    child: TextField(
                      controller: controller,
                      keyboardType: isCode
                          ? TextInputType.number
                          : TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      autofillHints: isCode
                          ? null
                          : const [AutofillHints.telephoneNumber],
                      decoration: InputDecoration(
                        hintText: isCode ? codeInputLabel : numberInputLabel,
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
          ],
        ),
      ),
    );
  }
}

class _CollectMomoReceiverModeSegment extends StatelessWidget {
  const _CollectMomoReceiverModeSegment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = selected ? colors.onAccent : colors.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        borderRadius: CollectRadius.controlBorder,
        onTap: onTap,
        child: AnimatedContainer(
          duration: CollectMotion.duration(context, CollectMotion.fast),
          curve: CollectMotion.standard,
          height: 48,
          decoration: BoxDecoration(
            color: selected ? colors.actionColor : colors.transparent,
            borderRadius: CollectRadius.controlBorder,
            border: Border.all(
              color: selected ? colors.actionColor : colors.glassBorder,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: CollectSpacing.x2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: foreground, size: 19),
              CollectSpacing.gapW8,
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.clip,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
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
