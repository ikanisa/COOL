import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/cool_async_view.dart';
import '../../../../shared/widgets/cool_empty_view.dart';
import '../../../../shared/widgets/cool_skeleton.dart';
import '../../providers/rayon_sports_provider.dart';
import '../models/rs_models.dart';
import '../providers/rs_admin_provider.dart';
import '../widgets/rs_admin_shell.dart';
import '../../../../core/l10n/l10n.dart';

/// Admin screen for managing RS shop products — CRUD, toggle active, stock.
class RsAdminShopScreen extends ConsumerStatefulWidget {
  const RsAdminShopScreen({super.key});

  @override
  ConsumerState<RsAdminShopScreen> createState() => _RsAdminShopScreenState();
}

class _RsAdminShopScreenState extends ConsumerState<RsAdminShopScreen> {
  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(rsAdminProductsProvider);

    return RsAdminShell(
      title: context.l10n.shopProducts,
      subtitle:
          'Keep the catalog current',
      floatingActionButton: Semantics(
        button: true,
        label: 'Add product',
        hint: 'New product',
        child: FloatingActionButton(
          backgroundColor: AppColors.rsBlue,
          onPressed: () => _showProductForm(context),
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
      metrics: [
        RsAdminMetric(
          label: 'products',
          value:
              productsAsync.whenOrNull(
                data: (products) => '${products.length}',
              ) ??
              '...',
        ),
        RsAdminMetric(
          label: 'active',
          value:
              productsAsync.whenOrNull(
                data: (products) =>
                    '${products.where((product) => product.isActive).length}',
              ) ??
              '...',
        ),
        RsAdminMetric(
          label: 'stock',
          value:
              productsAsync.whenOrNull(
                data: (products) =>
                    '${products.fold<int>(0, (sum, p) => sum + p.stock)}',
              ) ??
              '...',
        ),
        RsAdminMetric(
          label: 'low',
          value:
              productsAsync.whenOrNull(
                data: (products) =>
                    '${products.where((p) => p.stock <= 5 && p.isActive).length}',
              ) ??
              '...',
        ),
      ],
      child: CoolAsyncView<List<RsProduct>>(
        value: productsAsync,
        onRetry: () => ref.invalidate(rsAdminProductsProvider),
        loadingWidget: const Padding(
          padding: EdgeInsets.all(16),
          child: CoolSkeletonList(itemCount: 4),
        ),
        emptyCheck: (products) => products.isEmpty,
        emptyWidget: const CoolEmptyView(
          subtitle: 'No shop products yet',
          icon: Icons.inventory_2_outlined,
          isPremium: true,
        ),
        builder: (products) => ListView.separated(
          padding: EdgeInsets.zero,
          itemCount: products.length,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final prod = products[index];
            return _ProductTile(
              product: prod,
              onToggleActive: () => _toggleActive(prod),
              onEdit: () => _showProductForm(context, product: prod),
              onDelete: () => _deleteProduct(prod),
              onAdjustStock: (delta) => _adjustStock(prod, delta),
            );
          },
        ),
      ),
    );
  }

  Future<void> _toggleActive(RsProduct prod) async {
    final repo = ref.read(rayonSportsRepositoryProvider);
    await repo.toggleProductActive(prod.id, isActive: !prod.isActive);
    ref.invalidate(rsAdminProductsProvider);
  }

  Future<void> _adjustStock(RsProduct prod, int delta) async {
    final repo = ref.read(rayonSportsRepositoryProvider);
    await repo.adminAdjustStock(prod.id, delta);
    ref.invalidate(rsAdminProductsProvider);
    if (mounted) HapticFeedback.selectionClick();
  }

  Future<void> _deleteProduct(RsProduct prod) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Delete product?',
          style: GoogleFonts.dmSans(color: AppColors.text),
        ),
        content: Text(
          prod.name,
          style: GoogleFonts.dmSans(color: AppColors.text2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.delete, style: const TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final repo = ref.read(rayonSportsRepositoryProvider);
    await repo.deleteProduct(prod.id);
    ref.invalidate(rsAdminProductsProvider);
  }

  void _showProductForm(BuildContext context, {RsProduct? product}) {
    final isEdit = product != null;
    final nameCtrl = TextEditingController(text: product?.name);
    final descCtrl = TextEditingController(text: product?.description);
    final categoryCtrl = TextEditingController(
      text: product?.category.value ?? 'apparel',
    );
    final priceCtrl = TextEditingController(
      text: product?.price.toString() ?? '5000',
    );
    final stockCtrl = TextEditingController(
      text: product?.stock.toString() ?? '50',
    );
    final emojiCtrl = TextEditingController(text: product?.imageEmoji ?? '👕');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isEdit ? 'Edit Product' : 'New Product',
                style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 16),
              _Field(controller: nameCtrl, label: 'Name'),
              _Field(
                controller: descCtrl,
                label: 'Description',
                maxLines: 2,
              ),
              _Field(controller: categoryCtrl, label: 'Category'),
              Row(
                children: [
                  Expanded(
                    child: _Field(
                      controller: priceCtrl,
                      label: 'Price (RWF)',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Field(
                      controller: stockCtrl,
                      label: 'Stock',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              _Field(controller: emojiCtrl, label: 'Emoji Icon'),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.rsBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () async {
                  final repo = ref.read(rayonSportsRepositoryProvider);
                  if (isEdit) {
                    await repo.updateProduct(product.id, <String, dynamic>{
                      'name': nameCtrl.text,
                      'description': descCtrl.text,
                      'category': categoryCtrl.text,
                      'price': int.tryParse(priceCtrl.text) ?? 5000,
                      'stock': int.tryParse(stockCtrl.text) ?? 50,
                      'image_emoji': emojiCtrl.text,
                    });
                  } else {
                    await repo.createProduct(
                      name: nameCtrl.text,
                      category: categoryCtrl.text,
                      price: int.tryParse(priceCtrl.text) ?? 5000,
                      stock: int.tryParse(stockCtrl.text) ?? 50,
                      imageEmoji: emojiCtrl.text,
                    );
                  }
                  ref.invalidate(rsAdminProductsProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text(isEdit ? 'Update' : 'Create'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    required this.product,
    required this.onToggleActive,
    required this.onEdit,
    required this.onDelete,
    required this.onAdjustStock,
  });
  final RsProduct product;
  final VoidCallback onToggleActive;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<int> onAdjustStock;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label:
          'Product ${product.name}. ${product.isActive ?'Active' : 'Inactive'}. '
          'Price ${product.price} Rwandan francs. Stock ${product.stock}. '
          'Category ${product.category.value}.',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Text(product.imageEmoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          product.name,
                          style: GoogleFonts.dmSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                      if (!product.isActive)
                        Semantics(
                          label: 'Status inactive',
                          child: ExcludeSemantics(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.red.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'INACTIVE',
                                style: GoogleFonts.dmSans(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.red,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${product.price} RWF · Stock ${product.stock}',
                    style: GoogleFonts.dmSans(
                      fontSize: 11,
                      color: AppColors.text3,
                    ),
                  ),
                  if (product.stock <= 5 && product.isActive) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, size: 12, color: AppColors.red),
                        const SizedBox(width: 3),
                        Text(
                          'Low stock',
                          style: GoogleFonts.dmSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.red,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (product.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      product.description,
                      style: GoogleFonts.dmSans(
                        fontSize: 11,
                        color: AppColors.text3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _Action(
                        icon: product.isActive
                            ? Icons.visibility_off
                            : Icons.visibility,
                        label: product.isActive ? 'Deactivate' : 'Activate',
                        onTap: onToggleActive,
                      ),
                      const SizedBox(width: 12),
                      _Action(icon: Icons.edit, label: 'Edit', onTap: onEdit),
                      const SizedBox(width: 12),
                      _Action(
                        icon: Icons.delete_outline,
                        label: 'Delete',
                        onTap: onDelete,
                        color: AppColors.red,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Stock +/- row
                  Row(
                    children: [
                      Text(
                        'Stock',
                        style: GoogleFonts.dmSans(
                          fontSize: 10,
                          color: AppColors.text3,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _StockBtn(
                        icon: Icons.remove,
                        onTap: product.stock > 0
                            ? () => onAdjustStock(-1)
                            : null,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          '${product.stock}',
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                      _StockBtn(
                        icon: Icons.add,
                        onTap: () => onAdjustStock(1),
                      ),
                      const SizedBox(width: 8),
                      _StockBtn(
                        icon: Icons.add,
                        label: '+10',
                        onTap: () => onAdjustStock(10),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.text2;
    return Semantics(
      button: true,
      label: label,
      hint: '${label.toLowerCase()} product',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: c),
            const SizedBox(width: 3),
            Text(label, style: GoogleFonts.dmSans(fontSize: 10, color: c)),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.maxLines = 1,
  });
  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        textField: true,
        label: label,
        hint: 'Enter $label',
        child: TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          style: GoogleFonts.dmSans(color: AppColors.text, fontSize: 14),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: GoogleFonts.dmSans(
              color: AppColors.text3,
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
              vertical: 12,
            ),
          ),
        ),
      ),
    );
  }
}

class _StockBtn extends StatelessWidget {
  const _StockBtn({required this.icon, this.label, this.onTap});
  final IconData icon;
  final String? label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: enabled
              ? AppColors.rsBlue.withValues(alpha: 0.12)
              : AppColors.surface2,
          borderRadius: BorderRadius.circular(8),
        ),
        child: label != null
            ? Text(
                label!,
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: enabled ? AppColors.rsBlue : AppColors.text3,
                ),
              )
            : Icon(
                icon,
                size: 14,
                color: enabled ? AppColors.rsBlue : AppColors.text3,
              ),
      ),
    );
  }
}