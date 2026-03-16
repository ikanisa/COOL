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

/// Admin screen for managing mobility vehicle types.
class ManageVehicleTypesScreen extends ConsumerWidget {
  const ManageVehicleTypesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typesAsync = ref.watch(adminVehicleTypesProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          color: AppColors.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      floatingActionButton: Semantics(
        button: true,
        label: 'Add vehicle type',
        hint: 'New vehicle type',
        child: FloatingActionButton(
          backgroundColor: AppColors.accent,
          onPressed: () => _showEditSheet(context, ref, null),
          child: const Icon(Icons.add_rounded, color: Colors.black),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Text(
              'Vehicle Types',
              style: GoogleFonts.dmSans(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                height: 1.1,
                color: AppColors.text,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: CoolAsyncView<List<Map<String, dynamic>>>(
              value: typesAsync,
              onRetry: () => ref.invalidate(adminVehicleTypesProvider),
              loadingWidget: const CoolSkeletonList(itemCount: 4),
              emptyCheck: (t) => t.isEmpty,
              emptyWidget: const CoolEmptyView(
                message: 'No vehicle types yet',
                icon: Icons.directions_car_filled_rounded,
              ),
              builder: (types) => ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                itemCount: types.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final t = types[index];
                  return CoolCard(
                    padding: EdgeInsets.zero,
                    child: Semantics(
                      container: true,
                      label:
                          'Vehicle type ${t['label'] ?? ''}. Value ${t['value'] ?? ''}. '
                          'Market ${AppMarket.country.name}.',
                      child: ListTile(
                        leading: Text(
                          t['emoji']?.toString() ?? '🚘',
                          style: const TextStyle(fontSize: 22),
                        ),
                        title: Text(
                          t['label']?.toString() ?? '',
                          style: GoogleFonts.dmSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          ),
                        ),
                        subtitle: Text(
                          'value: ${t['value']} · ${AppMarket.country.name}',
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            color: AppColors.text3,
                          ),
                        ),
                        trailing: Semantics(
                          button: true,
                          label: 'Edit vehicle type ${t['label'] ?? ''}',
                          hint: 'Edit vehicle type',
                          child: GestureDetector(
                            onTap: () => _showEditSheet(context, ref, t),
                            child: Icon(
                              Icons.edit_rounded,
                              size: 18,
                              color: AppColors.text3,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditSheet(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic>? type,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _EditVehicleTypeSheet(type: type, ref: ref),
    );
  }
}

class _EditVehicleTypeSheet extends StatefulWidget {
  const _EditVehicleTypeSheet({this.type, required this.ref});
  final Map<String, dynamic>? type;
  final WidgetRef ref;
  @override
  State<_EditVehicleTypeSheet> createState() => _EditVehicleTypeSheetState();
}

class _EditVehicleTypeSheetState extends State<_EditVehicleTypeSheet> {
  late final TextEditingController _labelCtl, _valueCtl, _emojiCtl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final t = widget.type;
    _labelCtl = TextEditingController(text: t?['label']?.toString() ?? '');
    _valueCtl = TextEditingController(text: t?['value']?.toString() ?? '');
    _emojiCtl = TextEditingController(text: t?['emoji']?.toString() ?? '');
  }

  @override
  void dispose() {
    _labelCtl.dispose();
    _valueCtl.dispose();
    _emojiCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final data = <String, dynamic>{
      'label': _labelCtl.text.trim(),
      'value': _valueCtl.text.trim(),
      'emoji': _emojiCtl.text.trim(),
      'country': AppMarket.countryCode,
    };
    if (widget.type != null) data['id'] = widget.type!['id'];
    try {
      await widget.ref.read(adminRepositoryProvider).upsertVehicleType(data);
      widget.ref.invalidate(adminVehicleTypesProvider);
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
  Widget build(BuildContext context) => DecoratedBox(
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
                widget.type != null ? 'Edit Vehicle Type' : 'New Vehicle Type',
                style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 16),
              _field('Label (e.g. 🛺 Moto)', _labelCtl),
              _field('Value (e.g. Moto)', _valueCtl),
              _field('Emoji', _emojiCtl),
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

  Widget _marketField() => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      initialValue: AppMarket.country.name,
      enabled: false,
      style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.text),
      decoration: InputDecoration(
        labelText: 'Market',
        labelStyle: GoogleFonts.dmSans(color: AppColors.text3),
        filled: true,
        fillColor: AppColors.surface2.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    ),
  );
}
