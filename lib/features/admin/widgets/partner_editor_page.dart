import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/config/app_market.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/cool_palette.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../providers/admin_providers.dart';

const _categories = ['football', 'bank', 'organization'];

/// Full-page editor for creating / editing a single Partner.
class PartnerEditorPage extends StatefulWidget {
  const PartnerEditorPage({super.key, this.partner, required this.ref});
  final Map<String, dynamic>? partner;
  final WidgetRef ref;

  @override
  State<PartnerEditorPage> createState() => _PartnerEditorPageState();
}

class _PartnerEditorPageState extends State<PartnerEditorPage> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  // ── Core ──
  late final TextEditingController _nameCtl;
  late final TextEditingController _slugCtl;
  late final TextEditingController _emojiCtl;
  late final TextEditingController _subtitleCtl;
  late final TextEditingController _descriptionCtl;
  late String _category;
  late bool _isActive;

  // ── Contact ──
  late final TextEditingController _whatsappCtl;
  late final TextEditingController _momoCodeCtl;
  late final TextEditingController _websiteCtl;

  // ── Branding ──
  late final TextEditingController _logoUrlCtl;
  late final TextEditingController _bannerUrlCtl;
  late final TextEditingController _primaryColorCtl;
  late final TextEditingController _secondaryColorCtl;

  // ── Ordering ──
  late final TextEditingController _sortOrderCtl;

  bool get _isNew => widget.partner == null;

  @override
  void initState() {
    super.initState();
    final p = widget.partner;
    _nameCtl = TextEditingController(text: p?['name']?.toString() ?? '');
    _slugCtl = TextEditingController(text: p?['slug']?.toString() ?? '');
    _emojiCtl = TextEditingController(text: p?['emoji']?.toString() ?? '🤝');
    _subtitleCtl = TextEditingController(
      text: p?['subtitle']?.toString() ?? '',
    );
    _descriptionCtl = TextEditingController(
      text: p?['description']?.toString() ?? '',
    );
    _category = p?['category']?.toString() ?? 'organization';
    _isActive = p?['is_active'] == true || _isNew;

    _whatsappCtl = TextEditingController(
      text: p?['whatsapp_number']?.toString() ?? '',
    );
    _momoCodeCtl = TextEditingController(
      text: p?['momo_code']?.toString() ?? '',
    );
    _websiteCtl = TextEditingController(
      text: p?['website_url']?.toString() ?? '',
    );

    _logoUrlCtl = TextEditingController(
      text: p?['logo_url']?.toString() ?? '',
    );
    _bannerUrlCtl = TextEditingController(
      text: p?['banner_url']?.toString() ?? '',
    );
    _primaryColorCtl = TextEditingController(
      text: p?['brand_primary_color']?.toString() ?? '',
    );
    _secondaryColorCtl = TextEditingController(
      text: p?['brand_secondary_color']?.toString() ?? '',
    );

    _sortOrderCtl = TextEditingController(
      text: (p?['sort_order'] ?? 0).toString(),
    );
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _slugCtl.dispose();
    _emojiCtl.dispose();
    _subtitleCtl.dispose();
    _descriptionCtl.dispose();
    _whatsappCtl.dispose();
    _momoCodeCtl.dispose();
    _websiteCtl.dispose();
    _logoUrlCtl.dispose();
    _bannerUrlCtl.dispose();
    _primaryColorCtl.dispose();
    _secondaryColorCtl.dispose();
    _sortOrderCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final data = <String, dynamic>{
      'name': _nameCtl.text.trim(),
      'slug': _slugCtl.text.trim(),
      'emoji': _emojiCtl.text.trim(),
      'subtitle': _subtitleCtl.text.trim().isEmpty
          ? null
          : _subtitleCtl.text.trim(),
      'description': _descriptionCtl.text.trim().isEmpty
          ? null
          : _descriptionCtl.text.trim(),
      'category': _category,
      'country': AppMarket.countryCode,
      'is_active': _isActive,
      'whatsapp_number': _whatsappCtl.text.trim().isEmpty
          ? null
          : _whatsappCtl.text.trim(),
      'momo_code': _momoCodeCtl.text.trim().isEmpty
          ? null
          : _momoCodeCtl.text.trim(),
      'website_url': _websiteCtl.text.trim().isEmpty
          ? null
          : _websiteCtl.text.trim(),
      'logo_url': _logoUrlCtl.text.trim().isEmpty
          ? null
          : _logoUrlCtl.text.trim(),
      'banner_url': _bannerUrlCtl.text.trim().isEmpty
          ? null
          : _bannerUrlCtl.text.trim(),
      'brand_primary_color': _primaryColorCtl.text.trim().isEmpty
          ? null
          : _primaryColorCtl.text.trim(),
      'brand_secondary_color': _secondaryColorCtl.text.trim().isEmpty
          ? null
          : _secondaryColorCtl.text.trim(),
      'sort_order': int.tryParse(_sortOrderCtl.text.trim()) ?? 0,
    };

    if (!_isNew) data['id'] = widget.partner!['id'];

    try {
      await widget.ref.read(adminRepositoryProvider).upsertPartner(data);
      widget.ref.invalidate(adminPartnersProvider);
      if (mounted) {
        CoolToast.success(
          context,
          _isNew ? 'Partner created' : 'Partner updated',
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) CoolToast.error(context, 'Error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded),
          color: palette.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _isNew ? 'New Partner' : 'Edit Partner',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: palette.text,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const CupertinoActivityIndicator(radius: 10)
                  : Text(
                      'Save',
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: palette.accent,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 48),
          children: [
            // ════════════════════════════════════════════
            // SECTION: Identity
            // ════════════════════════════════════════════
            _sectionHeader('Identity'),
            _textField('Name *', _nameCtl, required_: true),
            Row(
              children: [
                Expanded(child: _textField('Slug *', _slugCtl, required_: true)),
                const SizedBox(width: 12),
                SizedBox(
                  width: 80,
                  child: _textField('Emoji', _emojiCtl),
                ),
              ],
            ),
            _categoryDropdown(),
            _textField('Subtitle', _subtitleCtl),
            _textField(
              'Description',
              _descriptionCtl,
              maxLines: 3,
              hint: 'Short description of the partner',
            ),

            const SizedBox(height: 20),

            // ════════════════════════════════════════════
            // SECTION: Contact & Payments
            // ════════════════════════════════════════════
            _sectionHeader('Contact & Payments'),
            _textField(
              'WhatsApp Number',
              _whatsappCtl,
              hint: '+250788000000',
              keyboard: TextInputType.phone,
            ),
            _textField(
              'MoMo Code',
              _momoCodeCtl,
              hint: 'e.g. *182*8*1*123456#',
            ),
            _textField(
              'Website URL',
              _websiteCtl,
              hint: 'https://...',
              keyboard: TextInputType.url,
            ),

            const SizedBox(height: 20),

            // ════════════════════════════════════════════
            // SECTION: Branding
            // ════════════════════════════════════════════
            _sectionHeader('Branding'),
            _textField(
              'Logo URL',
              _logoUrlCtl,
              hint: 'https://... (square image)',
              keyboard: TextInputType.url,
            ),
            _textField(
              'Banner URL',
              _bannerUrlCtl,
              hint: 'https://... (wide banner)',
              keyboard: TextInputType.url,
            ),
            Row(
              children: [
                Expanded(
                  child: _textField(
                    'Primary Color',
                    _primaryColorCtl,
                    hint: '#FF5733',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _textField(
                    'Secondary Color',
                    _secondaryColorCtl,
                    hint: '#333333',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ════════════════════════════════════════════
            // SECTION: Settings
            // ════════════════════════════════════════════
            _sectionHeader('Settings'),
            _marketField(),
            _textField(
              'Sort Order',
              _sortOrderCtl,
              hint: '0',
              keyboard: TextInputType.number,
            ),
            _switchTile('Active', _isActive, (v) {
              setState(() => _isActive = v);
            }),

            const SizedBox(height: 32),

            // ════════════════════════════════════════════
            // SAVE BUTTON
            // ════════════════════════════════════════════
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.accent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _saving
                    ? const CupertinoActivityIndicator(radius: 10)
                    : Text(
                        _isNew ? 'Create Partner' : 'Save Changes',
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
    );
  }

  // ── Builders ──

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: GoogleFonts.dmSans(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.text,
        ),
      ),
    );
  }

  Widget _textField(
    String label,
    TextEditingController ctl, {
    int maxLines = 1,
    String? hint,
    TextInputType? keyboard,
    bool required_ = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        textField: true,
        label: label,
        child: TextFormField(
          controller: ctl,
          maxLines: maxLines,
          keyboardType: keyboard,
          style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.text),
          validator: required_
              ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
              : null,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            labelStyle: GoogleFonts.dmSans(color: AppColors.text3),
            hintStyle: GoogleFonts.dmSans(
              color: AppColors.text3.withValues(alpha: 0.5),
              fontSize: 13,
            ),
            filled: true,
            fillColor: AppColors.surface2,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _categoryDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: _categories.contains(_category) ? _category : null,
        onChanged: (v) {
          if (v != null) setState(() => _category = v);
        },
        style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.text),
        dropdownColor: AppColors.surface,
        decoration: InputDecoration(
          labelText: 'Category *',
          labelStyle: GoogleFonts.dmSans(color: AppColors.text3),
          filled: true,
          fillColor: AppColors.surface2,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
        ),
        items: _categories
            .map((c) => DropdownMenuItem(
                  value: c,
                  child: Text(
                    c[0].toUpperCase() + c.substring(1),
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      color: AppColors.text,
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _marketField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        initialValue: AppMarket.country.name,
        enabled: false,
        style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.text),
        decoration: InputDecoration(
          labelText: 'Market (auto)',
          labelStyle: GoogleFonts.dmSans(color: AppColors.text3),
          filled: true,
          fillColor: AppColors.surface2.withValues(alpha: 0.5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  Widget _switchTile(String label, bool value, ValueChanged<bool> onChanged) {
    return Semantics(
      label: label,
      toggled: value,
      child: SwitchListTile(
        title: Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.text,
          ),
        ),
        value: value,
        activeTrackColor: AppColors.accent,
        contentPadding: EdgeInsets.zero,
        onChanged: onChanged,
      ),
    );
  }
}
