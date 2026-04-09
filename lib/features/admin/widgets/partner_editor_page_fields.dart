part of 'partner_editor_page.dart';

class _PartnerEditorSectionHeader extends StatelessWidget {
  const _PartnerEditorSectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Padding(
      padding: _partnerEditorFieldPadding(),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          color: colors.primaryText,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PartnerEditorTextField extends StatelessWidget {
  const _PartnerEditorTextField({
    required this.label,
    required this.controller,
    this.maxLines = 1,
    this.hint,
    this.keyboard,
    this.required_ = false,
  });

  final String label;
  final TextEditingController controller;
  final int maxLines;
  final String? hint;
  final TextInputType? keyboard;
  final bool required_;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Padding(
      padding: _partnerEditorFieldPadding(),
      child: Semantics(
        textField: true,
        label: label,
        child: TextFormField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboard,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.primaryText,
            fontWeight: FontWeight.w700,
          ),
          validator: required_
              ? (value) =>
                    (value == null || value.trim().isEmpty) ? 'Required' : null
              : null,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            labelStyle: theme.textTheme.labelMedium?.copyWith(
              color: colors.secondaryText,
              fontWeight: FontWeight.w700,
            ),
            hintStyle: theme.textTheme.bodySmall?.copyWith(
              color: colors.tertiaryText,
              fontWeight: FontWeight.w600,
            ),
            filled: true,
            fillColor: colors.inputSurface,
            border: _partnerEditorInputBorder(colors),
            enabledBorder: _partnerEditorInputBorder(colors),
            focusedBorder: _partnerEditorInputBorder(
              colors,
              borderColor: colors.accent,
            ),
            disabledBorder: _partnerEditorInputBorder(
              colors,
              borderColor: colors.border.withValues(alpha: 0.65),
            ),
            contentPadding: _partnerEditorInputPadding(),
          ),
        ),
      ),
    );
  }
}

class _PartnerEditorCategoryField extends StatelessWidget {
  const _PartnerEditorCategoryField({
    required this.category,
    required this.onChanged,
  });

  final String category;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Padding(
      padding: _partnerEditorFieldPadding(),
      child: DropdownButtonFormField<String>(
        initialValue: _categories.contains(category) ? category : null,
        onChanged: (value) {
          if (value != null) {
            onChanged(value);
          }
        },
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colors.primaryText,
          fontWeight: FontWeight.w700,
        ),
        dropdownColor: colors.cardSurfaceStrong,
        decoration: InputDecoration(
          labelText: 'Category *',
          labelStyle: theme.textTheme.labelMedium?.copyWith(
            color: colors.secondaryText,
            fontWeight: FontWeight.w700,
          ),
          filled: true,
          fillColor: colors.inputSurface,
          border: _partnerEditorInputBorder(colors),
          enabledBorder: _partnerEditorInputBorder(colors),
          focusedBorder: _partnerEditorInputBorder(
            colors,
            borderColor: colors.accent,
          ),
          contentPadding: _partnerEditorInputPadding(),
        ),
        items: _categories
            .map(
              (value) => DropdownMenuItem<String>(
                value: value,
                child: Text(
                  value[0].toUpperCase() + value.substring(1),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _PartnerEditorMarketField extends StatelessWidget {
  const _PartnerEditorMarketField();

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Padding(
      padding: _partnerEditorFieldPadding(),
      child: TextFormField(
        initialValue: AppMarket.country.name,
        enabled: false,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colors.primaryText,
          fontWeight: FontWeight.w700,
        ),
        decoration: InputDecoration(
          labelText: 'Market (auto)',
          labelStyle: theme.textTheme.labelMedium?.copyWith(
            color: colors.secondaryText,
            fontWeight: FontWeight.w700,
          ),
          filled: true,
          fillColor: colors.buttonSecondaryBackground,
          border: _partnerEditorInputBorder(colors),
          enabledBorder: _partnerEditorInputBorder(colors),
          disabledBorder: _partnerEditorInputBorder(
            colors,
            borderColor: colors.border.withValues(alpha: 0.65),
          ),
          contentPadding: _partnerEditorInputPadding(),
        ),
      ),
    );
  }
}

class _PartnerEditorSwitchTile extends StatelessWidget {
  const _PartnerEditorSwitchTile({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Semantics(
      label: label,
      toggled: value,
      child: SwitchListTile(
        title: Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.primaryText,
            fontWeight: FontWeight.w700,
          ),
        ),
        value: value,
        activeThumbColor: Theme.of(context).colorScheme.onPrimary,
        activeTrackColor: colors.accent,
        inactiveThumbColor: colors.secondaryText,
        inactiveTrackColor: colors.borderStrong,
        contentPadding: _partnerEditorZeroPadding(),
        onChanged: onChanged,
      ),
    );
  }
}

OutlineInputBorder _partnerEditorInputBorder(
  CoolSemanticColors colors, {
  Color? borderColor,
}) {
  return OutlineInputBorder(
    borderRadius: _partnerEditorInputRadius,
    borderSide: BorderSide(color: borderColor ?? colors.border, width: 1.2),
  );
}
