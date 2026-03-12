import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/config/country_catalog.dart';
import '../../../core/providers/supported_countries_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../providers/admin_providers.dart';

/// Admin screen for managing partners.
class ManagePartnersScreen extends ConsumerWidget {
  const ManagePartnersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partnersAsync = ref.watch(adminPartnersProvider);
    final countries =
        ref.watch(supportedCountriesProvider).valueOrNull ??
        CoolCountryCatalog.all;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text(
          'Manage Partners',
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
          value: partnersAsync,
          onRetry: () => ref.invalidate(adminPartnersProvider),
          emptyCheck: (p) => p.isEmpty,
          emptyMessage: 'No partners yet',
          builder: (partners) => ListView.separated(
            itemCount: partners.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final p = partners[index];
              return _PartnerTile(
                partner: p,
                onEdit: () => _showEditSheet(context, ref, p, countries),
              );
            },
          ),
        ),
      ),
    );
  }

  void _showEditSheet(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic>? partner,
    List<CoolCountry> countries,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) =>
          _EditPartnerSheet(partner: partner, ref: ref, countries: countries),
    );
  }
}

class _PartnerTile extends StatelessWidget {
  const _PartnerTile({required this.partner, required this.onEdit});
  final Map<String, dynamic> partner;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final isActive = partner['is_active'] == true;
    final isMock = partner['is_mock'] == true;
    final mockBatch = partner['mock_batch']?.toString().trim() ?? '';
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        leading: Text(
          partner['emoji']?.toString() ?? '🤝',
          style: const TextStyle(fontSize: 24),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                partner['name']?.toString() ?? '',
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ),
            if (isMock) const SizedBox(width: 8),
            if (isMock)
              const _AdminMarkerChip(label: 'Mock', color: Colors.orange),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${partner['slug']} · ${partner['category']} · ${partner['country'] ?? 'all'}',
              style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.text3),
            ),
            if (isMock && mockBatch.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Batch: $mockBatch',
                style: GoogleFonts.dmSans(fontSize: 11, color: Colors.orange),
              ),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AdminMarkerChip(
              label: isActive ? 'Active' : 'Off',
              color: isActive ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onEdit,
              child: const Icon(
                Icons.edit_rounded,
                size: 18,
                color: AppColors.text3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminMarkerChip extends StatelessWidget {
  const _AdminMarkerChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color)),
    );
  }
}

class _EditPartnerSheet extends StatefulWidget {
  const _EditPartnerSheet({
    this.partner,
    required this.ref,
    required this.countries,
  });
  final Map<String, dynamic>? partner;
  final WidgetRef ref;
  final List<CoolCountry> countries;

  @override
  State<_EditPartnerSheet> createState() => _EditPartnerSheetState();
}

class _EditPartnerSheetState extends State<_EditPartnerSheet> {
  late final TextEditingController _nameCtl;
  late final TextEditingController _slugCtl;
  late final TextEditingController _emojiCtl;
  late final TextEditingController _subtitleCtl;
  late final TextEditingController _categoryCtl;
  late final TextEditingController _whatsappCtl;
  late bool _isActive;
  late String _selectedCountryCode;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.partner;
    _nameCtl = TextEditingController(text: p?['name']?.toString() ?? '');
    _slugCtl = TextEditingController(text: p?['slug']?.toString() ?? '');
    _emojiCtl = TextEditingController(text: p?['emoji']?.toString() ?? '');
    _subtitleCtl = TextEditingController(
      text: p?['subtitle']?.toString() ?? '',
    );
    _categoryCtl = TextEditingController(
      text: p?['category']?.toString() ?? '',
    );
    _whatsappCtl = TextEditingController(
      text: p?['whatsapp_number']?.toString() ?? '',
    );
    _isActive = p?['is_active'] == true || p == null;
    _selectedCountryCode =
        CoolCountryCatalog.byIsoCode(
          p?['country']?.toString(),
          source: widget.countries,
        )?.isoCode ??
        widget.countries.first.isoCode;
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _slugCtl.dispose();
    _emojiCtl.dispose();
    _subtitleCtl.dispose();
    _categoryCtl.dispose();
    _whatsappCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final data = <String, dynamic>{
      'name': _nameCtl.text.trim(),
      'slug': _slugCtl.text.trim(),
      'emoji': _emojiCtl.text.trim(),
      'subtitle': _subtitleCtl.text.trim(),
      'category': _categoryCtl.text.trim(),
      'country': _selectedCountryCode,
      'whatsapp_number': _whatsappCtl.text.trim(),
      'is_active': _isActive,
    };
    if (widget.partner != null) data['id'] = widget.partner!['id'];
    try {
      await widget.ref.read(adminRepositoryProvider).upsertPartner(data);
      widget.ref.invalidate(adminPartnersProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        CoolToast.error(context, 'Error: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
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
                  widget.partner != null ? 'Edit Partner' : 'New Partner',
                  style: GoogleFonts.dmSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 16),
                _field('Name', _nameCtl),
                _field('Slug', _slugCtl),
                _field('Emoji', _emojiCtl),
                _field('Subtitle', _subtitleCtl),
                _field('Category', _categoryCtl),
                _countryField(),
                _field('WhatsApp #', _whatsappCtl),
                SwitchListTile(
                  title: Text(
                    'Active',
                    style: GoogleFonts.dmSans(color: AppColors.text),
                  ),
                  value: _isActive,
                  activeTrackColor: AppColors.accent,
                  onChanged: (v) => setState(() => _isActive = v),
                ),
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
  }

  Widget _field(String label, TextEditingController ctl) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctl,
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
  }

  Widget _countryField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        initialValue: _selectedCountryCode,
        dropdownColor: AppColors.surface2,
        decoration: InputDecoration(
          labelText: 'Country',
          labelStyle: GoogleFonts.dmSans(color: AppColors.text3),
          filled: true,
          fillColor: AppColors.surface2,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
        items: widget.countries
            .map(
              (country) => DropdownMenuItem<String>(
                value: country.isoCode,
                child: Text(country.pickerLabel),
              ),
            )
            .toList(growable: false),
        onChanged: _saving
            ? null
            : (value) {
                if (value == null) {
                  return;
                }
                setState(() => _selectedCountryCode = value);
              },
      ),
    );
  }
}
