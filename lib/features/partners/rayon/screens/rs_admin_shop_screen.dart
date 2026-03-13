import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../providers/rayon_sports_provider.dart';
import '../../widgets/partner_navigation.dart';
import '../models/rs_models.dart';
import '../providers/rs_admin_provider.dart';

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

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.rsBlue,
        elevation: 0,
        leading: buildPartnerBackButton(
          context,
          fallbackLocation: AppRoutes.adminRayon,
          color: Colors.white,
        ),
        title: Text(
          'Shop Products',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        actions: buildPartnerAppBarActions(context, homeColor: Colors.white),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.rsBlue,
        onPressed: () => _showProductForm(context),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: productsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            'Error: $e',
            style: const TextStyle(color: AppColors.red),
          ),
        ),
        data: (products) {
          if (products.isEmpty) {
            return Center(
              child: Text(
                'No products yet',
                style: GoogleFonts.dmSans(color: AppColors.text3),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: products.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final prod = products[index];
              return _ProductTile(
                product: prod,
                onToggleActive: () => _toggleActive(prod),
                onEdit: () => _showProductForm(context, product: prod),
                onDelete: () => _deleteProduct(prod),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _toggleActive(RsProduct prod) async {
    final repo = ref.read(rayonSportsRepositoryProvider);
    await repo.toggleProductActive(prod.id, isActive: !prod.isActive);
    ref.invalidate(rsAdminProductsProvider);
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
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.red)),
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
  });
  final RsProduct product;
  final VoidCallback onToggleActive;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
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
                      Container(
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
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${product.price} RWF · Stock: ${product.stock} · ${product.category.value}',
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    color: AppColors.text3,
                  ),
                ),
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
              ],
            ),
          ),
        ],
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
    return GestureDetector(
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
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.keyboardType,
  });
  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: GoogleFonts.dmSans(color: AppColors.text, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.dmSans(color: AppColors.text3, fontSize: 13),
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
    );
  }
}
