import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_market.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../providers/admin_providers.dart';

part 'partner_editor_page_fields.dart';

const _categories = ['football', 'bank', 'organization'];
EdgeInsets _partnerEditorActionPadding() => CoolSpace.sectionPadding.copyWith(
  left: 0,
  right: CoolSpace.x3,
  top: 0,
  bottom: 0,
);

EdgeInsets _partnerEditorListPadding() =>
    CoolSpace.pagePadding.copyWith(top: CoolSpace.x2, bottom: CoolSpace.x9);

EdgeInsets _partnerEditorFieldPadding() => CoolSpace.sectionPadding.copyWith(
  left: 0,
  right: 0,
  top: 0,
  bottom: CoolSpace.x3,
);

EdgeInsets _partnerEditorInputPadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x3,
  right: CoolSpace.x3,
  top: CoolSpace.x3,
  bottom: CoolSpace.x3,
);

EdgeInsets _partnerEditorZeroPadding() =>
    CoolSpace.sectionPadding.copyWith(left: 0, right: 0, top: 0, bottom: 0);

const BorderRadius _partnerEditorInputRadius = BorderRadius.all(
  Radius.circular(CoolRadii.md),
);

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

    _logoUrlCtl = TextEditingController(text: p?['logo_url']?.toString() ?? '');
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
      await widget.ref.read(adminContentRepositoryProvider).upsertPartner(data);
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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: colors.appBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded),
          color: colors.primaryText,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _isNew ? 'New Partner' : 'Edit Partner',
          style: theme.textTheme.titleLarge?.copyWith(
            color: colors.primaryText,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          Padding(
            padding: _partnerEditorActionPadding(),
            child: TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const CupertinoActivityIndicator(radius: 10)
                  : Text(
                      'Save',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colors.accent,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: _partnerEditorListPadding(),
          children: [
            // ════════════════════════════════════════════
            // SECTION: Identity
            // ════════════════════════════════════════════
            const _PartnerEditorSectionHeader(title: 'Identity'),
            _PartnerEditorTextField(
              label: 'Name *',
              controller: _nameCtl,
              required_: true,
            ),
            Row(
              children: [
                Expanded(
                  child: _PartnerEditorTextField(
                    label: 'Slug *',
                    controller: _slugCtl,
                    required_: true,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 80,
                  child: _PartnerEditorTextField(
                    label: 'Emoji',
                    controller: _emojiCtl,
                  ),
                ),
              ],
            ),
            _PartnerEditorCategoryField(
              category: _category,
              onChanged: (value) => setState(() => _category = value),
            ),
            _PartnerEditorTextField(
              label: 'Subtitle',
              controller: _subtitleCtl,
            ),
            _PartnerEditorTextField(
              label: 'Description',
              controller: _descriptionCtl,
              maxLines: 3,
              hint: 'Short description of the partner',
            ),

            const SizedBox(height: CoolSpace.x5),

            // ════════════════════════════════════════════
            // SECTION: Contact & Payments
            // ════════════════════════════════════════════
            const _PartnerEditorSectionHeader(title: 'Contact & Payments'),
            _PartnerEditorTextField(
              label: 'WhatsApp Number',
              controller: _whatsappCtl,
              hint: '+250788000000',
              keyboard: TextInputType.phone,
            ),
            _PartnerEditorTextField(
              label: 'MoMo Code',
              controller: _momoCodeCtl,
              hint: 'e.g. *182*8*1*123456#',
            ),
            _PartnerEditorTextField(
              label: 'Website URL',
              controller: _websiteCtl,
              hint: 'https://...',
              keyboard: TextInputType.url,
            ),

            const SizedBox(height: CoolSpace.x5),

            // ════════════════════════════════════════════
            // SECTION: Branding
            // ════════════════════════════════════════════
            const _PartnerEditorSectionHeader(title: 'Branding'),
            _PartnerEditorTextField(
              label: 'Logo URL',
              controller: _logoUrlCtl,
              hint: 'https://... (square image)',
              keyboard: TextInputType.url,
            ),
            _PartnerEditorTextField(
              label: 'Banner URL',
              controller: _bannerUrlCtl,
              hint: 'https://... (wide banner)',
              keyboard: TextInputType.url,
            ),
            Row(
              children: [
                Expanded(
                  child: _PartnerEditorTextField(
                    label: 'Primary Color',
                    controller: _primaryColorCtl,
                    hint: '#FF5733',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PartnerEditorTextField(
                    label: 'Secondary Color',
                    controller: _secondaryColorCtl,
                    hint: '#333333',
                  ),
                ),
              ],
            ),

            const SizedBox(height: CoolSpace.x5),

            // ════════════════════════════════════════════
            // SECTION: Settings
            // ════════════════════════════════════════════
            const _PartnerEditorSectionHeader(title: 'Settings'),
            const _PartnerEditorMarketField(),
            _PartnerEditorTextField(
              label: 'Sort Order',
              controller: _sortOrderCtl,
              hint: '0',
              keyboard: TextInputType.number,
            ),
            _PartnerEditorSwitchTile(
              label: 'Active',
              value: _isActive,
              onChanged: (value) => setState(() => _isActive = value),
            ),

            const SizedBox(height: CoolSpace.x7),

            // ════════════════════════════════════════════
            // SAVE BUTTON
            // ════════════════════════════════════════════
            CoolButton(
              label: _isNew ? 'Create Partner' : 'Save Changes',
              isLoading: _saving,
              onTap: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
