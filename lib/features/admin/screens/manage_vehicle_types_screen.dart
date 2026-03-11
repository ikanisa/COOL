import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_skeleton.dart';
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
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text(
          'Vehicle Types',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.text),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.accent,
        onPressed: () => _showEditSheet(context, ref, null),
        child: const Icon(Icons.add_rounded, color: Colors.black),
      ),
      body: typesAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: CoolSkeletonList(),
        ),
        error: (e, _) => Center(
          child: Text(
            'Error: $e',
            style: const TextStyle(color: AppColors.text3),
          ),
        ),
        data: (types) {
          if (types.isEmpty) {
            return const Center(
              child: Text(
                'No vehicle types',
                style: TextStyle(color: AppColors.text3),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: types.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final t = types[index];
              return Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
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
                    'value: ${t['value']} · ${t['country'] ?? 'global'}',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: AppColors.text3,
                    ),
                  ),
                  trailing: GestureDetector(
                    onTap: () => _showEditSheet(context, ref, t),
                    child: const Icon(
                      Icons.edit_rounded,
                      size: 18,
                      color: AppColors.text3,
                    ),
                  ),
                ),
              );
            },
          );
        },
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
  late final TextEditingController _labelCtl, _valueCtl, _emojiCtl, _countryCtl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final t = widget.type;
    _labelCtl = TextEditingController(text: t?['label']?.toString() ?? '');
    _valueCtl = TextEditingController(text: t?['value']?.toString() ?? '');
    _emojiCtl = TextEditingController(text: t?['emoji']?.toString() ?? '');
    _countryCtl = TextEditingController(text: t?['country']?.toString() ?? '');
  }

  @override
  void dispose() {
    _labelCtl.dispose();
    _valueCtl.dispose();
    _emojiCtl.dispose();
    _countryCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final data = <String, dynamic>{
      'label': _labelCtl.text.trim(),
      'value': _valueCtl.text.trim(),
      'emoji': _emojiCtl.text.trim(),
      'country': _countryCtl.text.trim().isEmpty
          ? null
          : _countryCtl.text.trim(),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
              _field('Country (ISO, blank=global)', _countryCtl),
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
                          child: CircularProgressIndicator(strokeWidth: 2),
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
  );
}
