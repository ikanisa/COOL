import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/cool_layout.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/cool_card.dart';
import '../providers/admin_providers.dart';
import '../../../core/l10n/l10n.dart';
import '../widgets/partner_editor_page.dart';
import '../../../shared/widgets/cool_screen_background.dart';

EdgeInsets _managePartnersHeaderPadding() =>
    CoolSpace.pagePadding.copyWith(top: 0, bottom: 0);

EdgeInsets _managePartnersListPadding() => CoolSpace.pagePadding.copyWith(
  top: 0,
  bottom: CoolLayout.rootBottomClearance,
);

EdgeInsets _partnerSearchContentPadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x3,
  right: CoolSpace.x3,
  top: CoolSpace.x3,
  bottom: CoolSpace.x3,
);

EdgeInsets _partnerChipPadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x2,
  right: CoolSpace.x2,
  top: CoolSpace.x1,
  bottom: CoolSpace.x1,
);

EdgeInsets _partnerActionPadding() => CoolSpace.sectionPadding.copyWith(
  left: 0,
  right: 0,
  top: CoolSpace.x2,
  bottom: CoolSpace.x2,
);

EdgeInsets _partnerMetricPadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x3,
  right: CoolSpace.x3,
  top: CoolSpace.x2,
  bottom: CoolSpace.x2,
);

({Color tone, Color foreground}) _partnerTone(Color foreground) {
  return (tone: foreground.withValues(alpha: 0.12), foreground: foreground);
}

OutlineInputBorder _partnerSearchBorder(
  CoolSemanticColors colors, {
  Color? borderColor,
  double width = 1,
}) {
  return OutlineInputBorder(
    borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.xs)),
    borderSide: BorderSide(color: borderColor ?? colors.border, width: width),
  );
}

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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final space = context.coolSpace;
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
            color: colors.primaryText,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        floatingActionButton: Semantics(
          button: true,
          label: context.l10n.addPartner,
          child: FloatingActionButton(
            backgroundColor: colors.accent,
            onPressed: () => _openEditor(context, null),
            child: Icon(Icons.add_rounded, color: colors.accentForeground),
          ),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: _managePartnersHeaderPadding(),
              child: Text(
                'Manage Partners',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                  color: colors.primaryText,
                ),
              ),
            ),
            SizedBox(height: space.x2),
            Padding(
              padding: _managePartnersHeaderPadding(),
              child: Text(
                'Create, edit, and manage all platform partners',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.tertiaryText,
                ),
              ),
            ),
            SizedBox(height: space.x3),
            Padding(
              padding: _managePartnersHeaderPadding(),
              child: TextField(
                onChanged: (v) => setState(() => _search = v),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.primaryText,
                ),
                decoration: InputDecoration(
                  hintText: 'Search partners…',
                  hintStyle: theme.textTheme.bodySmall?.copyWith(
                    color: colors.tertiaryText,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: colors.tertiaryText,
                  ),
                  filled: true,
                  fillColor: colors.inputSurface,
                  contentPadding: _partnerSearchContentPadding(),
                  border: _partnerSearchBorder(colors),
                  enabledBorder: _partnerSearchBorder(colors),
                  focusedBorder: _partnerSearchBorder(
                    colors,
                    borderColor: colors.accent,
                    width: 1.5,
                  ),
                ),
              ),
            ),
            SizedBox(height: space.x3),
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
                          final name = (p['name']?.toString() ?? '')
                              .toLowerCase();
                          final slug = (p['slug']?.toString() ?? '')
                              .toLowerCase();
                          final cat = (p['category']?.toString() ?? '')
                              .toLowerCase();
                          return name.contains(query) ||
                              slug.contains(query) ||
                              cat.contains(query);
                        }).toList();

                  final activeCount = partners
                      .where((p) => p['is_active'] == true)
                      .length;
                  final inactiveCount = partners.length - activeCount;

                  return ListView.separated(
                    padding: _managePartnersListPadding(),
                    itemCount: filtered.length + 1,
                    separatorBuilder: (_, i) =>
                        SizedBox(height: i == 0 ? CoolSpace.x3 : CoolSpace.x2),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Row(
                          children: [
                            _MetricBadge(
                              label: 'Total',
                              value: partners.length.toString(),
                            ),
                            const SizedBox(width: CoolSpace.x2),
                            _MetricBadge(
                              label: 'Active',
                              value: activeCount.toString(),
                              color: colors.accent,
                            ),
                            const SizedBox(width: CoolSpace.x2),
                            _MetricBadge(
                              label: 'Inactive',
                              value: inactiveCount.toString(),
                              color: colors.warning,
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

  void _openEditor(BuildContext context, Map<String, dynamic>? partner) {
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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final space = context.coolSpace;
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
      semanticsLabel:
          '$name partner. $category. ${isActive ? "Active" : "Inactive"}',
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
                  color: colors.operationalSurface,
                  borderRadius: const BorderRadius.all(
                    Radius.circular(CoolRadii.xs),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(emoji, style: theme.textTheme.titleMedium),
              ),
              SizedBox(width: space.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.primaryText,
                      ),
                    ),
                    const SizedBox(height: CoolSpace.x1),
                    Text(
                      '$slug · $category',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.tertiaryText,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusChip(isActive: isActive),
              if (isMock) ...[
                const SizedBox(width: CoolSpace.x1),
                _TagChip(label: 'Mock', color: colors.warning),
              ],
            ],
          ),

          // ── Description ──
          if (description.isNotEmpty) ...[
            SizedBox(height: space.x3),
            Text(
              description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.secondaryText,
                height: 1.4,
              ),
            ),
          ],

          // ── Detail chips ──
          SizedBox(height: space.x3),
          Wrap(
            spacing: space.x2,
            runSpacing: space.x1,
            children: [
              if (momoCode.isNotEmpty)
                _InfoChip(
                  icon: Icons.phone_android_rounded,
                  label: 'MoMo: $momoCode',
                ),
              if (whatsapp.isNotEmpty)
                _InfoChip(icon: Icons.chat_rounded, label: whatsapp),
              if (website.isNotEmpty)
                const _InfoChip(icon: Icons.language_rounded, label: 'Website'),
            ],
          ),

          // ── Actions ──
          SizedBox(height: space.x3),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.edit_rounded,
                  label: 'Edit',
                  onTap: onEdit,
                ),
              ),
              SizedBox(width: space.x3),
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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final tone = _partnerTone(isActive ? colors.success : colors.danger);
    return Container(
      padding: _partnerChipPadding(),

      decoration: BoxDecoration(
        color: tone.tone,
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.xs)),
      ),
      child: Text(
        isActive ? 'Active' : 'Off',
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: tone.foreground,
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
    final theme = Theme.of(context);
    final tone = _partnerTone(color);
    return Container(
      padding: _partnerChipPadding(),
      decoration: BoxDecoration(
        color: tone.tone,
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.xs)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: tone.foreground),
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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Container(
      padding: _partnerChipPadding(),
      decoration: BoxDecoration(
        color: colors.operationalSurface,
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.xs)),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: colors.tertiaryText),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.secondaryText,
            ),
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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final color = destructive ? colors.danger : colors.secondaryText;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: colors.operationalSurface,
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.xs)),
        child: InkWell(
          onTap: onTap,
          borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.xs)),
          child: Padding(
            padding: _partnerActionPadding(),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: CoolSpace.x1),
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
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
  const _MetricBadge({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final c = color ?? colors.secondaryText;
    return Expanded(
      child: Container(
        padding: _partnerMetricPadding(),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.08),
          borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.xs)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: c,
              ),
            ),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w500,
                color: colors.tertiaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
