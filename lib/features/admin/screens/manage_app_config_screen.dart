import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/config/app_config_repository.dart';
import '../../../core/config/country_catalog.dart';
import '../../../core/models/engagement_feature_flags.dart';
import '../../../core/providers/engagement_providers.dart';
import '../../../core/providers/supported_countries_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../models/admin_feature_rollout.dart';
import '../providers/admin_providers.dart';

/// Admin screen for managing key-value app configuration.
class ManageAppConfigScreen extends ConsumerWidget {
  const ManageAppConfigScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(adminAppConfigProvider);
    final countries =
        ref.watch(supportedCountriesProvider).valueOrNull ??
        CoolCountryCatalog.all;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text(
          'App Config',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.text),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.accent,
        onPressed: () => _showEditSheet(context, ref, null, countries),
        child: const Icon(Icons.add_rounded, color: Colors.black),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: CoolAsyncView<List<Map<String, dynamic>>>(
          value: configAsync,
          onRetry: () => ref.invalidate(adminAppConfigProvider),
          emptyCheck: (_) => false,
          builder: (configs) {
            final rollouts = AdminFeatureRolloutConfig.fromAppConfigEntries(
              configs,
            );
            final mobilitySubscriptionConfigs =
                configs
                    .where(
                      (entry) =>
                          entry['key'] ==
                          AppConfigKeys.mobilitySubscriptionMomoCode,
                    )
                    .toList()
                  ..sort((left, right) {
                    final leftCountry =
                        left['country']?.toString().trim().toUpperCase() ?? '';
                    final rightCountry =
                        right['country']?.toString().trim().toUpperCase() ?? '';
                    if (leftCountry.isEmpty != rightCountry.isEmpty) {
                      return leftCountry.isEmpty ? -1 : 1;
                    }
                    return leftCountry.compareTo(rightCountry);
                  });
            final genericConfigs =
                configs.where((entry) {
                  final key = entry['key']?.toString();
                  final country = entry['country']?.toString().trim();
                  if (key == null || key.isEmpty) {
                    return false;
                  }
                  if (key == AppConfigKeys.mobilitySubscriptionMomoCode) {
                    return false;
                  }
                  if (!AdminFeatureRolloutConfig.isManagedFeatureConfigKey(
                    key,
                  )) {
                    return true;
                  }
                  return country != null && country.isNotEmpty;
                }).toList()..sort((left, right) {
                  final leftKey = left['key']?.toString() ?? '';
                  final rightKey = right['key']?.toString() ?? '';
                  return leftKey.compareTo(rightKey);
                });

            return ListView(
              children: [
                _SectionHeader(
                  title: 'Rollout Governance',
                  subtitle:
                      'Manage kill switches, rollout stage, market allow-lists, and operator-only access for the app shell.',
                ),
                const SizedBox(height: 12),
                ...rollouts.map(
                  (rollout) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _RolloutCard(
                      rollout: rollout,
                      onEdit: () =>
                          _showRolloutSheet(context, ref, rollout, countries),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _SectionHeader(
                  title: 'Mobility Subscription Recipient',
                  subtitle:
                      'Set the MoMo code that receives mobility subscription payments. Add a global default or country override here instead of using build flags.',
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => _showMobilitySubscriptionSheet(
                      context,
                      ref,
                      null,
                      countries,
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.text,
                      side: BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(
                      'Add code',
                      style: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (mobilitySubscriptionConfigs.isEmpty)
                  const _EmptyConfigCard(
                    message:
                        'No mobility subscription MoMo code is configured yet. Add one before drivers can pay subscriptions.',
                  )
                else
                  ...mobilitySubscriptionConfigs.map(
                    (config) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _MobilitySubscriptionConfigTile(
                        config: config,
                        countries: countries,
                        onEdit: () => _showMobilitySubscriptionSheet(
                          context,
                          ref,
                          config,
                          countries,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                _SectionHeader(
                  title: 'Additional Config',
                  subtitle:
                      'Use the generic config editor for non-rollout keys and country-scoped operational settings.',
                ),
                const SizedBox(height: 12),
                if (genericConfigs.isEmpty)
                  const _EmptyConfigCard(
                    message:
                        'No non-rollout config entries yet. Use the add button to create one.',
                  )
                else
                  ...genericConfigs.map(
                    (config) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ConfigTile(
                        config: config,
                        onEdit: () =>
                            _showEditSheet(context, ref, config, countries),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showEditSheet(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic>? config,
    List<CoolCountry> countries,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) =>
          _EditConfigSheet(config: config, ref: ref, countries: countries),
    );
  }

  void _showRolloutSheet(
    BuildContext context,
    WidgetRef ref,
    AdminFeatureRolloutConfig rollout,
    List<CoolCountry> countries,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) =>
          _EditRolloutSheet(rollout: rollout, ref: ref, countries: countries),
    );
  }

  void _showMobilitySubscriptionSheet(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic>? config,
    List<CoolCountry> countries,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _EditMobilitySubscriptionCodeSheet(
        config: config,
        ref: ref,
        countries: countries,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.dmSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.text3),
        ),
      ],
    );
  }
}

class _EmptyConfigCard extends StatelessWidget {
  const _EmptyConfigCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        message,
        style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.text3),
      ),
    );
  }
}

class _ConfigTile extends StatelessWidget {
  const _ConfigTile({required this.config, required this.onEdit});

  final Map<String, dynamic> config;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final value = config['value']?.toString() ?? '';
    final preview = value.length > 60 ? '${value.substring(0, 60)}…' : value;
    final country = config['country']?.toString();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        title: Text(
          config['key']?.toString() ?? '',
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        subtitle: Text(
          '$preview\n${config['description'] ?? ''} ${country != null && country.isNotEmpty ? '($country)' : '(global)'}',
          style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.text3),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: GestureDetector(
          onTap: onEdit,
          child: const Icon(
            Icons.edit_rounded,
            size: 18,
            color: AppColors.text3,
          ),
        ),
      ),
    );
  }
}

class _RolloutCard extends StatelessWidget {
  const _RolloutCard({required this.rollout, required this.onEdit});

  final AdminFeatureRolloutConfig rollout;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final allowedCountries = rollout.rollout.allowedCountries;
    final stageLabel = rollout.rollout.stage.remoteConfigValue.toUpperCase();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rollout.label,
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      rollout.description,
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: AppColors.text3,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onEdit,
                icon: const Icon(Icons.tune_rounded, color: AppColors.text),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusPill(
                label: rollout.rollout.killSwitch ? 'Killed' : stageLabel,
                tone: rollout.rollout.killSwitch
                    ? const Color(0xFFFFD1D1)
                    : const Color(0xFFD9F5D6),
                foreground: rollout.rollout.killSwitch
                    ? const Color(0xFF7A1616)
                    : const Color(0xFF0F5132),
              ),
              _StatusPill(
                label: rollout.rollout.adminOnly
                    ? 'Admin only'
                    : 'User-accessible',
                tone: rollout.rollout.adminOnly
                    ? const Color(0xFFFFF2C9)
                    : const Color(0xFFDCE8FF),
                foreground: rollout.rollout.adminOnly
                    ? const Color(0xFF725400)
                    : const Color(0xFF173A7A),
              ),
              _StatusPill(
                label: allowedCountries.isEmpty
                    ? 'All countries'
                    : '${allowedCountries.length} countries',
                tone: const Color(0xFFE8E3FF),
                foreground: const Color(0xFF3D2F7A),
              ),
            ],
          ),
          if (allowedCountries.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              allowedCountries.join(', '),
              style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.text3),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.tone,
    required this.foreground,
  });

  final String label;
  final Color tone;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tone,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}

class _MobilitySubscriptionConfigTile extends StatelessWidget {
  const _MobilitySubscriptionConfigTile({
    required this.config,
    required this.countries,
    required this.onEdit,
  });

  final Map<String, dynamic> config;
  final List<CoolCountry> countries;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final countryCode = config['country']?.toString();
    final scopeLabel = countryCode == null || countryCode.trim().isEmpty
        ? 'Global default'
        : CoolCountryCatalog.byIsoCode(
                countryCode,
                source: countries,
              )?.pickerLabel ??
              countryCode.toUpperCase();
    final code = config['value']?.toString() ?? '';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        title: Text(
          scopeLabel,
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        subtitle: Text(
          'MoMo code: $code',
          style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.text3),
        ),
        trailing: GestureDetector(
          onTap: onEdit,
          child: const Icon(
            Icons.edit_rounded,
            size: 18,
            color: AppColors.text3,
          ),
        ),
      ),
    );
  }
}

class _EditMobilitySubscriptionCodeSheet extends StatefulWidget {
  const _EditMobilitySubscriptionCodeSheet({
    this.config,
    required this.ref,
    required this.countries,
  });

  final Map<String, dynamic>? config;
  final WidgetRef ref;
  final List<CoolCountry> countries;

  @override
  State<_EditMobilitySubscriptionCodeSheet> createState() =>
      _EditMobilitySubscriptionCodeSheetState();
}

class _EditMobilitySubscriptionCodeSheetState
    extends State<_EditMobilitySubscriptionCodeSheet> {
  late final TextEditingController _codeCtl;
  String? _selectedCountryCode;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _codeCtl = TextEditingController(
      text: widget.config?['value']?.toString() ?? '',
    );
    _selectedCountryCode = CoolCountryCatalog.byIsoCode(
      widget.config?['country']?.toString(),
      source: widget.countries,
    )?.isoCode;
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
      'country': _selectedCountryCode,
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
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                'This code receives mobility subscription payments. Save a global default or a country override.',
                style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.text3),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              _field('MoMo code', _codeCtl),
              _countryField(),
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
                          child: CircularProgressIndicator(strokeWidth: 2),
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
  );

  Widget _countryField() => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: DropdownButtonFormField<String?>(
      initialValue: _selectedCountryCode,
      dropdownColor: AppColors.surface2,
      decoration: InputDecoration(
        labelText: 'Country scope',
        labelStyle: GoogleFonts.dmSans(color: AppColors.text3),
        filled: true,
        fillColor: AppColors.surface2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('Global')),
        ...widget.countries.map(
          (country) => DropdownMenuItem<String?>(
            value: country.isoCode,
            child: Text(country.pickerLabel),
          ),
        ),
      ],
      onChanged: _saving
          ? null
          : (value) => setState(() => _selectedCountryCode = value),
    ),
  );
}

class _EditConfigSheet extends StatefulWidget {
  const _EditConfigSheet({
    this.config,
    required this.ref,
    required this.countries,
  });
  final Map<String, dynamic>? config;
  final WidgetRef ref;
  final List<CoolCountry> countries;
  @override
  State<_EditConfigSheet> createState() => _EditConfigSheetState();
}

class _EditConfigSheetState extends State<_EditConfigSheet> {
  late final TextEditingController _keyCtl, _valueCtl, _descCtl;
  String? _selectedCountryCode;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.config;
    _keyCtl = TextEditingController(text: c?['key']?.toString() ?? '');
    _valueCtl = TextEditingController(text: c?['value']?.toString() ?? '');
    _descCtl = TextEditingController(text: c?['description']?.toString() ?? '');
    _selectedCountryCode = CoolCountryCatalog.byIsoCode(
      c?['country']?.toString(),
      source: widget.countries,
    )?.isoCode;
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
      'country': _selectedCountryCode,
    };
    try {
      await widget.ref.read(adminRepositoryProvider).upsertAppConfig(data);
      widget.ref.invalidate(adminAppConfigProvider);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        CoolToast.error(context, 'Error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
              _countryField(),
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
                          child: CircularProgressIndicator(strokeWidth: 2),
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
  );

  Widget _countryField() => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: DropdownButtonFormField<String?>(
      initialValue: _selectedCountryCode,
      dropdownColor: AppColors.surface2,
      decoration: InputDecoration(
        labelText: 'Country scope',
        labelStyle: GoogleFonts.dmSans(color: AppColors.text3),
        filled: true,
        fillColor: AppColors.surface2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('Global')),
        ...widget.countries.map(
          (country) => DropdownMenuItem<String?>(
            value: country.isoCode,
            child: Text(country.pickerLabel),
          ),
        ),
      ],
      onChanged: _saving
          ? null
          : (value) => setState(() => _selectedCountryCode = value),
    ),
  );
}

class _EditRolloutSheet extends StatefulWidget {
  const _EditRolloutSheet({
    required this.rollout,
    required this.ref,
    required this.countries,
  });

  final AdminFeatureRolloutConfig rollout;
  final WidgetRef ref;
  final List<CoolCountry> countries;

  @override
  State<_EditRolloutSheet> createState() => _EditRolloutSheetState();
}

class _EditRolloutSheetState extends State<_EditRolloutSheet> {
  late FeatureRolloutStage _stage;
  late bool _killSwitch;
  late bool _adminOnly;
  late Set<String> _selectedCountries;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _stage = widget.rollout.rollout.stage;
    _killSwitch = widget.rollout.rollout.killSwitch;
    _adminOnly = widget.rollout.rollout.adminOnly;
    _selectedCountries = widget.rollout.rollout.allowedCountries.toSet();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final updated = widget.rollout.copyWith(
      rollout: widget.rollout.rollout.copyWith(
        stage: _stage,
        killSwitch: _killSwitch,
        adminOnly: _adminOnly,
        allowedCountries: (_selectedCountries.toList()..sort()),
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
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                    'Immediately blocks the feature regardless of stage or country allow-list.',
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
                    'Requires admin access even when the stage would otherwise allow users in.',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: AppColors.text3,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Allowed countries',
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Leave empty to allow every supported market. Country scoping happens here, not via country-scoped config rows.',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: AppColors.text3,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.countries
                      .map((country) {
                        final selected = _selectedCountries.contains(
                          country.isoCode,
                        );
                        return FilterChip(
                          label: Text(country.isoCode),
                          selected: selected,
                          onSelected: _saving
                              ? null
                              : (value) {
                                  setState(() {
                                    if (value) {
                                      _selectedCountries.add(country.isoCode);
                                    } else {
                                      _selectedCountries.remove(
                                        country.isoCode,
                                      );
                                    }
                                  });
                                },
                          backgroundColor: AppColors.surface2,
                          selectedColor: AppColors.accent.withValues(
                            alpha: 0.2,
                          ),
                          labelStyle: GoogleFonts.dmSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          ),
                          side: BorderSide(color: AppColors.border),
                        );
                      })
                      .toList(growable: false),
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
                            child: CircularProgressIndicator(strokeWidth: 2),
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
