import 'package:flutter/material.dart';

import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../home/models/nexus_recommendation.dart';

const BorderRadius _aiContentSheetRadius = BorderRadius.vertical(
  top: Radius.circular(CoolRadii.lg),
);
const BorderRadius _aiContentFieldRadius = BorderRadius.all(
  Radius.circular(CoolRadii.xs),
);
const BorderRadius _aiContentHeroRadius = BorderRadius.all(
  Radius.circular(CoolRadii.md),
);
const BorderRadius _aiContentPillRadius = BorderRadius.all(
  Radius.circular(CoolRadii.pill),
);

EdgeInsets _aiContentHeaderPadding() =>
    CoolSpace.pagePadding.copyWith(top: 0, bottom: 0);

EdgeInsets _aiContentListPadding() =>
    CoolSpace.pagePadding.copyWith(top: 0, bottom: CoolSpace.x7);

EdgeInsets _aiContentFieldPadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x4,
  right: CoolSpace.x4,
  top: CoolSpace.x3,
  bottom: CoolSpace.x3,
);

EdgeInsets _aiContentDropdownPadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x4,
  right: CoolSpace.x4,
  top: CoolSpace.x1,
  bottom: CoolSpace.x1,
);

/// Bottom sheet for creating / editing an AI content item.
class EditAiContentSheet extends StatefulWidget {
  const EditAiContentSheet({super.key, this.initial, required this.onSave});

  final NexusRecommendation? initial;
  final Future<void> Function(NexusRecommendation) onSave;

  @override
  State<EditAiContentSheet> createState() => _EditAiContentSheetState();
}

class _EditAiContentSheetState extends State<EditAiContentSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _subtitleCtrl;
  late final TextEditingController _bodyCtrl;
  late final TextEditingController _rationaleCtrl;
  late final TextEditingController _iconCtrl;
  late final TextEditingController _ctaActionCtrl;
  late final TextEditingController _ctaLabelCtrl;
  late final TextEditingController _sortOrderCtrl;
  late AiContentType _contentType;
  late AiContentStatus _status;
  String? _country;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _titleCtrl = TextEditingController(text: i?.title ?? '');
    _subtitleCtrl = TextEditingController(text: i?.subtitle ?? '');
    _bodyCtrl = TextEditingController(text: i?.body ?? '');
    _rationaleCtrl = TextEditingController(text: i?.rationale ?? '');
    _iconCtrl = TextEditingController(text: i?.iconEmoji ?? '✨');
    _ctaActionCtrl = TextEditingController(text: i?.ctaAction ?? '');
    _ctaLabelCtrl = TextEditingController(text: i?.ctaLabel ?? '');
    _sortOrderCtrl = TextEditingController(
      text: (i?.sortOrder ?? 0).toString(),
    );
    _contentType = i?.contentType ?? AiContentType.recommendation;
    _status = i?.status ?? AiContentStatus.draft;
    _country = i?.country;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    _bodyCtrl.dispose();
    _rationaleCtrl.dispose();
    _iconCtrl.dispose();
    _ctaActionCtrl.dispose();
    _ctaLabelCtrl.dispose();
    _sortOrderCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final isCreate = widget.initial == null;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: colors.overlaySurface,
        borderRadius: _aiContentSheetRadius,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 14),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: colors.borderStrong,
              borderRadius: _aiContentPillRadius,
            ),
          ),
          const SizedBox(height: CoolSpace.x5),
          Padding(
            padding: _aiContentHeaderPadding(),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.accent.withValues(alpha: 0.12),
                    borderRadius: _aiContentHeroRadius,
                  ),
                  child: Icon(
                    CoolIcons.autoAwesome,
                    color: colors.accent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isCreate ? 'New AI Content' : 'Edit AI Content',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colors.primaryText,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: CoolSpace.x5),
          Flexible(
            child: ListView(
              padding: _aiContentListPadding(),
              children: [
                _buildTextField(_titleCtrl, 'Title *'),
                const SizedBox(height: 14),
                _buildTextField(_subtitleCtrl, 'Subtitle'),
                const SizedBox(height: 14),
                _buildTextField(_bodyCtrl, 'Body', maxLines: 3),
                const SizedBox(height: 14),
                _buildTextField(_rationaleCtrl, 'Rationale', maxLines: 2),
                const SizedBox(height: 14),
                Row(
                  children: [
                    SizedBox(
                      width: 80,
                      child: _buildTextField(_iconCtrl, 'Icon'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildTextField(
                        _sortOrderCtrl,
                        'Sort Order',
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _buildTextField(_ctaActionCtrl, 'CTA Route'),
                const SizedBox(height: 14),
                _buildTextField(_ctaLabelCtrl, 'CTA Label'),
                const SizedBox(height: 18),
                _buildDropdown<AiContentType>(
                  label: 'Content Type',
                  value: _contentType,
                  items: AiContentType.values,
                  itemLabel: (t) => t.label,
                  onChanged: (v) => setState(() => _contentType = v!),
                ),
                const SizedBox(height: 14),
                _buildDropdown<AiContentStatus>(
                  label: 'Status',
                  value: _status,
                  items: AiContentStatus.values,
                  itemLabel: (s) => s.label,
                  onChanged: (v) => setState(() => _status = v!),
                ),
                const SizedBox(height: 14),
                _buildDropdown<String?>(
                  label: 'Country',
                  value: _country,
                  items: const [null, 'RW', 'MT'],
                  itemLabel: (c) => c ?? 'All Countries',
                  onChanged: (v) => setState(() => _country = v),
                ),
                const SizedBox(height: CoolSpace.x6),
                CoolButton(
                  label: isCreate ? 'Create Content' : 'Save Content',
                  onTap: _onSave,
                  isLoading: _saving,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
  }) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: colors.primaryText,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: theme.textTheme.bodySmall?.copyWith(
          color: colors.tertiaryText,
          fontWeight: FontWeight.w500,
        ),
        filled: true,
        fillColor: colors.inputSurface,
        border: _aiContentInputBorder(colors),
        enabledBorder: _aiContentInputBorder(colors),
        focusedBorder: _aiContentInputBorder(
          colors,
          borderColor: colors.accent,
          width: 2,
        ),
        contentPadding: _aiContentFieldPadding(),
      ),
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    required String Function(T) itemLabel,
    required ValueChanged<T?> onChanged,
  }) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        labelStyle: theme.textTheme.bodySmall?.copyWith(
          color: colors.tertiaryText,
          fontWeight: FontWeight.w500,
        ),
        filled: true,
        fillColor: colors.inputSurface,
        border: _aiContentInputBorder(colors),
        enabledBorder: _aiContentInputBorder(colors),
        contentPadding: _aiContentDropdownPadding(),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: colors.overlaySurface,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.primaryText,
            fontWeight: FontWeight.w500,
          ),
          items: items
              .map(
                (e) => DropdownMenuItem<T>(value: e, child: Text(itemLabel(e))),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Future<void> _onSave() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      CoolToast.error(context, 'Title is required');
      return;
    }

    setState(() => _saving = true);

    final item = NexusRecommendation(
      id: widget.initial?.id ?? '',
      title: title,
      subtitle: _subtitleCtrl.text.trim(),
      body: _bodyCtrl.text.trim(),
      rationale: _rationaleCtrl.text.trim(),
      contentType: _contentType,
      status: _status,
      iconEmoji: _iconCtrl.text.trim().isEmpty ? '✨' : _iconCtrl.text.trim(),
      ctaAction: _ctaActionCtrl.text.trim(),
      ctaLabel: _ctaLabelCtrl.text.trim(),
      country: _country,
      sortOrder: int.tryParse(_sortOrderCtrl.text.trim()) ?? 0,
    );

    await widget.onSave(item);
    if (mounted) setState(() => _saving = false);
  }
}

OutlineInputBorder _aiContentInputBorder(
  CoolSemanticColors colors, {
  Color? borderColor,
  double width = 1,
}) {
  return OutlineInputBorder(
    borderRadius: _aiContentFieldRadius,
    borderSide: BorderSide(color: borderColor ?? colors.border, width: width),
  );
}
