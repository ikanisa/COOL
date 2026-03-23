import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../providers/admin_providers.dart';

const BorderRadius _editUserSheetRadius = BorderRadius.vertical(
  top: Radius.circular(CoolRadii.lg),
);

const BorderRadius _editUserHandleRadius = BorderRadius.all(
  Radius.circular(CoolRadii.pill),
);

const BorderRadius _editUserFieldRadius = BorderRadius.all(
  Radius.circular(CoolRadii.xs),
);

EdgeInsets _editUserSheetInsets(BuildContext context) {
  final space = context.coolSpace;
  return CoolSpace.pagePadding.copyWith(
    top: space.x3,
    bottom: MediaQuery.of(context).viewInsets.bottom + space.x6,
  );
}

EdgeInsets _editUserFieldPadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x3,
  right: CoolSpace.x3,
  top: CoolSpace.x3,
  bottom: CoolSpace.x3,
);

OutlineInputBorder _editUserInputBorder(
  CoolSemanticColors colors, {
  Color? color,
  double width = 1,
}) {
  return OutlineInputBorder(
    borderRadius: _editUserFieldRadius,
    borderSide: BorderSide(color: color ?? colors.border, width: width),
  );
}

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
    if (userId == null || userId.isEmpty) {
      if (mounted) setState(() => _isSaving = false);
      return;
    }

    try {
      final fields = <String, dynamic>{
        'full_name': _nameController.text.trim(),
        'is_admin': _isAdmin,
        'is_driver': _isDriver,
        'vehicle_type': _vehicleController.text.trim().isEmpty
            ? null
            : _vehicleController.text.trim(),
      };

      await ref
          .read(adminUsersRepositoryProvider)
          .updateUserFields(userId, fields);

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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final userId = widget.user['id']?.toString() ?? '';
    final phone = widget.user['phone']?.toString() ?? '';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.overlaySurface,
        borderRadius: _editUserSheetRadius,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: _editUserSheetInsets(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.borderStrong,
                    borderRadius: _editUserHandleRadius,
                  ),
                ),
              ),
              const SizedBox(height: CoolSpace.x5),
              Text(
                'Edit User',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(height: CoolSpace.x1),
              Text(
                '$phone · ${userId.substring(0, 8.clamp(0, userId.length))}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.tertiaryText,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: CoolSpace.x5),
              const _FieldLabel('Full name'),
              const SizedBox(height: 6),
              _EditInput(controller: _nameController),
              const SizedBox(height: CoolSpace.x4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Platform Admin',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.warning,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Switch.adaptive(
                    value: _isAdmin,
                    onChanged: (v) => setState(() => _isAdmin = v),
                    activeTrackColor: colors.warning,
                  ),
                ],
              ),
              const SizedBox(height: CoolSpace.x2),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Driver',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.primaryText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Switch.adaptive(
                    value: _isDriver,
                    onChanged: (v) => setState(() => _isDriver = v),
                    activeTrackColor: colors.accent,
                  ),
                ],
              ),
              if (_isDriver) ...[
                const SizedBox(height: CoolSpace.x2),
                const _FieldLabel('Vehicle type'),
                const SizedBox(height: 6),
                _EditInput(
                  controller: _vehicleController,
                  hint: 'e.g. motorcycle, car',
                ),
              ],
              const SizedBox(height: CoolSpace.x6),
              CoolButton(
                label: 'Save User',
                onTap: _save,
                isLoading: _isSaving,
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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: colors.tertiaryText,
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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: colors.primaryText,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: theme.textTheme.bodySmall?.copyWith(
          color: colors.tertiaryText,
        ),
        filled: true,
        fillColor: colors.inputSurface,
        contentPadding: _editUserFieldPadding(),
        border: _editUserInputBorder(colors),
        enabledBorder: _editUserInputBorder(colors),
        focusedBorder: _editUserInputBorder(
          colors,
          color: colors.accent,
          width: 1.5,
        ),
      ),
    );
  }
}
