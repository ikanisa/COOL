import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';


import '../../../core/theme/cool_palette.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/cool_card.dart';
import '../providers/admin_providers.dart';
import '../../../core/l10n/l10n.dart';
import '../widgets/partner_editor_page.dart';
import '../../../shared/widgets/cool_screen_background.dart';

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
    final palette = context.coolPalette;
    final partnersAsync = ref.watch(adminPartnersProvider);

    return CoolScreenBackground(


      showGlow: false,


      child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: context.l10n.back,
          icon: const Icon(Icons.arrow_back_rounded),
          color: palette.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      floatingActionButton: Semantics(
        button: true,
        label: context.l10n.addPartner,
        child: FloatingActionButton(
          backgroundColor: palette.accent,
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
                color: palette.text,
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
                color: palette.text3,
              ),
            ),
          ),
          const SizedBox(height: 14),
          // ── Search bar ──────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              style: GoogleFonts.dmSans(fontSize: 14, color: palette.text),
              decoration: InputDecoration(
                hintText: 'Search partners…',
                hintStyle: GoogleFonts.dmSans(
                  fontSize: 13,
                  color: palette.text3,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: palette.text3,
                ),
                filled: true,
                fillColor: palette.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: palette.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: palette.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: palette.accent,
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
                            color: palette.accent,
                          ),
                          const SizedBox(width: 8),
                          _MetricBadge(
                            label: 'Inactive',
                            value: inactiveCount.toString(),
                            color: palette.orange,
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
    ),


    );
  }

  void _openEditor(
    BuildContext context,
    Map<String, dynamic>? partner,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PartnerEditorPage(partner: partner, ref: ref),
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
            child: Text(context.l10n.cancel),
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
    final palette = context.coolPalette;
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
                  color: palette.surface2,
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
                        color: palette.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$slug · $category',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: palette.text3,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusChip(isActive: isActive),
              if (isMock) ...[
                const SizedBox(width: 6),
                const _TagChip(label: 'Mock', color: Colors.orange),
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
                color: palette.text2,
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
                const _InfoChip(icon: Icons.language_rounded, label: 'Website'),
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
    final palette = context.coolPalette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: palette.surface2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: palette.text3),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.dmSans(fontSize: 11, color: palette.text2),
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
    final palette = context.coolPalette;
    final color = destructive ? Colors.red : palette.text2;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: palette.surface2,
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
    final palette = context.coolPalette;
    final c = color ?? palette.text2;
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
                color: palette.text3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}