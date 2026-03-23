part of '../screens/manage_services_screen.dart';

EdgeInsets _serviceChipPadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x2,
  right: CoolSpace.x2,
  top: CoolSpace.x1,
  bottom: CoolSpace.x1,
);

EdgeInsets _serviceActionPadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x3,
  right: CoolSpace.x3,
  top: CoolSpace.x2,
  bottom: CoolSpace.x2,
);

EdgeInsets _serviceFieldPadding() => CoolSpace.sectionPadding.copyWith(
  left: 0,
  right: 0,
  top: 0,
  bottom: CoolSpace.x3,
);

EdgeInsets _serviceSheetInsets(BuildContext context) {
  final space = context.coolSpace;
  return CoolSpace.pagePadding.copyWith(
    top: space.x3,
    bottom: MediaQuery.of(context).viewInsets.bottom + space.x6,
  );
}

OutlineInputBorder _serviceInputBorder() {
  return const OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(CoolRadii.xs)),
    borderSide: BorderSide.none,
  );
}

BoxDecoration _serviceSheetDecoration(BuildContext context) {
  final colors = context.coolSemanticColors;
  return BoxDecoration(
    color: colors.elevatedBackground,
    borderRadius: const BorderRadius.vertical(
      top: Radius.circular(CoolRadii.lg),
    ),
  );
}

Widget _serviceSheetHandle(BuildContext context) {
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

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Container(
      padding: _serviceChipPadding(),
      decoration: BoxDecoration(
        color: colors.operationalSurface,
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.xs)),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        '$count',
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: colors.secondaryText,
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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final space = context.coolSpace;
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
                  color: colors.operationalSurface,
                  borderRadius: const BorderRadius.all(
                    Radius.circular(CoolRadii.xs),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(emoji, style: theme.textTheme.titleSmall),
              ),
              SizedBox(width: space.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.primaryText,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.tertiaryText,
                        ),
                      ),
                  ],
                ),
              ),
              // Status chip
              Container(
                padding: _serviceChipPadding(),
                decoration: BoxDecoration(
                  color: (isActive ? colors.success : colors.danger).withValues(
                    alpha: 0.12,
                  ),
                  borderRadius: const BorderRadius.all(
                    Radius.circular(CoolRadii.xs),
                  ),
                ),
                child: Text(
                  isActive ? 'Active' : 'Off',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isActive ? colors.success : colors.danger,
                  ),
                ),
              ),
              if (isMock) ...[
                SizedBox(width: space.x2),
                Container(
                  padding: _serviceChipPadding(),
                  decoration: BoxDecoration(
                    color: colors.warning.withValues(alpha: 0.12),
                    borderRadius: const BorderRadius.all(
                      Radius.circular(CoolRadii.xs),
                    ),
                  ),
                  child: Text(
                    'Mock',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.warning,
                    ),
                  ),
                ),
              ],
            ],
          ),

          // ── Details row ──
          SizedBox(height: space.x2),
          Wrap(
            spacing: space.x2,
            runSpacing: space.x1,
            children: [
              if (category.isNotEmpty)
                _Chip(icon: Icons.category_rounded, label: category),
              if (ctaLabel.isNotEmpty)
                _Chip(icon: Icons.touch_app_rounded, label: ctaLabel),
            ],
          ),

          // ── Action row ──
          SizedBox(height: space.x3),
          Row(
            children: [
              Expanded(
                child: _ActionBtn(
                  icon: Icons.edit_rounded,
                  label: 'Edit',
                  onTap: onEdit,
                ),
              ),
              SizedBox(width: space.x2),
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
              SizedBox(width: space.x2),
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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Container(
      padding: _serviceChipPadding(),
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
            style: theme.textTheme.labelLarge?.copyWith(
              color: colors.secondaryText,
            ),
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
            padding: _serviceActionPadding(),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: CoolSpace.x1),
                Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
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
      await widget.ref.read(adminContentRepositoryProvider).upsertPartnerService(data);
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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: _serviceSheetDecoration(context),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: _serviceSheetInsets(context),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _serviceSheetHandle(context),
                const SizedBox(height: CoolSpace.x4),
                Text(
                  widget.service != null ? 'Edit Service' : 'New Service',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.primaryText,
                  ),
                ),
                const SizedBox(height: CoolSpace.x4),
                _partnerField(),
                _field('Title', _titleCtl),
                _field('Subtitle', _subtitleCtl),
                _field('Emoji', _emojiCtl),
                _field('Category', _categoryCtl),
                _field('CTA Label', _ctaLabelCtl),
                _field('CTA Action', _ctaActionCtl),
                _marketField(),
                const SizedBox(height: CoolSpace.x3),
                SizedBox(
                  width: double.infinity,
                  height: CoolTapTargets.minimum,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.accent,
                      foregroundColor: colors.accentForeground,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(
                          Radius.circular(CoolRadii.xs),
                        ),
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
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w600,
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
    padding: _serviceFieldPadding(),
    child: Semantics(
      textField: true,
      label: label,
      hint: 'Enter $label',
      child: TextField(
        controller: ctl,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: context.coolSemanticColors.primaryText,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: context.coolSemanticColors.tertiaryText,
          ),
          filled: true,
          fillColor: context.coolSemanticColors.inputSurface,
          border: _serviceInputBorder(),
        ),
      ),
    ),
  );

  Widget _partnerField() {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Padding(
      padding: _serviceFieldPadding(),
      child: Semantics(
        label: context.l10n.partnerSelector,
        hint: 'Choose partner',
        child: DropdownButtonFormField<String>(
          initialValue: _selectedPartnerId,
          dropdownColor: colors.inputSurface,
          decoration: InputDecoration(
            labelText: 'Partner',
            labelStyle: theme.textTheme.bodySmall?.copyWith(
              color: colors.tertiaryText,
            ),
            filled: true,
            fillColor: colors.inputSurface,
            border: _serviceInputBorder(),
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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Padding(
      padding: _serviceFieldPadding(),
      child: IgnorePointer(
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'Market',
            labelStyle: theme.textTheme.bodySmall?.copyWith(
              color: colors.tertiaryText,
            ),
            filled: true,
            fillColor: colors.inputSurface,
            border: _serviceInputBorder(),
          ),
          child: Text(
            AppMarket.country.name,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.primaryText,
            ),
          ),
        ),
      ),
    );
  }
}
