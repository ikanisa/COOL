part of '../screens/manage_app_config_screen.dart';

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
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          22,
          12,
          22,
          MediaQuery.of(context).viewInsets.bottom + 22,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.route == null
                    ? 'Add Partner Payment Route'
                    : 'Edit Partner Payment Route',
                style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Manage the live MoMo',
                style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.text3),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              _partnerField(),
              _marketField(),
              _field('Provider id', _providerCtl),
              _field('Merchant code', _recipientCodeCtl),
              _field('Reconciliation label', _reconciliationCtl),
              _statusField(),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _saving || _deleting ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CupertinoActivityIndicator(radius: 10),
                        )
                      : Text(
                          'Save route',
                          style: GoogleFonts.dmSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
                ),
              ),
              if (widget.route != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton(
                    onPressed: _saving || _deleting ? null : _delete,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.orange,
                      side: const BorderSide(color: AppColors.orange),
                    ),
                    child: _deleting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CupertinoActivityIndicator(radius: 9),
                          )
                        : Text(
                            'Delete route',
                            style: GoogleFonts.dmSans(
                              fontWeight: FontWeight.w600,
                            ),
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

  Widget _field(String label, TextEditingController ctl) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Semantics(
      textField: true,
      label: label,
      hint: 'Enter $label',
      child: TextField(
        controller: ctl,
        maxLines: 1,
        style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.text),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.dmSans(color: AppColors.text3),
          filled: true,
          fillColor: AppColors.surface2,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    ),
  );

  Widget _partnerField() => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Semantics(
      label: context.l10n.partnerSelector,
      hint: 'Choose partner',
      child: DropdownButtonFormField<String>(
        initialValue: _selectedPartnerId,
        dropdownColor: AppColors.surface2,
        decoration: InputDecoration(
          labelText: 'Partner',
          labelStyle: GoogleFonts.dmSans(color: AppColors.text3),
          filled: true,
          fillColor: AppColors.surface2,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
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
            : (value) {
                setState(() {
                  _selectedPartnerId = value;
                });
              },
      ),
    ),
  );

  Widget _marketField() => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      initialValue: 'Rwanda',
      enabled: false,
      style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.text),
      decoration: InputDecoration(
        labelText: 'Market',
        labelStyle: GoogleFonts.dmSans(color: AppColors.text3),
        filled: true,
        fillColor: AppColors.surface2.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    ),
  );

  Widget _statusField() => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Semantics(
      label: context.l10n.statusSelector,
      hint: 'Choose route status',
      child: DropdownButtonFormField<String>(
        initialValue: _status,
        dropdownColor: AppColors.surface2,
        decoration: InputDecoration(
          labelText: 'Status',
          labelStyle: GoogleFonts.dmSans(color: AppColors.text3),
          filled: true,
          fillColor: AppColors.surface2,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
        items: [
          const DropdownMenuItem<String>(value: 'draft', child: Text('Draft')),
          const DropdownMenuItem<String>(value: 'active', child: Text('Active')),
          const DropdownMenuItem<String>(value: 'inactive', child: Text('Inactive')),
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
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          22,
          12,
          22,
          MediaQuery.of(context).viewInsets.bottom + 22,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.config == null
                    ? 'Add Mobility Subscription Code'
                    : 'Edit Mobility Subscription Code',
                style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This code receives Rwanda',
                style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.text3),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              _field('MoMo code', _codeCtl),
              _marketField(),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CupertinoActivityIndicator(radius: 10),
                        )
                      : Text(
                          'Save code',
                          style: GoogleFonts.dmSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _field(String label, TextEditingController ctl) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Semantics(
      textField: true,
      label: label,
      hint: 'Enter $label',
      child: TextField(
        controller: ctl,
        maxLines: 1,
        style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.text),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.dmSans(color: AppColors.text3),
          filled: true,
          fillColor: AppColors.surface2,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    ),
  );

  Widget _marketField() => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      initialValue: AppMarket.country.name,
      enabled: false,
      style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.text),
      decoration: InputDecoration(
        labelText: 'Market',
        labelStyle: GoogleFonts.dmSans(color: AppColors.text3),
        filled: true,
        fillColor: AppColors.surface2.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
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
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          22,
          12,
          22,
          MediaQuery.of(context).viewInsets.bottom + 22,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.config != null ? 'Edit Config' : 'New Config Entry',
                style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 16),
              _field('Key', _keyCtl, enabled: widget.config == null),
              _field('Value', _valueCtl, maxLines: 4),
              _field('Description', _descCtl),
              _marketField(),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CupertinoActivityIndicator(radius: 10),
                        )
                      : Text(
                          'Save',
                          style: GoogleFonts.dmSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
                ),
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
    padding: const EdgeInsets.only(bottom: 10),
    child: Semantics(
      textField: true,
      label: label,
      enabled: enabled,
      hint: enabled ? 'Enter $label' : '$label is read only',
      child: TextField(
        controller: ctl,
        enabled: enabled,
        maxLines: maxLines,
        style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.text),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.dmSans(color: AppColors.text3),
          filled: true,
          fillColor: enabled
              ? AppColors.surface2
              : AppColors.surface2.withValues(alpha: 0.5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    ),
  );

  Widget _marketField() => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      initialValue: AppMarket.country.name,
      enabled: false,
      style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.text),
      decoration: InputDecoration(
        labelText: 'Market',
        labelStyle: GoogleFonts.dmSans(color: AppColors.text3),
        filled: true,
        fillColor: AppColors.surface2.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            22,
            12,
            22,
            MediaQuery.of(context).viewInsets.bottom + 22,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border2,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '${widget.rollout.label} rollout',
                  style: GoogleFonts.dmSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.rollout.description,
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: AppColors.text3,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<FeatureRolloutStage>(
                  initialValue: _stage,
                  dropdownColor: AppColors.surface2,
                  decoration: InputDecoration(
                    labelText: 'Rollout stage',
                    labelStyle: GoogleFonts.dmSans(color: AppColors.text3),
                    filled: true,
                    fillColor: AppColors.surface2,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
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
                  activeThumbColor: AppColors.accent,
                  activeTrackColor: AppColors.accent.withValues(alpha: 0.35),
                  title: Text(
                    'Kill switch',
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  subtitle: Text(
                    'Immediately blocks the feature',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: AppColors.text3,
                    ),
                  ),
                ),
                SwitchListTile.adaptive(
                  value: _adminOnly,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _adminOnly = value),
                  activeThumbColor: AppColors.accent,
                  activeTrackColor: AppColors.accent.withValues(alpha: 0.35),
                  title: Text(
                    'Admin only',
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  subtitle: Text(
                    'Requires admin access even',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: AppColors.text3,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Market: Rwanda only',
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'This app is restricted',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: AppColors.text3,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CupertinoActivityIndicator(radius: 10),
                          )
                        : Text(
                            'Save rollout',
                            style: GoogleFonts.dmSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.black,
                            ),
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