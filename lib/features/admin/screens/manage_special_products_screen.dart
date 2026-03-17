import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../models/special_product.dart';
import '../providers/special_products_provider.dart';
import '../../../core/l10n/l10n.dart';

/// Admin CRUD screen for managing special product cards.
class ManageSpecialProductsScreen extends ConsumerWidget {
  const ManageSpecialProductsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(adminSpecialProductsProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: context.l10n.back,
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.text),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.accent,
        onPressed: () => _showEditSheet(context, ref, null),
        child: const Icon(Icons.add_rounded, color: Colors.black),
      ),
      body: productsAsync.when(
        data: (products) => products.isEmpty
            ? Center(
                child: Text(
                  'No special products yet',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    color: AppColors.text3,
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 96),
                itemCount: products.length + 1,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Text(
                      'Special Products',
                      style: GoogleFonts.dmSans(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                        height: 1.1,
                      ),
                    );
                  }
                  final product = products[index - 1];
                  return _ProductAdminCard(
                    product: product,
                    onEdit: () => _showEditSheet(context, ref, product),
                    onToggle: () => _toggleActive(context, ref, product),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            'Error: $e',
            style: GoogleFonts.dmSans(color: AppColors.text3),
          ),
        ),
      ),
    );
  }

  void _showEditSheet(
    BuildContext context,
    WidgetRef ref,
    SpecialProduct? product,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SpecialProductEditSheet(
        product: product,
        onSaved: () => ref.invalidate(adminSpecialProductsProvider),
      ),
    );
  }

  Future<void> _toggleActive(
    BuildContext context,
    WidgetRef ref,
    SpecialProduct product,
  ) async {
    try {
      final repo =
          SpecialProductsRepository(Supabase.instance.client);
      await repo.toggleActive(product.id, isActive: !product.isActive);
      ref.invalidate(adminSpecialProductsProvider);
      if (context.mounted) {
        CoolToast.success(
          context,
          product.isActive ? '${product.title} disabled' : '${product.title} enabled',
        );
      }
    } catch (e) {
      if (context.mounted) {
        CoolToast.error(context, 'Failed to toggle: $e');
      }
    }
  }
}

// ─── Admin Product Card ─────────────────────────────────────────────────────

class _ProductAdminCard extends StatelessWidget {
  const _ProductAdminCard({
    required this.product,
    required this.onEdit,
    required this.onToggle,
  });

  final SpecialProduct product;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      onTap: onEdit,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: product.accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child:
                Icon(product.icon, color: product.accentColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        product.title,
                        style: GoogleFonts.dmSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: product.isActive
                            ? Colors.green.withValues(alpha: 0.1)
                            : Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        product.isActive ? 'Active' : 'Disabled',
                        style: GoogleFonts.dmSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color:
                              product.isActive ? Colors.green : Colors.red,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${product.formattedAmount} · ${product.targetAudience} · ${product.momoRecipient}',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: AppColors.text3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              product.isActive
                  ? Icons.toggle_on_rounded
                  : Icons.toggle_off_rounded,
              color: product.isActive ? Colors.green : AppColors.text3,
              size: 32,
            ),
            onPressed: onToggle,
            tooltip: product.isActive ? 'Disable' : 'Enable',
          ),
        ],
      ),
    );
  }
}

// ─── Edit / Create Bottom Sheet ─────────────────────────────────────────────

class _SpecialProductEditSheet extends StatefulWidget {
  const _SpecialProductEditSheet({this.product, required this.onSaved});

  final SpecialProduct? product;
  final VoidCallback onSaved;

  @override
  State<_SpecialProductEditSheet> createState() =>
      _SpecialProductEditSheetState();
}

class _SpecialProductEditSheetState
    extends State<_SpecialProductEditSheet> {
  late final TextEditingController _slugCtrl;
  late final TextEditingController _titleCtrl;
  late final TextEditingController _subtitleCtrl;
  late final TextEditingController _descriptionCtrl;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _colorCtrl;
  late final TextEditingController _interestCtrl;
  late final TextEditingController _loanCtrl;
  late final TextEditingController _recipientCtrl;
  late final TextEditingController _audienceCtrl;
  late final TextEditingController _sortCtrl;
  late String _recipientType;
  late String _iconName;
  late bool _isActive;
  bool _saving = false;

  bool get _isNew => widget.product == null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _slugCtrl = TextEditingController(text: p?.slug ?? '');
    _titleCtrl = TextEditingController(text: p?.title ?? '');
    _subtitleCtrl = TextEditingController(text: p?.subtitle ?? '');
    _descriptionCtrl = TextEditingController(text: p?.description ?? '');
    _amountCtrl =
        TextEditingController(text: p != null ? p.amount.toString() : '');
    _colorCtrl = TextEditingController(text: p?.colorHex ?? '#C9A84C');
    _interestCtrl = TextEditingController(text: p?.interestRate ?? '');
    _loanCtrl = TextEditingController(text: p?.loanMultiplier ?? '');
    _recipientCtrl = TextEditingController(text: p?.momoRecipient ?? '');
    _audienceCtrl =
        TextEditingController(text: p?.targetAudience ?? 'Everyone');
    _sortCtrl =
        TextEditingController(text: p != null ? p.sortOrder.toString() : '0');
    _recipientType = p?.momoRecipientType ?? 'code';
    _iconName = p?.iconName ?? 'directions_car';
    _isActive = p?.isActive ?? true;
  }

  @override
  void dispose() {
    _slugCtrl.dispose();
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    _descriptionCtrl.dispose();
    _amountCtrl.dispose();
    _colorCtrl.dispose();
    _interestCtrl.dispose();
    _loanCtrl.dispose();
    _recipientCtrl.dispose();
    _audienceCtrl.dispose();
    _sortCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty ||
        _amountCtrl.text.trim().isEmpty ||
        _recipientCtrl.text.trim().isEmpty) {
      CoolToast.error(context, 'Title, amount, and MoMo recipient are required.');
      return;
    }

    setState(() => _saving = true);

    try {
      final product = SpecialProduct(
        id: widget.product?.id ?? '',
        slug: _slugCtrl.text.trim(),
        title: _titleCtrl.text.trim(),
        subtitle: _subtitleCtrl.text.trim(),
        description: _descriptionCtrl.text.trim(),
        amount: int.tryParse(_amountCtrl.text.trim()) ?? 0,
        colorHex: _colorCtrl.text.trim(),
        iconName: _iconName,
        interestRate:
            _interestCtrl.text.trim().isEmpty ? null : _interestCtrl.text.trim(),
        loanMultiplier:
            _loanCtrl.text.trim().isEmpty ? null : _loanCtrl.text.trim(),
        momoRecipient: _recipientCtrl.text.trim(),
        momoRecipientType: _recipientType,
        targetAudience: _audienceCtrl.text.trim(),
        isActive: _isActive,
        sortOrder: int.tryParse(_sortCtrl.text.trim()) ?? 0,
      );

      final repo =
          SpecialProductsRepository(Supabase.instance.client);
      await repo.upsert(product);

      widget.onSaved();
      if (mounted) {
        Navigator.of(context).pop();
        CoolToast.success(
          context,
          _isNew ? '${product.title} created' : '${product.title} updated',
        );
      }
    } catch (e) {
      if (mounted) {
        CoolToast.error(context, 'Save failed: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _isNew ? 'Create Product' : 'Edit Product',
                    style: GoogleFonts.dmSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                    ),
                  ),
                ),
                if (!_isNew)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Active',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          color: AppColors.text3,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Switch.adaptive(
                        value: _isActive,
                        activeTrackColor: Colors.green,
                        onChanged: (v) => setState(() => _isActive = v),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
              shrinkWrap: true,
              children: [
                _Field(label: 'Slug', controller: _slugCtrl),
                _Field(label: 'Title', controller: _titleCtrl),
                _Field(label: 'Subtitle', controller: _subtitleCtrl),
                _Field(
                  label: 'Description',
                  controller: _descriptionCtrl,
                  maxLines: 2,
                ),
                _Field(
                  label: 'Amount',
                  controller: _amountCtrl,
                  keyboardType: TextInputType.number,
                ),
                _Field(label: 'Color Hex', controller: _colorCtrl),
                _Field(label: 'Interest Rate', controller: _interestCtrl),
                _Field(label: 'Loan Multiplier', controller: _loanCtrl),
                _Field(label: 'MoMo Recipient', controller: _recipientCtrl),
                const SizedBox(height: 8),
                _DropdownField(
                  label: 'Recipient Type',
                  value: _recipientType,
                  items: const ['code', 'phone_number'],
                  onChanged: (v) => setState(() => _recipientType = v),
                ),
                const SizedBox(height: 8),
                _DropdownField(
                  label: 'Icon',
                  value: _iconName,
                  items: const [
                    'directions_car',
                    'savings',
                    'school',
                    'star',
                    'home',
                    'agriculture',
                    'local_hospital',
                    'construction',
                    'store',
                    'electric_bolt',
                  ],
                  onChanged: (v) => setState(() => _iconName = v),
                ),
                const SizedBox(height: 8),
                _Field(
                  label: 'Target Audience',
                  controller: _audienceCtrl,
                ),
                _Field(
                  label: 'Sort Order',
                  controller: _sortCtrl,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : Text(
                            _isNew ? 'Create' : 'Save',
                            style: GoogleFonts.dmSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.maxLines = 1,
  });

  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        style: GoogleFonts.dmSans(
          fontSize: 14,
          color: AppColors.text,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.dmSans(
            fontSize: 13,
            color: AppColors.text3,
          ),
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
        ),
      ),
    );
  }
}

class _DropdownField extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.text3),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: AppColors.surface,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                color: AppColors.text,
                fontWeight: FontWeight.w500,
              ),
              items: items
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }
}