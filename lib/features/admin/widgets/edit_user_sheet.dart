import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/cool_palette.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../providers/admin_providers.dart';

/// Bottom sheet for editing a user's admin fields.
class EditUserSheet extends ConsumerStatefulWidget {
  const EditUserSheet({super.key, required this.user, required this.onSaved});
  final Map<String, dynamic> user;
  final VoidCallback onSaved;

  @override
  ConsumerState<EditUserSheet> createState() => _EditUserSheetState();
}

class _EditUserSheetState extends ConsumerState<EditUserSheet> {
  late final TextEditingController _nameController;
  late bool _isDriver;
  late bool _isAdmin;
  late final TextEditingController _vehicleController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.user['full_name']?.toString() ?? '',
    );
    _isDriver = widget.user['is_driver'] == true;
    _isAdmin = widget.user['is_admin'] == true;
    _vehicleController = TextEditingController(
      text: widget.user['vehicle_type']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _vehicleController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    final userId = widget.user['id']?.toString();
    if (userId == null || userId.isEmpty) return;

    try {
      final fields = <String, dynamic>{
        'full_name': _nameController.text.trim(),
        'is_admin': _isAdmin,
        'is_driver': _isDriver,
        'vehicle_type': _vehicleController.text.trim().isEmpty
            ? null
            : _vehicleController.text.trim(),
      };

      await ref.read(adminRepositoryProvider).updateUserFields(userId, fields);

      widget.onSaved();
      if (mounted) {
        Navigator.of(context).pop();
        CoolToast.success(context, 'User updated');
      }
    } catch (e) {
      if (mounted) CoolToast.error(context, 'Failed: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final userId = widget.user['id']?.toString() ?? '';
    final phone = widget.user['phone']?.toString() ?? '';

    return SizedBox(
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            22,
            12,
            22,
            MediaQuery.of(context).viewInsets.bottom + 22,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              Text(
                'Edit User',
                style: GoogleFonts.dmSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: palette.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$phone · ${userId.substring(0, 8.clamp(0, userId.length))}',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: palette.text3,
                ),
              ),
              const SizedBox(height: 20),

              // Full name
              const _FieldLabel('Full name'),
              const SizedBox(height: 6),
              _EditInput(controller: _nameController),
              const SizedBox(height: 16),

              // Admin toggle
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Platform Admin',
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                  Switch.adaptive(
                    value: _isAdmin,
                    onChanged: (v) => setState(() => _isAdmin = v),
                    activeTrackColor: Colors.orange,
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Driver toggle
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Driver',
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: palette.text,
                      ),
                    ),
                  ),
                  Switch.adaptive(
                    value: _isDriver,
                    onChanged: (v) => setState(() => _isDriver = v),
                    activeTrackColor: palette.accent,
                  ),
                ],
              ),

              // Vehicle type (only when driver)
              if (_isDriver) ...[
                const SizedBox(height: 8),
                const _FieldLabel('Vehicle type'),
                const SizedBox(height: 6),
                _EditInput(
                  controller: _vehicleController,
                  hint: 'e.g. motorcycle, car',
                ),
              ],
              const SizedBox(height: 24),

              // Save
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isSaving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: palette.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Save',
                          style: GoogleFonts.dmSans(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Text(
      text,
      style: GoogleFonts.dmSans(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: palette.text3,
        letterSpacing: 0.4,
      ),
    );
  }
}

class _EditInput extends StatelessWidget {
  const _EditInput({required this.controller, this.hint});
  final TextEditingController controller;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return TextField(
      controller: controller,
      style: GoogleFonts.dmSans(fontSize: 14, color: palette.text),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.dmSans(fontSize: 13, color: palette.text3),
        filled: true,
        fillColor: palette.bg,
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
          borderSide: BorderSide(color: palette.accent, width: 1.5),
        ),
      ),
    );
  }
}
