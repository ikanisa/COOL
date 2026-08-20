import 'package:flutter/material.dart';
import '../../app/theme/collect_colors.dart';
import '../../app/theme/collect_radius.dart';
import '../../app/theme/collect_spacing.dart';

class BottomActionSurface extends StatelessWidget {
  const BottomActionSurface({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.panelSurface,
        borderRadius: CollectRadius.cardBorder,
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

typedef CollectAccessibleTextFieldBuilder =
    Widget Function(FocusNode focusNode);

class CollectAccessibleTextField extends StatefulWidget {
  const CollectAccessibleTextField({
    required this.controller,
    required this.label,
    required this.builder,
    this.onChanged,
    this.multiline = false,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final CollectAccessibleTextFieldBuilder builder;
  final ValueChanged<String>? onChanged;
  final bool multiline;

  @override
  State<CollectAccessibleTextField> createState() =>
      _CollectAccessibleTextFieldState();
}

class _CollectAccessibleTextFieldState
    extends State<CollectAccessibleTextField> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()..addListener(_refreshSemantics);
    widget.controller.addListener(_refreshSemantics);
  }

  @override
  void didUpdateWidget(covariant CollectAccessibleTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_refreshSemantics);
    widget.controller.addListener(_refreshSemantics);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refreshSemantics);
    _focusNode
      ..removeListener(_refreshSemantics)
      ..dispose();
    super.dispose();
  }

  void _refreshSemantics() {
    if (mounted) setState(() {});
  }

  void _setText(String value) {
    widget.controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    widget.onChanged?.call(value);
  }

  void _setSelection(TextSelection selection) {
    final length = widget.controller.text.length;
    widget.controller.selection = TextSelection(
      baseOffset: selection.baseOffset.clamp(0, length),
      extentOffset: selection.extentOffset.clamp(0, length),
      affinity: selection.affinity,
      isDirectional: selection.isDirectional,
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.text;
    return Semantics(
      container: true,
      excludeSemantics: true,
      tooltip: widget.label,
      value: value,
      textField: true,
      focusable: true,
      focused: _focusNode.hasFocus,
      multiline: widget.multiline,
      currentValueLength: value.length,
      onTap: _focusNode.requestFocus,
      onFocus: _focusNode.requestFocus,
      onSetText: _setText,
      onSetSelection: _setSelection,
      child: widget.builder(_focusNode),
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
        color: colors.controlSurface,
        borderRadius: CollectRadius.controlBorder,
        border: Border.all(color: colors.panelBorder),
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
              child: CollectAccessibleTextField(
                controller: controller,
                label: label,
                multiline: maxLines > 1,
                builder: (focusNode) => TextField(
                  focusNode: focusNode,
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
            ),
          ],
        ),
      ),
    );
  }
}
