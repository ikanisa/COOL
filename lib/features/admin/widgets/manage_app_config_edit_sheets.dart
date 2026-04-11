part of '../screens/manage_app_config_screen.dart';

class EditConfigSheet extends StatefulWidget {
  const EditConfigSheet({
    this.config,
    required this.ref,
    required this.countries,
    super.key,
  });

  final Map<String, dynamic>? config;
  final WidgetRef ref;
  final List<CoolCountry> countries;

  @override
  State<EditConfigSheet> createState() => _EditConfigSheetState();
}

class _EditConfigSheetState extends State<EditConfigSheet> {
  late final TextEditingController _keyCtl;
  late final TextEditingController _valueCtl;
  late final TextEditingController _descCtl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final config = widget.config;
    _keyCtl = TextEditingController(text: config?['key']?.toString() ?? '');
    _valueCtl = TextEditingController(text: config?['value']?.toString() ?? '');
    _descCtl = TextEditingController(
      text: config?['description']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _keyCtl.dispose();
    _valueCtl.dispose();
    _descCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final key = _keyCtl.text.trim();
    if (widget.config == null &&
        AdminFeatureRolloutConfig.isManagedFeatureConfigKey(key)) {
      CoolToast.error(
        context,
        'Use the rollout governance cards for managed feature keys.',
      );
      return;
    }
    setState(() => _saving = true);
    final data = <String, dynamic>{
      'key': key,
      'value': _valueCtl.text.trim(),
      'description': _descCtl.text.trim(),
      'country': AppMarket.countryCode,
    };
    try {
      await widget.ref
          .read(adminContentRepositoryProvider)
          .upsertAppConfig(data);
      widget.ref.invalidate(adminAppConfigProvider);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        CoolToast.error(context, 'Error: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => _adminSheetFrame(
    context,
    child: ListView(
      padding: EdgeInsets.zero,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        _adminSheetHandle(context),
        const SizedBox(height: CoolSpace.x4),
        Text(
          widget.config != null ? 'Edit Config' : 'New Config Entry',
          style: _adminSheetTitleStyle(context),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: CoolSpace.x4),
        _field('Key', _keyCtl, enabled: widget.config == null),
        _field('Value', _valueCtl, maxLines: 4),
        _field('Description', _descCtl),
        _marketField(),
        const SizedBox(height: CoolSpace.x3),
        _adminSheetPrimaryButton(
          context,
          label: 'Save',
          isLoading: _saving,
          onPressed: _saving ? null : _save,
        ),
        const SizedBox(height: CoolSpace.x2),
      ],
    ),
  );

  Widget _field(
    String label,
    TextEditingController ctl, {
    bool enabled = true,
    int maxLines = 1,
  }) => Padding(
    padding: _adminFieldInsets(context),
    child: Semantics(
      textField: true,
      label: label,
      enabled: enabled,
      hint: enabled ? 'Enter $label' : '$label is read only',
      child: TextField(
        controller: ctl,
        enabled: enabled,
        maxLines: maxLines,
        style: _adminSheetFieldStyle(context),
        decoration: _adminSheetInputDecoration(
          context,
          label: label,
          enabled: enabled,
        ),
      ),
    ),
  );

  Widget _marketField() => Padding(
    padding: _adminFieldInsets(context),
    child: TextFormField(
      initialValue: AppMarket.country.name,
      enabled: false,
      style: _adminSheetFieldStyle(context),
      decoration: _adminSheetInputDecoration(
        context,
        label: 'Market',
        enabled: false,
      ),
    ),
  );
}

class EditRolloutSheet extends StatefulWidget {
  const EditRolloutSheet({
    required this.rollout,
    required this.ref,
    required this.countries,
    super.key,
  });

  final AdminFeatureRolloutConfig rollout;
  final WidgetRef ref;
  final List<CoolCountry> countries;

  @override
  State<EditRolloutSheet> createState() => _EditRolloutSheetState();
}

class _EditRolloutSheetState extends State<EditRolloutSheet> {
  late FeatureRolloutStage _stage;
  late bool _killSwitch;
  late bool _adminOnly;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _stage = widget.rollout.rollout.stage;
    _killSwitch = widget.rollout.rollout.killSwitch;
    _adminOnly = widget.rollout.rollout.adminOnly;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final updated = widget.rollout.copyWith(
      rollout: widget.rollout.rollout.copyWith(
        stage: _stage,
        killSwitch: _killSwitch,
        adminOnly: _adminOnly,
      ),
    );
    try {
      await widget.ref
          .read(adminContentRepositoryProvider)
          .upsertAppConfigs(updated.toAppConfigEntries());
      widget.ref.invalidate(adminAppConfigProvider);
      await widget.ref.read(featureFlagsStateProvider.notifier).refresh();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        CoolToast.error(context, 'Error: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return _adminSheetFrame(
      context,
      child: ListView(
        padding: EdgeInsets.zero,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          Center(child: _adminSheetHandle(context)),
          const SizedBox(height: CoolSpace.x4),
          Text(
            '${widget.rollout.label} rollout',
            style: _adminSheetTitleStyle(context),
          ),
          const SizedBox(height: CoolSpace.x1),
          Text(
            widget.rollout.description,
            style: _adminSheetMessageStyle(context),
          ),
          const SizedBox(height: CoolSpace.x4),
          DropdownButtonFormField<FeatureRolloutStage>(
            initialValue: _stage,
            style: _adminSheetFieldStyle(context),
            dropdownColor: colors.cardSurfaceStrong,
            decoration: _adminSheetInputDecoration(
              context,
              label: 'Rollout stage',
            ),
            items: FeatureRolloutStage.values
                .map(
                  (stage) => DropdownMenuItem<FeatureRolloutStage>(
                    value: stage,
                    child: Text(stage.remoteConfigValue),
                  ),
                )
                .toList(growable: false),
            onChanged: _saving
                ? null
                : (value) {
                    if (value != null) {
                      setState(() => _stage = value);
                    }
                  },
          ),
          const SizedBox(height: 10),
          SwitchListTile.adaptive(
            value: _killSwitch,
            onChanged: _saving
                ? null
                : (value) => setState(() => _killSwitch = value),
            activeThumbColor: theme.colorScheme.onPrimary,
            activeTrackColor: colors.accent,
            inactiveThumbColor: colors.secondaryText,
            inactiveTrackColor: colors.borderStrong,
            title: Text(
              'Kill switch',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.primaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              'Immediately blocks the feature for Rwanda users.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.secondaryText,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SwitchListTile.adaptive(
            value: _adminOnly,
            onChanged: _saving
                ? null
                : (value) => setState(() => _adminOnly = value),
            activeThumbColor: theme.colorScheme.onPrimary,
            activeTrackColor: colors.accent,
            inactiveThumbColor: colors.secondaryText,
            inactiveTrackColor: colors.borderStrong,
            title: Text(
              'Admin only',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.primaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              'Requires admin access even after the feature is enabled.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.secondaryText,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: CoolSpace.x3),
          Text(
            'Market: Rwanda only',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: CoolSpace.x1),
          Text(
            'This app is restricted to the Rwanda market in the current release.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.secondaryText,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 18),
          _adminSheetPrimaryButton(
            context,
            label: 'Save rollout',
            isLoading: _saving,
            onPressed: _saving ? null : _save,
          ),
          const SizedBox(height: CoolSpace.x2),
        ],
      ),
    );
  }
}
