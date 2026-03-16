import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/config/app_market.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/cool_card.dart';
import '../providers/admin_providers.dart';

/// Full CRUD admin screen for managing partners.
class ManagePartnersScreen extends ConsumerStatefulWidget {
  const ManagePartnersScreen({super.key});

  @override
  ConsumerState<ManagePartnersScreen> createState() =>
      _ManagePartnersScreenState();
}

class _ManagePartnersScreenState extends ConsumerState<ManagePartnersScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final partnersAsync = ref.watch(adminPartnersProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          color: AppColors.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      floatingActionButton: Semantics(
        button: true,
        label: 'Add partner',
        child: FloatingActionButton(
          backgroundColor: AppColors.accent,
          onPressed: () => _openEditor(context, null),
          child: const Icon(Icons.add_rounded, color: Colors.black),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Text(
              'Manage Partners',
              style: GoogleFonts.dmSans(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                height: 1.1,
                color: AppColors.text,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Text(
              'Create, edit, and manage all platform partners',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.text3,
              ),
            ),
          ),
          const SizedBox(height: 14),
          // ── Search bar ──────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.text),
              decoration: InputDecoration(
                hintText: 'Search partners…',
                hintStyle: GoogleFonts.dmSans(
                  fontSize: 13,
                  color: AppColors.text3,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: AppColors.text3,
                ),
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: AppColors.accent,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: CoolAsyncView<List<Map<String, dynamic>>>(
              value: partnersAsync,
              onRetry: () => ref.invalidate(adminPartnersProvider),
              loadingWidget: const CoolSkeletonList(itemCount: 4),
              emptyCheck: (p) => p.isEmpty,
              emptyWidget: const CoolEmptyView(
                message: 'No partners yet',
                icon: Icons.handshake_rounded,
              ),
              builder: (partners) {
                final query = _search.trim().toLowerCase();
                final filtered = query.isEmpty
                    ? partners
                    : partners.where((p) {
                        final name =
                            (p['name']?.toString() ?? '').toLowerCase();
                        final slug =
                            (p['slug']?.toString() ?? '').toLowerCase();
                        final cat =
                            (p['category']?.toString() ?? '').toLowerCase();
                        return name.contains(query) ||
                            slug.contains(query) ||
                            cat.contains(query);
                      }).toList();

                final activeCount =
                    partners.where((p) => p['is_active'] == true).length;
                final inactiveCount = partners.length - activeCount;

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 100),
                  itemCount: filtered.length + 1,
                  separatorBuilder: (_, i) =>
                      SizedBox(height: i == 0 ? 14 : 12),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Row(
                        children: [
                          _MetricBadge(
                            label: 'Total',
                            value: partners.length.toString(),
                          ),
                          const SizedBox(width: 8),
                          _MetricBadge(
                            label: 'Active',
                            value: activeCount.toString(),
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: 8),
                          _MetricBadge(
                            label: 'Inactive',
                            value: inactiveCount.toString(),
                            color: AppColors.orange,
                          ),
                        ],
                      );
                    }
                    final p = filtered[index - 1];
                    return _PartnerCard(
                      partner: p,
                      onEdit: () => _openEditor(context, p),
                      onToggleActive: () => _toggleActive(context, p),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openEditor(
    BuildContext context,
    Map<String, dynamic>? partner,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _PartnerEditorPage(partner: partner, ref: ref),
      ),
    );
  }

  Future<void> _toggleActive(
    BuildContext context,
    Map<String, dynamic> partner,
  ) async {
    final isActive = partner['is_active'] == true;
    final name = partner['name']?.toString() ?? 'Partner';
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: Text(isActive ? 'Deactivate $name?' : 'Activate $name?'),
        content: Text(
          isActive
              ? 'This partner will be hidden from all users.'
              : 'This partner will become visible to users.',
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context, false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: isActive,
            child: Text(isActive ? 'Deactivate' : 'Activate'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(adminRepositoryProvider).upsertPartner({
        'id': partner['id'],
        'is_active': !isActive,
      });
      ref.invalidate(adminPartnersProvider);
      if (context.mounted) {
        CoolToast.success(
          context,
          isActive ? '$name deactivated' : '$name activated',
        );
      }
    } catch (e) {
      if (context.mounted) CoolToast.error(context, 'Error: $e');
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Partner Card (list tile with rich info)
// ─────────────────────────────────────────────────────────────

class _PartnerCard extends StatelessWidget {
  const _PartnerCard({
    required this.partner,
    required this.onEdit,
    required this.onToggleActive,
  });

  final Map<String, dynamic> partner;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;

  @override
  Widget build(BuildContext context) {
    final name = partner['name']?.toString() ?? '';
    final slug = partner['slug']?.toString() ?? '';
    final category = partner['category']?.toString() ?? '';
    final emoji = partner['emoji']?.toString() ?? '🤝';
    final momoCode = partner['momo_code']?.toString() ?? '';
    final whatsapp = partner['whatsapp_number']?.toString() ?? '';
    final website = partner['website_url']?.toString() ?? '';
    final isActive = partner['is_active'] == true;
    final isMock = partner['is_mock'] == true;
    final description = partner['description']?.toString() ?? '';

    return CoolCard(
      onTap: onEdit,
      semanticsLabel: '$name partner. $category. ${isActive ? "Active" : "Inactive"}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ──
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(emoji, style: const TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$slug · $category',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: AppColors.text3,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusChip(isActive: isActive),
              if (isMock) ...[
                const SizedBox(width: 6),
                _TagChip(label: 'Mock', color: Colors.orange),
              ],
            ],
          ),

          // ── Description ──
          if (description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                color: AppColors.text2,
                height: 1.4,
              ),
            ),
          ],

          // ── Detail chips ──
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (momoCode.isNotEmpty)
                _InfoChip(icon: Icons.phone_android_rounded, label: 'MoMo: $momoCode'),
              if (whatsapp.isNotEmpty)
                _InfoChip(icon: Icons.chat_rounded, label: whatsapp),
              if (website.isNotEmpty)
                _InfoChip(icon: Icons.language_rounded, label: 'Website'),
            ],
          ),

          // ── Actions ──
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.edit_rounded,
                  label: 'Edit',
                  onTap: onEdit,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionButton(
                  icon: isActive
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  label: isActive ? 'Deactivate' : 'Activate',
                  onTap: onToggleActive,
                  destructive: isActive,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.isActive});
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? Colors.green : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isActive ? 'Active' : 'Off',
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(fontSize: 11, color: color),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.text3),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.text2),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Colors.red : AppColors.text2;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
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

// ─────────────────────────────────────────────────────────────
// Full-page Partner Editor (replaces bottom sheet)
// ─────────────────────────────────────────────────────────────

const _categories = ['football', 'bank', 'organization'];

class _PartnerEditorPage extends StatefulWidget {
  const _PartnerEditorPage({this.partner, required this.ref});
  final Map<String, dynamic>? partner;
  final WidgetRef ref;

  @override
  State<_PartnerEditorPage> createState() => _PartnerEditorPageState();
}

class _PartnerEditorPageState extends State<_PartnerEditorPage> {
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
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          color: AppColors.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _isNew ? 'New Partner' : 'Edit Partner',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
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
                        color: AppColors.accent,
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
                  backgroundColor: AppColors.accent,
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
        value: _categories.contains(_category) ? _category : null,
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

class _MetricBadge extends StatelessWidget {
  const _MetricBadge({
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.text2;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: GoogleFonts.dmSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: c,
              ),
            ),
            Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.text3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
