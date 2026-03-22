import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/cool_palette.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../home/models/nexus_recommendation.dart';

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
    _sortOrderCtrl =
        TextEditingController(text: (i?.sortOrder ?? 0).toString());
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
    final palette = context.coolPalette;
    final isCreate = widget.initial == null;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 14),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: palette.text3.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Row(
              children: [
                Icon(Icons.auto_awesome_rounded,
                    color: palette.accent, size: 22),
                const SizedBox(width: 10),
                Text(
                  isCreate ? 'New AI Content' : 'Edit AI Content',
                  style: GoogleFonts.dmSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: palette.text,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Flexible(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 32),
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
                          _sortOrderCtrl, 'Sort Order',
                          keyboardType: TextInputType.number),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _buildTextField(_ctaActionCtrl, 'CTA Route (e.g. /momo)'),
                const SizedBox(height: 14),
                _buildTextField(_ctaLabelCtrl, 'CTA Label (e.g. Open)'),
                const SizedBox(height: 18),

                // ── Type dropdown ──────────────────────────
                _buildDropdown<AiContentType>(
                  label: 'Content Type',
                  value: _contentType,
                  items: AiContentType.values,
                  itemLabel: (t) => t.label,
                  onChanged: (v) => setState(() => _contentType = v!),
                ),
                const SizedBox(height: 14),

                // ── Status dropdown ────────────────────────
                _buildDropdown<AiContentStatus>(
                  label: 'Status',
                  value: _status,
                  items: AiContentStatus.values,
                  itemLabel: (s) => s.label,
                  onChanged: (v) => setState(() => _status = v!),
                ),
                const SizedBox(height: 14),

                // ── Country dropdown ───────────────────────
                _buildDropdown<String?>(
                  label: 'Country',
                  value: _country,
                  items: const [null, 'RW', 'MT'],
                  itemLabel: (c) => c ?? 'All Countries',
                  onChanged: (v) => setState(() => _country = v),
                ),
                const SizedBox(height: 24),

                // ── Save button ────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _onSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.accent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
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
                            isCreate ? 'Create' : 'Save Changes',
                            style: GoogleFonts.dmSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
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

  Widget _buildTextField(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: GoogleFonts.dmSans(
        fontSize: 14,
        color: AppColors.text,
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
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.accent, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.dmSans(
          fontSize: 13,
          color: AppColors.text3,
        ),
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.border),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: AppColors.bg,
          style: GoogleFonts.dmSans(
            fontSize: 14,
            color: AppColors.text,
          ),
          items: items
              .map((e) => DropdownMenuItem(
                    value: e,
                    child: Text(itemLabel(e)),
                  ))
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
