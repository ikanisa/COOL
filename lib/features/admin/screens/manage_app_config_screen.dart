import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../providers/admin_providers.dart';

/// Admin screen for managing key-value app configuration.
class ManageAppConfigScreen extends ConsumerWidget {
  const ManageAppConfigScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(adminAppConfigProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text(
          'App Config',
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
      body: configAsync.when(
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
        data: (configs) {
          if (configs.isEmpty) {
            return const Center(
              child: Text(
                'No config entries',
                style: TextStyle(color: AppColors.text3),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: configs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final c = configs[index];
              return Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: ListTile(
                  title: Text(
                    c['key']?.toString() ?? '',
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  subtitle: Text(
                    '${c['value']?.toString().substring(0, (c['value']?.toString().length ?? 0) > 60 ? 60 : c['value']?.toString().length ?? 0)}${(c['value']?.toString().length ?? 0) > 60 ? '…' : ''}\n${c['description'] ?? ''} ${c['country'] != null ? '(${c['country']})' : '(global)'}',
                    style: GoogleFonts.dmSans(
                      fontSize: 11,
                      color: AppColors.text3,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: GestureDetector(
                    onTap: () => _showEditSheet(context, ref, c),
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
    Map<String, dynamic>? config,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _EditConfigSheet(config: config, ref: ref),
    );
  }
}

class _EditConfigSheet extends StatefulWidget {
  const _EditConfigSheet({this.config, required this.ref});
  final Map<String, dynamic>? config;
  final WidgetRef ref;
  @override
  State<_EditConfigSheet> createState() => _EditConfigSheetState();
}

class _EditConfigSheetState extends State<_EditConfigSheet> {
  late final TextEditingController _keyCtl, _valueCtl, _descCtl, _countryCtl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.config;
    _keyCtl = TextEditingController(text: c?['key']?.toString() ?? '');
    _valueCtl = TextEditingController(text: c?['value']?.toString() ?? '');
    _descCtl = TextEditingController(text: c?['description']?.toString() ?? '');
    _countryCtl = TextEditingController(text: c?['country']?.toString() ?? '');
  }

  @override
  void dispose() {
    _keyCtl.dispose();
    _valueCtl.dispose();
    _descCtl.dispose();
    _countryCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final data = <String, dynamic>{
      'key': _keyCtl.text.trim(),
      'value': _valueCtl.text.trim(),
      'description': _descCtl.text.trim(),
      'country': _countryCtl.text.trim().isEmpty
          ? null
          : _countryCtl.text.trim(),
    };
    try {
      await widget.ref.read(adminRepositoryProvider).upsertAppConfig(data);
      widget.ref.invalidate(adminAppConfigProvider);
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
                widget.config != null ? 'Edit Config' : 'New Config Entry',
                style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 16),
              _field('Key', _keyCtl, enabled: widget.config == null),
              _field('Value', _valueCtl, maxLines: 4),
              _field('Description', _descCtl),
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

  Widget _field(
    String label,
    TextEditingController ctl, {
    bool enabled = true,
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: ctl,
      enabled: enabled,
      maxLines: maxLines,
      style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.text),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.dmSans(color: AppColors.text3),
        filled: true,
        fillColor: enabled
            ? AppColors.surface2
            : AppColors.surface2.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    ),
  );
}
