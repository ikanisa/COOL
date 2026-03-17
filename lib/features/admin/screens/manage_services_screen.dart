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
import '../providers/admin_providers.dart';
import '../../../core/l10n/l10n.dart';

/// Admin screen for managing partner services.
class ManageServicesScreen extends ConsumerWidget {
  const ManageServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servicesAsync = ref.watch(adminPartnerServicesProvider(null));
    final partners = ref.watch(adminPartnersProvider).valueOrNull ?? const [];

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text(
          'Manage Services',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
        iconTheme: IconThemeData(color: AppColors.text),
      ),
      floatingActionButton: Semantics(
        button: true,
        label: context.l10n.addService,
        hint: 'New service',
        child: FloatingActionButton(
          backgroundColor: AppColors.accent,
          onPressed: () => _showEditSheet(context, ref, null, partners),
          child: const Icon(Icons.add_rounded, color: Colors.black),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: CoolAsyncView<List<Map<String, dynamic>>>(
          value: servicesAsync,
          onRetry: () => ref.invalidate(adminPartnerServicesProvider(null)),
          loadingWidget: const CoolSkeletonList(itemCount: 4),
          emptyCheck: (s) => s.isEmpty,
          emptyWidget: const CoolEmptyView(
            message: 'No services are yet',
            icon: Icons.assignment_outlined,
          ),
          builder: (services) => ListView.separated(
            itemCount: services.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final s = services[index];
              final partnerName =
                  (s['partners'] as Map?)?['name']?.toString() ?? '';
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: _ServiceTile(
                  service: s,
                  partnerName: partnerName,
                  onEdit: () => _showEditSheet(context, ref, s, partners),
                ),
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
    Map<String, dynamic>? service,
    List<Map<String, dynamic>> partners,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) =>
          _EditServiceSheet(service: service, ref: ref, partners: partners),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.service,
    required this.partnerName,
    required this.onEdit,
  });

  final Map<String, dynamic> service;
  final String partnerName;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final isMock = service['is_mock'] == true;
    final mockBatch = service['mock_batch']?.toString().trim() ?? '';
    final title = service['title']?.toString() ?? '';
    final category = service['category']?.toString() ?? '';
    final marketName = AppMarket.country.name;

    return Semantics(
      container: true,
      label:
          'Service title Partner partnerName'
          '${isMock ? ' Mock service.' : ''}'
          '${mockBatch.isNotEmpty ? ' Batch $mockBatch.' : ''}',
      child: ListTile(
        leading: Text(
          service['emoji']?.toString() ?? '📋',
          style: const TextStyle(fontSize: 22),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ),
            if (isMock) const SizedBox(width: 8),
            if (isMock)
              Semantics(
                label: context.l10n.mockService,
                child: ExcludeSemantics(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Mock',
                      style: TextStyle(fontSize: 11, color: Colors.orange),
                    ),
                  ),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$partnerName · $category · $marketName',
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
        trailing: Semantics(
          button: true,
          label: 'Edit service $title',
          hint: 'Opens the service editor',
          child: GestureDetector(
            onTap: onEdit,
            child: Icon(Icons.edit_rounded, size: 18, color: AppColors.text3),
          ),
        ),
      ),
    );
  }
}

class _EditServiceSheet extends StatefulWidget {
  const _EditServiceSheet({
    this.service,
    required this.ref,
    required this.partners,
  });
  final Map<String, dynamic>? service;
  final WidgetRef ref;
  final List<Map<String, dynamic>> partners;
  @override
  State<_EditServiceSheet> createState() => _EditServiceSheetState();
}

class _EditServiceSheetState extends State<_EditServiceSheet> {
  late final TextEditingController _titleCtl,
      _subtitleCtl,
      _emojiCtl,
      _categoryCtl,
      _ctaLabelCtl,
      _ctaActionCtl;
  String? _selectedPartnerId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.service;
    _titleCtl = TextEditingController(text: s?['title']?.toString() ?? '');
    _subtitleCtl = TextEditingController(
      text: s?['subtitle']?.toString() ?? '',
    );
    _emojiCtl = TextEditingController(text: s?['emoji']?.toString() ?? '');
    _categoryCtl = TextEditingController(
      text: s?['category']?.toString() ?? '',
    );
    _ctaLabelCtl = TextEditingController(
      text: s?['cta_label']?.toString() ?? '',
    );
    _ctaActionCtl = TextEditingController(
      text: s?['cta_action']?.toString() ?? '',
    );
    final seededPartnerId = s?['partner_id']?.toString();
    final availablePartnerIds = widget.partners
        .map((partner) => partner['id']?.toString())
        .whereType<String>()
        .toSet();
    _selectedPartnerId = availablePartnerIds.contains(seededPartnerId)
        ? seededPartnerId
        : (widget.partners.isNotEmpty
              ? widget.partners.first['id']?.toString()
              : null);
  }

  @override
  void dispose() {
    _titleCtl.dispose();
    _subtitleCtl.dispose();
    _emojiCtl.dispose();
    _categoryCtl.dispose();
    _ctaLabelCtl.dispose();
    _ctaActionCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final data = <String, dynamic>{
      'title': _titleCtl.text.trim(),
      'subtitle': _subtitleCtl.text.trim(),
      'emoji': _emojiCtl.text.trim(),
      'category': _categoryCtl.text.trim(),
      'cta_label': _ctaLabelCtl.text.trim(),
      'cta_action': _ctaActionCtl.text.trim(),
      'partner_id': _selectedPartnerId,
      'country': AppMarket.countryCode,
    };
    if (widget.service != null) data['id'] = widget.service!['id'];
    try {
      await widget.ref.read(adminRepositoryProvider).upsertPartnerService(data);
      widget.ref.invalidate(adminPartnerServicesProvider(null));
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
                  widget.service != null ? 'Edit Service' : 'New Service',
                  style: GoogleFonts.dmSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 16),
                _partnerField(),
                _field('Title', _titleCtl),
                _field('Subtitle', _subtitleCtl),
                _field('Emoji', _emojiCtl),
                _field('Category', _categoryCtl),
                _field('CTA Label', _ctaLabelCtl),
                _field('CTA Action', _ctaActionCtl),
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
  }

  Widget _field(String label, TextEditingController ctl) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Semantics(
      textField: true,
      label: label,
      hint: 'Enter $label',
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
    ),
  );

  Widget _partnerField() {
    return Padding(
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
                  value: partner['id']?.toString(),
                  child: Text(
                    '${partner['name'] ?? 'Partner'} (${AppMarket.country.name})',
                  ),
                ),
              )
              .toList(growable: false),
          onChanged: _saving
              ? null
              : (value) {
                  setState(() => _selectedPartnerId = value);
                },
        ),
      ),
    );
  }

  Widget _marketField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: IgnorePointer(
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'Market',
            labelStyle: GoogleFonts.dmSans(color: AppColors.text3),
            filled: true,
            fillColor: AppColors.surface2,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          child: Text(
            AppMarket.country.name,
            style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.text),
          ),
        ),
      ),
    );
  }
}