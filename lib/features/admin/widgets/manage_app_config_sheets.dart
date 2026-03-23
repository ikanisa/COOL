part of '../screens/manage_app_config_screen.dart';

BoxDecoration _adminSheetDecoration(BuildContext context) {
  final colors = context.coolSemanticColors;
  return BoxDecoration(
    color: colors.cardSurfaceStrong,
    borderRadius: const BorderRadius.vertical(
      top: Radius.circular(CoolRadii.lg),
    ),
  );
}

Widget _adminSheetHandle(BuildContext context) {
  final colors = context.coolSemanticColors;
  return Container(
    width: 40,
    height: 4,
    decoration: BoxDecoration(
      color: colors.borderStrong,
      borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.pill)),
    ),
  );
}

OutlineInputBorder _adminSheetInputBorder(
  CoolSemanticColors colors, {
  Color? borderColor,
}) {
  return OutlineInputBorder(
    borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.xs)),
    borderSide: BorderSide(color: borderColor ?? colors.border, width: 1.1),
  );
}

EdgeInsets _adminSheetInsets(BuildContext context) {
  final space = context.coolSpace;
  return CoolSpace.pagePadding.copyWith(
    top: space.x3,
    bottom: MediaQuery.of(context).viewInsets.bottom + space.x6,
  );
}

EdgeInsets _adminFieldInsets(BuildContext context) {
  return CoolSpace.sectionPadding.copyWith(
    left: 0,
    right: 0,
    top: 0,
    bottom: context.coolSpace.x3,
  );
}

InputDecoration _adminSheetInputDecoration(
  BuildContext context, {
  required String label,
  bool enabled = true,
}) {
  final colors = context.coolSemanticColors;
  final theme = Theme.of(context);
  return InputDecoration(
    labelText: label,
    labelStyle: theme.textTheme.labelMedium?.copyWith(
      color: colors.secondaryText,
      fontWeight: FontWeight.w700,
    ),
    filled: true,
    fillColor: enabled ? colors.inputSurface : colors.buttonSecondaryBackground,
    border: _adminSheetInputBorder(colors),
    enabledBorder: _adminSheetInputBorder(colors),
    focusedBorder: _adminSheetInputBorder(colors, borderColor: colors.accent),
    disabledBorder: _adminSheetInputBorder(
      colors,
      borderColor: colors.border.withValues(alpha: 0.65),
    ),
  );
}

TextStyle? _adminSheetFieldStyle(BuildContext context) {
  final colors = context.coolSemanticColors;
  return Theme.of(context).textTheme.bodyMedium?.copyWith(
    color: colors.primaryText,
    fontWeight: FontWeight.w700,
  );
}

TextStyle? _adminSheetTitleStyle(BuildContext context) {
  final colors = context.coolSemanticColors;
  return Theme.of(context).textTheme.titleLarge?.copyWith(
    color: colors.primaryText,
    fontWeight: FontWeight.w800,
  );
}

TextStyle? _adminSheetMessageStyle(BuildContext context) {
  final colors = context.coolSemanticColors;
  return Theme.of(context).textTheme.bodySmall?.copyWith(
    color: colors.secondaryText,
    fontWeight: FontWeight.w600,
    height: 1.45,
  );
}

ButtonStyle _adminSheetOutlineStyle(
  BuildContext context, {
  required Color foregroundColor,
  required Color borderColor,
}) {
  return OutlinedButton.styleFrom(
    foregroundColor: foregroundColor,
    side: BorderSide(color: borderColor),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(CoolRadii.xs)),
    ),
  );
}

Widget _adminSheetPrimaryButton(
  BuildContext context, {
  required String label,
  required bool isLoading,
  required VoidCallback? onPressed,
}) {
  final colors = context.coolSemanticColors;
  final theme = Theme.of(context);
  return SizedBox(
    width: double.infinity,
    height: 48,
    child: ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: colors.accent,
        foregroundColor: theme.colorScheme.onPrimary,
        disabledBackgroundColor: colors.buttonSecondaryBackground,
        disabledForegroundColor: colors.tertiaryText,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(CoolRadii.xs)),
        ),
      ),
      child: isLoading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CupertinoActivityIndicator(radius: 10),
            )
          : Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onPrimary,
              ),
            ),
    ),
  );
}

class EditPartnerPaymentRouteSheet extends StatefulWidget {
  const EditPartnerPaymentRouteSheet({
    this.route,
    required this.ref,
    required this.countries,
    required this.partners,
    super.key,
  });

  final Map<String, dynamic>? route;
  final WidgetRef ref;
  final List<CoolCountry> countries;
  final List<Map<String, dynamic>> partners;

  @override
  State<EditPartnerPaymentRouteSheet> createState() =>
      _EditPartnerPaymentRouteSheetState();
}

class _EditPartnerPaymentRouteSheetState
    extends State<EditPartnerPaymentRouteSheet> {
  late final TextEditingController _providerCtl;
  late final TextEditingController _recipientCodeCtl;
  late final TextEditingController _reconciliationCtl;
  String? _selectedPartnerId;
  String _status = 'draft';
  bool _saving = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    final route = widget.route;
    _providerCtl = TextEditingController(
      text: route?['provider']?.toString() ?? '',
    );
    _recipientCodeCtl = TextEditingController(
      text: route?['recipient_code']?.toString() ?? '',
    );
    _reconciliationCtl = TextEditingController(
      text: route?['reconciliation_label']?.toString() ?? '',
    );
    _selectedPartnerId = route?['partner_id']?.toString();
    _status = route?['status']?.toString().toLowerCase() ?? 'draft';
  }

  @override
  void dispose() {
    _providerCtl.dispose();
    _recipientCodeCtl.dispose();
    _reconciliationCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final partnerId = _selectedPartnerId?.trim();
    final provider = _providerCtl.text.trim().toLowerCase();
    final recipientCode = _recipientCodeCtl.text.trim();
    final reconciliationLabel = _reconciliationCtl.text.trim();
    if (partnerId == null || partnerId.isEmpty) {
      CoolToast.error(context, 'Select a partner.');
      return;
    }
    if (provider.isEmpty) {
      CoolToast.error(context, 'Enter a provider id such as mtn_rwanda.');
      return;
    }
    if (reconciliationLabel.isEmpty) {
      CoolToast.error(context, 'Enter a reconciliation label.');
      return;
    }

    final country = AppMarket.country;
    if (!country.supportsMomoCode) {
      CoolToast.error(
        context,
        '${country.name} is not configured for merchant-code payments.',
      );
      return;
    }
    if (_status == 'active' && recipientCode.isEmpty) {
      CoolToast.error(context, 'Active routes require a merchant code.');
      return;
    }
    if (recipientCode.isNotEmpty &&
        !country.isValidMerchantCode(recipientCode)) {
      CoolToast.error(
        context,
        'Merchant code is invalid for ${country.name}. Example: ${country.momoCodeExample ?? 'configured code'}',
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.ref
          .read(adminRepositoryProvider)
          .upsertPartnerPaymentRoute(<String, dynamic>{
            'id': widget.route?['id'],
            'partner_id': partnerId,
            'country': AppMarket.countryCode,
            'provider': provider,
            'recipient_code': recipientCode,
            'reconciliation_label': reconciliationLabel,
            'status': _status,
          });
      widget.ref.invalidate(adminPartnerPaymentRoutesProvider);
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

  Future<void> _delete() async {
    final routeId = widget.route?['id']?.toString();
    if (routeId == null || routeId.isEmpty) {
      return;
    }
    setState(() => _deleting = true);
    try {
      await widget.ref
          .read(adminRepositoryProvider)
          .deletePartnerPaymentRoute(routeId);
      widget.ref.invalidate(adminPartnerPaymentRoutesProvider);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        CoolToast.error(context, 'Error: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _deleting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return DecoratedBox(
      decoration: _adminSheetDecoration(context),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: _adminSheetInsets(context),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _adminSheetHandle(context),
                const SizedBox(height: CoolSpace.x4),
                Text(
                  widget.route == null
                      ? 'Add Partner Payment Route'
                      : 'Edit Partner Payment Route',
                  style: _adminSheetTitleStyle(context),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: CoolSpace.x2),
                Text(
                  'Manage Rwanda partner checkout routing.',
                  style: _adminSheetMessageStyle(context),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: CoolSpace.x4),
                _partnerField(),
                _marketField(),
                _field('Provider id', _providerCtl),
                _field('Merchant code', _recipientCodeCtl),
                _field('Reconciliation label', _reconciliationCtl),
                _statusField(),
                const SizedBox(height: CoolSpace.x3),
                _adminSheetPrimaryButton(
                  context,
                  label: 'Save route',
                  isLoading: _saving,
                  onPressed: _saving || _deleting ? null : _save,
                ),
                if (widget.route != null) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton(
                      onPressed: _saving || _deleting ? null : _delete,
                      style: _adminSheetOutlineStyle(
                        context,
                        foregroundColor: colors.danger,
                        borderColor: colors.danger,
                      ),
                      child: _deleting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CupertinoActivityIndicator(radius: 9),
                            )
                          : Text(
                              'Delete route',
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctl) => Padding(
    padding: _adminFieldInsets(context),
    child: Semantics(
      textField: true,
      label: label,
      hint: 'Enter $label',
      child: TextField(
        controller: ctl,
        maxLines: 1,
        style: _adminSheetFieldStyle(context),
        decoration: _adminSheetInputDecoration(context, label: label),
      ),
    ),
  );

  Widget _partnerField() => Padding(
    padding: _adminFieldInsets(context),
    child: Semantics(
      label: context.l10n.partnerSelector,
      hint: 'Choose partner',
      child: DropdownButtonFormField<String>(
        initialValue: _selectedPartnerId,
        style: _adminSheetFieldStyle(context),
        dropdownColor: context.coolSemanticColors.cardSurfaceStrong,
        decoration: _adminSheetInputDecoration(context, label: 'Partner'),
        items: widget.partners
            .map(
              (partner) => DropdownMenuItem<String>(
                value: partner['id']?.toString() ?? '',
                child: Text(partner['name']?.toString() ?? 'Partner'),
              ),
            )
            .toList(growable: false),
        onChanged: _saving || _deleting
            ? null
            : (value) => setState(() => _selectedPartnerId = value),
      ),
    ),
  );

  Widget _marketField() => Padding(
    padding: _adminFieldInsets(context),
    child: TextFormField(
      initialValue: 'Rwanda',
      enabled: false,
      style: _adminSheetFieldStyle(context),
      decoration: _adminSheetInputDecoration(
        context,
        label: 'Market',
        enabled: false,
      ),
    ),
  );

  Widget _statusField() => Padding(
    padding: _adminFieldInsets(context),
    child: Semantics(
      label: context.l10n.statusSelector,
      hint: 'Choose route status',
      child: DropdownButtonFormField<String>(
        initialValue: _status,
        style: _adminSheetFieldStyle(context),
        dropdownColor: context.coolSemanticColors.cardSurfaceStrong,
        decoration: _adminSheetInputDecoration(context, label: 'Status'),
        items: const [
          DropdownMenuItem<String>(value: 'draft', child: Text('Draft')),
          DropdownMenuItem<String>(value: 'active', child: Text('Active')),
          DropdownMenuItem<String>(value: 'inactive', child: Text('Inactive')),
        ],
        onChanged: _saving || _deleting
            ? null
            : (value) => setState(() => _status = value ?? 'draft'),
      ),
    ),
  );
}

class EditMobilitySubscriptionCodeSheet extends StatefulWidget {
  const EditMobilitySubscriptionCodeSheet({
    this.config,
    required this.ref,
    required this.countries,
    super.key,
  });

  final Map<String, dynamic>? config;
  final WidgetRef ref;
  final List<CoolCountry> countries;

  @override
  State<EditMobilitySubscriptionCodeSheet> createState() =>
      _EditMobilitySubscriptionCodeSheetState();
}

class _EditMobilitySubscriptionCodeSheetState
    extends State<EditMobilitySubscriptionCodeSheet> {
  late final TextEditingController _codeCtl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _codeCtl = TextEditingController(
      text: widget.config?['value']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _codeCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final code = _codeCtl.text.trim();
    if (code.isEmpty) {
      CoolToast.error(context, 'Enter the mobility subscription MoMo code.');
      return;
    }

    setState(() => _saving = true);
    final data = <String, dynamic>{
      'key': AppConfigKeys.mobilitySubscriptionMomoCode,
      'value': code,
      'description':
          'MoMo code used to receive mobility subscription payments.',
      'country': AppMarket.countryCode,
    };

    try {
      await widget.ref.read(adminRepositoryProvider).upsertAppConfig(data);
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
  Widget build(BuildContext context) => DecoratedBox(
    decoration: _adminSheetDecoration(context),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: _adminSheetInsets(context),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _adminSheetHandle(context),
              const SizedBox(height: CoolSpace.x4),
              Text(
                widget.config == null
                    ? 'Add Mobility Subscription Code'
                    : 'Edit Mobility Subscription Code',
                style: _adminSheetTitleStyle(context),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: CoolSpace.x2),
              Text(
                'This code receives Rwanda mobility subscription payments.',
                style: _adminSheetMessageStyle(context),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: CoolSpace.x4),
              _field('MoMo code', _codeCtl),
              _marketField(),
              const SizedBox(height: CoolSpace.x3),
              _adminSheetPrimaryButton(
                context,
                label: 'Save code',
                isLoading: _saving,
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _field(String label, TextEditingController ctl) => Padding(
    padding: _adminFieldInsets(context),
    child: Semantics(
      textField: true,
      label: label,
      hint: 'Enter $label',
      child: TextField(
        controller: ctl,
        maxLines: 1,
        style: _adminSheetFieldStyle(context),
        decoration: _adminSheetInputDecoration(context, label: label),
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
    if (key == AppConfigKeys.mobilitySubscriptionMomoCode) {
      CoolToast.error(
        context,
        'Use the mobility subscription card for this MoMo code.',
      );
      return;
    }
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
      await widget.ref.read(adminRepositoryProvider).upsertAppConfig(data);
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
  Widget build(BuildContext context) => DecoratedBox(
    decoration: _adminSheetDecoration(context),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: _adminSheetInsets(context),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
            ],
          ),
        ),
      ),
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
          .read(adminRepositoryProvider)
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
    return DecoratedBox(
      decoration: _adminSheetDecoration(context),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: _adminSheetInsets(context),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
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
                      fontWeight: FontWeight.w600,
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
                      fontWeight: FontWeight.w600,
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
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 18),
                _adminSheetPrimaryButton(
                  context,
                  label: 'Save rollout',
                  isLoading: _saving,
                  onPressed: _saving ? null : _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
