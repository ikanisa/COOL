import 'package:flutter/material.dart';

import '../../../core/theme/cool_foundations.dart';

EdgeInsets _liveOpsBadgePadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x2,
  right: CoolSpace.x2,
  top: CoolSpace.x1,
  bottom: CoolSpace.x1,
);

EdgeInsets _liveOpsFieldPadding() => CoolSpace.sectionPadding.copyWith(
  left: 0,
  right: 0,
  top: 0,
  bottom: CoolSpace.x3,
);

EdgeInsets _liveOpsInputContentPadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x3,
  right: CoolSpace.x3,
  top: CoolSpace.x3,
  bottom: CoolSpace.x3,
);

EdgeInsets _liveOpsMetricPadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x3,
  right: CoolSpace.x3,
  top: CoolSpace.x2,
  bottom: CoolSpace.x2,
);

OutlineInputBorder _liveOpsInputBorder(
  CoolSemanticColors colors, {
  Color? borderColor,
  double width = 1,
}) {
  return OutlineInputBorder(
    borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.xs)),
    borderSide: BorderSide(color: borderColor ?? colors.border, width: width),
  );
}

class LiveOpsStatusBadge extends StatelessWidget {
  const LiveOpsStatusBadge({
    required this.label,
    required this.color,
    super.key,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: _liveOpsBadgePadding(),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.pill)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class LiveOpsTextField extends StatelessWidget {
  const LiveOpsTextField({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.maxLines = 1,
    super.key,
  });

  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return Padding(
      padding: _liveOpsFieldPadding(),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colors.primaryText,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: theme.textTheme.bodySmall?.copyWith(
            color: colors.tertiaryText,
            fontWeight: FontWeight.w700,
          ),
          filled: true,
          fillColor: colors.inputSurface,
          border: _liveOpsInputBorder(colors),
          enabledBorder: _liveOpsInputBorder(colors),
          focusedBorder: _liveOpsInputBorder(
            colors,
            borderColor: colors.accent,
            width: 1.4,
          ),
          contentPadding: _liveOpsInputContentPadding(),
        ),
      ),
    );
  }
}

class LiveOpsDropdownField extends StatelessWidget {
  const LiveOpsDropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    super.key,
  });

  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return Padding(
      padding: _liveOpsFieldPadding(),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        items: items
            .map(
              (item) => DropdownMenuItem<String>(
                value: item,
                child: Text(_formatOptionLabel(item)),
              ),
            )
            .toList(growable: false),
        onChanged: (next) {
          if (next != null) {
            onChanged(next);
          }
        },
        dropdownColor: colors.inputSurface,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colors.primaryText,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: theme.textTheme.bodySmall?.copyWith(
            color: colors.tertiaryText,
            fontWeight: FontWeight.w700,
          ),
          filled: true,
          fillColor: colors.inputSurface,
          border: _liveOpsInputBorder(colors),
          enabledBorder: _liveOpsInputBorder(colors),
          focusedBorder: _liveOpsInputBorder(
            colors,
            borderColor: colors.accent,
            width: 1.4,
          ),
          contentPadding: _liveOpsInputContentPadding(),
        ),
      ),
    );
  }
}

class LiveOpsDateButton extends StatelessWidget {
  const LiveOpsDateButton({
    required this.label,
    required this.value,
    required this.onTap,
    super.key,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return SizedBox(
      width: double.infinity,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          alignment: Alignment.centerLeft,
          minimumSize: const Size.fromHeight(CoolTapTargets.comfortable),
          padding: _liveOpsInputContentPadding(),
          backgroundColor: colors.inputSurface,
          foregroundColor: colors.primaryText,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.xs)),
            side: BorderSide(color: colors.border),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.tertiaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: CoolSpace.x1),
            Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.primaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LiveOpsMetricPill extends StatelessWidget {
  const LiveOpsMetricPill({
    required this.label,
    required this.value,
    required this.color,
    super.key,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;

    return Container(
      padding: _liveOpsMetricPadding(),
      decoration: BoxDecoration(
        color: colors.analyticsSurface,
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.sm)),
        boxShadow: CoolShadows.ambientFloat(strength: 0.15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.tertiaryText,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: CoolSpace.x1),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatOptionLabel(String value) {
  final parts = value.split('_').where((part) => part.isNotEmpty);
  return parts
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
