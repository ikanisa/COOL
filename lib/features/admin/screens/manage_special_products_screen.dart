import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/cool_layout.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../models/special_product.dart';
import '../providers/special_products_provider.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/widgets/cool_bottom_sheet.dart';
import '../../../shared/widgets/cool_screen_background.dart';

EdgeInsets _specialProductsHeaderPadding() =>
    CoolSpace.pagePadding.copyWith(top: 0, bottom: 0);

EdgeInsets _specialProductsLoadingPadding() =>
    CoolSpace.scaffoldPadding.copyWith(bottom: CoolSpace.x4);

EdgeInsets _specialProductsListPadding() =>
    CoolSpace.scaffoldPadding.copyWith(bottom: CoolLayout.rootBottomClearance);

EdgeInsets _specialProductStatusPadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x2,
  right: CoolSpace.x2,
  top: CoolSpace.x1,
  bottom: CoolSpace.x1,
);

EdgeInsets _specialProductSheetListPadding() =>
    CoolSpace.pagePadding.copyWith(top: 0, bottom: CoolSpace.x7);

EdgeInsets _specialProductFieldPadding() => CoolSpace.sectionPadding.copyWith(
  left: 0,
  right: 0,
  top: 0,
  bottom: CoolSpace.x3,
);

EdgeInsets _specialProductInputContentPadding() =>
    CoolSpace.sectionPadding.copyWith(
      left: CoolSpace.x3,
      right: CoolSpace.x3,
      top: CoolSpace.x3,
      bottom: CoolSpace.x3,
    );

EdgeInsets _specialProductDropdownPadding() => CoolSpace.sectionPadding
    .copyWith(left: CoolSpace.x3, right: CoolSpace.x3, top: 0, bottom: 0);

OutlineInputBorder _specialProductInputBorder(
  CoolSemanticColors colors, {
  Color? borderColor,
  double width = 1,
}) {
  return OutlineInputBorder(
    borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.xs)),
    borderSide: BorderSide(color: borderColor ?? colors.border, width: width),
  );
}

Widget _specialProductSheetHandle(BuildContext context) {
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

/// Admin CRUD screen for managing special product cards.
class ManageSpecialProductsScreen extends ConsumerWidget {
  const ManageSpecialProductsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final space = context.coolSpace;
    final productsAsync = ref.watch(adminSpecialProductsProvider);

    return CoolScreenBackground(
      showGlow: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            onPressed: () => Navigator.of(context).pop(),
            tooltip: context.l10n.back,
            icon: Icon(Icons.arrow_back_rounded, color: colors.primaryText),
          ),
        ),
        floatingActionButton: Semantics(
          button: true,
          label: 'Create special product',
          hint: 'Open special product form',
          child: FloatingActionButton(
            backgroundColor: colors.accent,
            foregroundColor: colors.accentForeground,
            onPressed: () => _showEditSheet(context, ref, null),
            child: const Icon(Icons.add_rounded),
          ),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: _specialProductsHeaderPadding(),
              child: Semantics(
                header: true,
                child: Text(
                  'Special Products',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                    color: colors.primaryText,
                  ),
                ),
              ),
            ),
            SizedBox(height: space.x2),
            Padding(
              padding: _specialProductsHeaderPadding(),
              child: Text(
                'Manage premium offers and payment routing targets',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.secondaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            SizedBox(height: space.x4),
            Expanded(
              child: CoolAsyncView<List<SpecialProduct>>(
                value: productsAsync,
                loadingWidget: Padding(
                  padding: _specialProductsLoadingPadding(),
                  child: const CoolSkeletonList(itemCount: 4),
                ),
                emptyCheck: (products) => products.isEmpty,
                emptyWidget: const CoolEmptyView(
                  message: 'No special products yet',
                  icon: Icons.inventory_2_outlined,
                ),
                builder: (products) {
                  return ListView.separated(
                    padding: _specialProductsListPadding(),
                    itemCount: products.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: CoolSpace.x3),
                    itemBuilder: (context, index) {
                      final product = products[index];
                      return _ProductAdminCard(
                        product: product,
                        onEdit: () => _showEditSheet(context, ref, product),
                        onToggle: () => _toggleActive(context, ref, product),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditSheet(
    BuildContext context,
    WidgetRef ref,
    SpecialProduct? product,
  ) {
    showCoolBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SpecialProductEditSheet(
        product: product,
        repo: ref.read(specialProductsRepositoryProvider),
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
      final repo = ref.read(specialProductsRepositoryProvider);
      await repo.toggleActive(product.id, isActive: !product.isActive);
      ref.invalidate(adminSpecialProductsProvider);
      if (context.mounted) {
        CoolToast.success(
          context,
          product.isActive
              ? '${product.title} disabled'
              : '${product.title} enabled',
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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final space = context.coolSpace;
    final statusColor = product.isActive ? colors.success : colors.danger;
    return CoolCard(
      onTap: onEdit,
      backgroundColor: colors.financialSurface,
      useGradient: false,
      semanticsLabel: 'Edit ${product.title}',
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: product.accentColor.withValues(alpha: 0.15),
              borderRadius: const BorderRadius.all(
                Radius.circular(CoolRadii.xs),
              ),
            ),
            alignment: Alignment.center,
            child: Icon(product.icon, color: product.accentColor, size: 22),
          ),
          SizedBox(width: space.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        product.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: colors.primaryText,
                        ),
                      ),
                    ),
                    Container(
                      padding: _specialProductStatusPadding(),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: const BorderRadius.all(
                          Radius.circular(CoolRadii.pill),
                        ),
                      ),
                      child: Text(
                        product.isActive ? 'Active' : 'Disabled',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: CoolSpace.x1),
                Text(
                  '${product.formattedAmount} · ${product.targetAudience} · ${product.momoRecipient}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.tertiaryText,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: CoolSpace.x2),
          IconButton(
            icon: Icon(
              product.isActive
                  ? Icons.toggle_on_rounded
                  : Icons.toggle_off_rounded,
              color: product.isActive ? colors.success : colors.tertiaryText,
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
  const _SpecialProductEditSheet({
    this.product,
    required this.repo,
    required this.onSaved,
  });

  final SpecialProduct? product;
  final SpecialProductsRepository repo;
  final VoidCallback onSaved;

  @override
  State<_SpecialProductEditSheet> createState() =>
      _SpecialProductEditSheetState();
}

class _SpecialProductEditSheetState extends State<_SpecialProductEditSheet> {
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
    _amountCtrl = TextEditingController(
      text: p != null ? p.amount.toString() : '',
    );
    _colorCtrl = TextEditingController(text: p?.colorHex ?? '#C9A84C');
    _interestCtrl = TextEditingController(text: p?.interestRate ?? '');
    _loanCtrl = TextEditingController(text: p?.loanMultiplier ?? '');
    _recipientCtrl = TextEditingController(text: p?.momoRecipient ?? '');
    _audienceCtrl = TextEditingController(
      text: p?.targetAudience ?? 'Everyone',
    );
    _sortCtrl = TextEditingController(
      text: p != null ? p.sortOrder.toString() : '0',
    );
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
      CoolToast.error(
        context,
        'Title, amount, and MoMo recipient are required.',
      );
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
        interestRate: _interestCtrl.text.trim().isEmpty
            ? null
            : _interestCtrl.text.trim(),
        loanMultiplier: _loanCtrl.text.trim().isEmpty
            ? null
            : _loanCtrl.text.trim(),
        momoRecipient: _recipientCtrl.text.trim(),
        momoRecipientType: _recipientType,
        targetAudience: _audienceCtrl.text.trim(),
        isActive: _isActive,
        sortOrder: int.tryParse(_sortCtrl.text.trim()) ?? 0,
      );

      final repo = widget.repo;
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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final space = context.coolSpace;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: BoxDecoration(
        color: colors.overlaySurface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(CoolRadii.lg),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: CoolSpace.x3),
          _specialProductSheetHandle(context),
          const SizedBox(height: CoolSpace.x4),
          Padding(
            padding: _specialProductsHeaderPadding(),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _isNew ? 'Create Product' : 'Edit Product',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colors.primaryText,
                    ),
                  ),
                ),
                if (!_isNew)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Active',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.tertiaryText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: CoolSpace.x1),
                      Switch.adaptive(
                        value: _isActive,
                        activeTrackColor: colors.success,
                        onChanged: (v) => setState(() => _isActive = v),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          SizedBox(height: space.x3),
          Flexible(
            child: ListView(
              padding: _specialProductSheetListPadding(),
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
                const SizedBox(height: CoolSpace.x2),
                _DropdownField(
                  label: 'Recipient Type',
                  value: _recipientType,
                  items: const ['code', 'phone_number'],
                  onChanged: (v) => setState(() => _recipientType = v),
                ),
                const SizedBox(height: CoolSpace.x2),
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
                const SizedBox(height: CoolSpace.x2),
                _Field(label: 'Target Audience', controller: _audienceCtrl),
                _Field(
                  label: 'Sort Order',
                  controller: _sortCtrl,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: CoolSpace.x4),
                CoolButton(
                  label: _isNew ? 'Create Product' : 'Save Product',
                  onTap: _save,
                  isLoading: _saving,
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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Padding(
      padding: _specialProductFieldPadding(),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colors.primaryText,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: theme.textTheme.bodySmall?.copyWith(
            color: colors.tertiaryText,
            fontWeight: FontWeight.w600,
          ),
          filled: true,
          fillColor: colors.inputSurface,
          border: _specialProductInputBorder(colors),
          enabledBorder: _specialProductInputBorder(colors),
          focusedBorder: _specialProductInputBorder(
            colors,
            borderColor: colors.accent,
            width: 1.5,
          ),
          contentPadding: _specialProductInputContentPadding(),
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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: colors.tertiaryText,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: CoolSpace.x1),
        Container(
          padding: _specialProductDropdownPadding(),
          decoration: BoxDecoration(
            color: colors.inputSurface,
            borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.xs)),
            border: Border.all(color: colors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: colors.overlaySurface,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.primaryText,
                fontWeight: FontWeight.w600,
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
