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
import '../../../core/l10n/l10n.dart';

/// Admin screen for managing partner services — grouped by partner.
class ManageServicesScreen extends ConsumerWidget {
  const ManageServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servicesAsync = ref.watch(adminPartnerServicesProvider(null));
    final partners = ref.watch(adminPartnersProvider).valueOrNull ?? const [];

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: context.l10n.back,
          icon: const Icon(Icons.arrow_back_rounded),
          color: AppColors.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Text(
              'Manage Services',
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
              'Services under Partners — grouped by partner',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.text3,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: CoolAsyncView<List<Map<String, dynamic>>>(
              value: servicesAsync,
              onRetry: () => ref.invalidate(adminPartnerServicesProvider(null)),
              loadingWidget: const CoolSkeletonList(itemCount: 4),
              emptyCheck: (s) => s.isEmpty,
              emptyWidget: const CoolEmptyView(
                message: 'No services yet',
                icon: Icons.assignment_outlined,
              ),
              builder: (services) {
                // Group by partner name
                final grouped = <String, List<Map<String, dynamic>>>{};
                for (final s in services) {
                  final partnerName =
                      (s['partners'] as Map?)?['name']?.toString() ?? 'Other';
                  grouped.putIfAbsent(partnerName, () => []).add(s);
                }
                final sortedKeys = grouped.keys.toList()..sort();

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 100),
                  itemCount: sortedKeys.length,
                  itemBuilder: (context, groupIndex) {
                    final partnerName = sortedKeys[groupIndex];
                    final groupServices = grouped[partnerName]!;
                    final partnerData =
                        partners.cast<Map<String, dynamic>>().firstWhere(
                              (p) => p['name']?.toString() == partnerName,
                              orElse: () => <String, dynamic>{},
                            );
                    final whatsapp =
                        partnerData['whatsapp_number']?.toString() ?? '';

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (groupIndex > 0) const SizedBox(height: 20),
                        // ── Partner section header ──
                        Row(
                          children: [
                            Text(
                              partnerData['emoji']?.toString() ?? '🤝',
                              style: const TextStyle(fontSize: 18),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Services under $partnerName',
                                style: GoogleFonts.dmSans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.text,
                                ),
                              ),
                            ),
                            _CountBadge(count: groupServices.length),
                          ],
                        ),
                        if (whatsapp.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const SizedBox(width: 26),
                              Icon(Icons.chat_rounded,
                                  size: 12, color: AppColors.text3),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  'WhatsApp: $whatsapp',
                                  style: GoogleFonts.dmSans(
                                    fontSize: 11,
                                    color: AppColors.text3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 10),
                        // ── Service cards for this partner ──
                        ...groupServices.map(
                          (s) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _ServiceCard(
                              service: s,
                              onEdit: () =>
                                  _showEditSheet(context, ref, s, partners),
                              onDelete: () =>
                                  _deleteService(context, ref, s),
                              onToggleActive: () =>
                                  _toggleActive(context, ref, s),
                            ),
                          ),
                        ),
                      ],
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

  Future<void> _deleteService(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> service,
  ) async {
    final title = service['title']?.toString() ?? 'Service';
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: Text('Delete "$title"?'),
        content: const Text('This service will be permanently removed.'),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            child: Text(context.l10n.cancel),
            onPressed: () => Navigator.pop(context, false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Delete'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(adminRepositoryProvider).deletePartnerService(
            service['id']?.toString() ?? '',
          );
      ref.invalidate(adminPartnerServicesProvider(null));
      if (context.mounted) CoolToast.success(context, '$title deleted');
    } catch (e) {
      if (context.mounted) CoolToast.error(context, 'Error: $e');
    }
  }

  Future<void> _toggleActive(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> service,
  ) async {
    final isActive = service['is_active'] == true;
    try {
      await ref.read(adminRepositoryProvider).upsertPartnerService({
        'id': service['id'],
        'is_active': !isActive,
      });
      ref.invalidate(adminPartnerServicesProvider(null));
      if (context.mounted) {
        CoolToast.success(
          context,
          isActive ? 'Service deactivated' : 'Service activated',
        );
      }
    } catch (e) {
      if (context.mounted) CoolToast.error(context, 'Error: $e');
    }
  }
}

// ──────────────────────────────────────────────────────────────
// Count badge
// ──────────────────────────────────────────────────────────────

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$count',
        style: GoogleFonts.dmSans(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.text2,
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Service Card (cleaner layout with activation & delete)
// ──────────────────────────────────────────────────────────────

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.service,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleActive,
  });

  final Map<String, dynamic> service;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleActive;

  @override
  Widget build(BuildContext context) {
    final title = service['title']?.toString() ?? '';
    final subtitle = service['subtitle']?.toString() ?? '';
    final emoji = service['emoji']?.toString() ?? '📋';
    final category = service['category']?.toString() ?? '';
    final isMock = service['is_mock'] == true;
    final isActive = service['is_active'] != false;
    final ctaLabel = service['cta_label']?.toString() ?? '';

    return CoolCard(
      onTap: onEdit,
      semanticsLabel:
          'Service $title. ${isActive ? "Active" : "Inactive"}. $category.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ──
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(emoji, style: const TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          color: AppColors.text3,
                        ),
                      ),
                  ],
                ),
              ),
              // Status chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (isActive ? Colors.green : Colors.red)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isActive ? 'Active' : 'Off',
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isActive ? Colors.green : Colors.red,
                  ),
                ),
              ),
              if (isMock) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Mock',
                    style: TextStyle(fontSize: 11, color: Colors.orange),
                  ),
                ),
              ],
            ],
          ),

          // ── Details row ──
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (category.isNotEmpty)
                _Chip(icon: Icons.category_rounded, label: category),
              if (ctaLabel.isNotEmpty)
                _Chip(icon: Icons.touch_app_rounded, label: ctaLabel),
            ],
          ),

          // ── Action row ──
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _ActionBtn(
                  icon: Icons.edit_rounded,
                  label: 'Edit',
                  onTap: onEdit,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionBtn(
                  icon: isActive
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  label: isActive ? 'Deactivate' : 'Activate',
                  onTap: onToggleActive,
                  destructive: isActive,
                ),
              ),
              const SizedBox(width: 8),
              _ActionBtn(
                icon: Icons.delete_rounded,
                label: 'Delete',
                onTap: onDelete,
                destructive: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});
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

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
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
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
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

// ──────────────────────────────────────────────────────────────
// Edit / New Service Bottom Sheet
// ──────────────────────────────────────────────────────────────

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