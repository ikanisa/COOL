part of 'group_profile_screen.dart';

class _GroupProfileEditSection extends StatelessWidget {
  const _GroupProfileEditSection({
    required this.children,
    this.title,
    this.errorMessage,
  });

  final String? title;
  final String? errorMessage;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return CollectCard(
      emphasis: CollectCardEmphasis.flat,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            CollectSpacing.gap12,
          ],
          for (var index = 0; index < children.length; index += 1) ...[
            children[index],
            if (index != children.length - 1) CollectSpacing.gap16,
          ],
          if (errorMessage != null) ...[
            CollectSpacing.gap12,
            InfoSecurityBanner(
              title: 'Profile not saved',
              message: errorMessage!,
              tone: CollectStatusTone.danger,
            ),
          ],
        ],
      ),
    );
  }
}

class _RecurringCadenceControl extends StatelessWidget {
  const _RecurringCadenceControl({
    required this.enabled,
    required this.selected,
    required this.onEnabledChanged,
    required this.onCadenceChanged,
  });

  final bool enabled;
  final String selected;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<String> onCadenceChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: context.collectColors.transparent,
          child: SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Recurring contribution'),
            value: enabled,
            onChanged: onEnabledChanged,
          ),
        ),
        if (enabled) ...[
          CollectSpacing.gap8,
          _CadencePicker(selected: selected, onChanged: onCadenceChanged),
        ],
      ],
    );
  }
}

class _CadencePicker extends StatelessWidget {
  const _CadencePicker({required this.selected, required this.onChanged});

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recurring contribution',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        CollectSpacing.gap8,
        Wrap(
          spacing: CollectSpacing.x2,
          runSpacing: CollectSpacing.x2,
          children:
              const [
                    _CadenceOption(value: 'daily', label: 'Daily'),
                    _CadenceOption(value: 'weekly', label: 'Weekly'),
                    _CadenceOption(value: 'monthly', label: 'Monthly'),
                  ]
                  .map(
                    (option) => ChoiceChip(
                      label: Text(option.label),
                      selected: selected == option.value,
                      onSelected: (_) => onChanged(option.value),
                    ),
                  )
                  .toList(),
        ),
      ],
    );
  }
}

class _ProfileCollectionTypePicker extends StatelessWidget {
  const _ProfileCollectionTypePicker({
    required this.selected,
    required this.onChanged,
  });

  final CollectionType selected;
  final ValueChanged<CollectionType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Collection type', style: Theme.of(context).textTheme.labelLarge),
        CollectSpacing.gap8,
        Wrap(
          spacing: CollectSpacing.x2,
          runSpacing: CollectSpacing.x2,
          children: [
            for (final type in CollectionType.values)
              ChoiceChip(
                avatar: Icon(collectionTypeIcon(type), size: 18),
                label: Text(type.label),
                selected: selected == type,
                onSelected: (_) => onChanged(type),
              ),
          ],
        ),
      ],
    );
  }
}

class _ProfileColorPalette extends StatelessWidget {
  const _ProfileColorPalette({
    required this.selectedHex,
    required this.onChanged,
  });

  final String selectedHex;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Group color', style: Theme.of(context).textTheme.labelLarge),
        CollectSpacing.gap8,
        Wrap(
          spacing: CollectSpacing.x2,
          runSpacing: CollectSpacing.x2,
          children: [
            for (final option in CollectColors.brandPrimaryOptions)
              Builder(
                builder: (context) {
                  final selected = selectedHex == option.hex;
                  final selectedForeground =
                      option.color.computeLuminance() > 0.72
                      ? colors.textPrimary
                      : colors.onAccent;
                  return Semantics(
                    button: true,
                    selected: selected,
                    label: 'Group color',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => onChanged(option.hex),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: option.color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected
                                ? selectedForeground
                                : colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: SizedBox(
                          width: 42,
                          height: 42,
                          child: selected
                              ? Icon(
                                  Icons.check_rounded,
                                  color: selectedForeground,
                                )
                              : null,
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }
}

String _defaultProfileCategorySubtype(CollectionType type) {
  return switch (type) {
    CollectionType.ikimina => 'group_savings',
    CollectionType.sport => 'fan_club',
    CollectionType.church => 'offering',
    CollectionType.wedding => 'committee',
    CollectionType.other => 'custom',
  };
}

class _CadenceOption {
  const _CadenceOption({required this.value, required this.label});

  final String value;
  final String label;
}
