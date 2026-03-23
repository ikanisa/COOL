import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_market.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/cool_layout.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/cool_card.dart';
import '../providers/admin_providers.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/widgets/cool_bottom_sheet.dart';
import '../../../shared/widgets/cool_screen_background.dart';

EdgeInsets _vehicleTypesHeaderPadding() =>
    CoolSpace.pagePadding.copyWith(top: 0, bottom: 0);

EdgeInsets _vehicleTypesListPadding() =>
    CoolSpace.scaffoldPadding.copyWith(bottom: CoolLayout.rootBottomClearance);

EdgeInsets _vehicleTypeTilePadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x4,
  right: CoolSpace.x4,
  top: CoolSpace.x2,
  bottom: CoolSpace.x2,
);

EdgeInsets _vehicleTypeFieldPadding() => CoolSpace.sectionPadding.copyWith(
  left: 0,
  right: 0,
  top: 0,
  bottom: CoolSpace.x3,
);

EdgeInsets _vehicleTypeSheetInsets(BuildContext context) {
  final space = context.coolSpace;
  return CoolSpace.pagePadding.copyWith(
    top: space.x3,
    bottom: MediaQuery.of(context).viewInsets.bottom + space.x6,
  );
}

OutlineInputBorder _vehicleTypeInputBorder(
  CoolSemanticColors colors, {
  Color? borderColor,
  double width = 1,
}) {
  return OutlineInputBorder(
    borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.xs)),
    borderSide: BorderSide(color: borderColor ?? colors.border, width: width),
  );
}

Widget _vehicleTypeSheetHandle(BuildContext context) {
  final colors = context.coolSemanticColors;
  return Container(
    width: 40,
    height: 4,
    decoration: BoxDecoration(
      color: colors.border,
      borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.pill)),
    ),
  );
}

/// Admin screen for managing mobility vehicle types.
class ManageVehicleTypesScreen extends ConsumerWidget {
  const ManageVehicleTypesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final space = context.coolSpace;
    final typesAsync = ref.watch(adminVehicleTypesProvider);

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
          label: context.l10n.addVehicleType,
          hint: 'New vehicle type',
          child: FloatingActionButton(
            backgroundColor: colors.accent,
            onPressed: () => _showEditSheet(context, ref, null),
            child: Icon(Icons.add_rounded, color: colors.accentForeground),
          ),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: _vehicleTypesHeaderPadding(),
              child: Text(
                'Vehicle Types',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                  color: colors.primaryText,
                ),
              ),
            ),
            SizedBox(height: space.x2),
            Padding(
              padding: _vehicleTypesHeaderPadding(),
              child: Text(
                'Mobility ride types',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.tertiaryText,
                ),
              ),
            ),
            SizedBox(height: space.x4),
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
                  padding: _vehicleTypesListPadding(),
                  itemCount: types.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: CoolSpace.x3),
                  itemBuilder: (context, index) {
                    final t = types[index];
                    return CoolCard(
                      padding: CoolSpace.sectionPadding.copyWith(
                        left: 0,
                        right: 0,
                        top: 0,
                        bottom: 0,
                      ),
                      backgroundColor: colors.operationalSurface,
                      useGradient: false,
                      child: Semantics(
                        container: true,
                        label:
                            'Vehicle type ${t['label'] ?? ''}. Value ${t['value'] ?? ''}. '
                            'Market ${AppMarket.country.name}.',
                        child: ListTile(
                          contentPadding: _vehicleTypeTilePadding(),
                          leading: (t['emoji']?.toString() ?? '').isNotEmpty
                              ? Text(
                                  t['emoji'].toString(),
                                  style: theme.textTheme.titleMedium,
                                )
                              : Icon(
                                  Icons.directions_car_filled_rounded,
                                  size: 22,
                                  color: colors.secondaryText,
                                ),
                          title: Text(
                            t['label']?.toString() ?? '',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colors.primaryText,
                            ),
                          ),
                          subtitle: Text(
                            'value: ${t['value']} · ${AppMarket.country.name}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.tertiaryText,
                            ),
                          ),
                          trailing: IconButton(
                            tooltip: 'Edit vehicle type ${t['label'] ?? ''}',
                            onPressed: () => _showEditSheet(context, ref, t),
                            icon: Icon(
                              Icons.edit_rounded,
                              size: 18,
                              color: colors.secondaryText,
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
      ),
    );
  }

  void _showEditSheet(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic>? type,
  ) {
    showCoolBottomSheet<void>(
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
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.overlaySurface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(CoolRadii.lg),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: _vehicleTypeSheetInsets(context),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _vehicleTypeSheetHandle(context),
                const SizedBox(height: CoolSpace.x4),
                Text(
                  widget.type != null
                      ? 'Edit Vehicle Type'
                      : 'New Vehicle Type',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.primaryText,
                  ),
                ),
                const SizedBox(height: CoolSpace.x4),
                _field('Label (e.g. Moto)', _labelCtl),
                _field('Value (e.g. Moto)', _valueCtl),
                _field('Emoji', _emojiCtl),
                _marketField(),
                const SizedBox(height: CoolSpace.x3),
                SizedBox(
                  width: double.infinity,
                  child: CoolButton(
                    label: 'Save',
                    onTap: _save,
                    isLoading: _saving,
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
    padding: _vehicleTypeFieldPadding(),
    child: Builder(
      builder: (context) {
        final colors = context.coolSemanticColors;
        final theme = Theme.of(context);
        return Semantics(
          textField: true,
          label: label,
          hint: 'Enter $label',
          child: TextField(
            controller: ctl,
            style: theme.textTheme.titleSmall?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w700,
            ),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: theme.textTheme.bodySmall?.copyWith(
                color: colors.tertiaryText,
              ),
              filled: true,
              fillColor: colors.inputSurface,
              border: _vehicleTypeInputBorder(colors),
              enabledBorder: _vehicleTypeInputBorder(colors),
              focusedBorder: _vehicleTypeInputBorder(
                colors,
                borderColor: colors.accent,
                width: 1.4,
              ),
              contentPadding: CoolSpace.sectionPadding.copyWith(
                left: CoolSpace.x3,
                right: CoolSpace.x3,
                top: CoolSpace.x3,
                bottom: CoolSpace.x3,
              ),
            ),
          ),
        );
      },
    ),
  );

  Widget _marketField() => Padding(
    padding: _vehicleTypeFieldPadding(),
    child: Builder(
      builder: (context) {
        final colors = context.coolSemanticColors;
        final theme = Theme.of(context);
        return TextFormField(
          initialValue: AppMarket.country.name,
          enabled: false,
          style: theme.textTheme.titleSmall?.copyWith(
            color: colors.primaryText,
            fontWeight: FontWeight.w700,
          ),
          decoration: InputDecoration(
            labelText: 'Market',
            labelStyle: theme.textTheme.bodySmall?.copyWith(
              color: colors.tertiaryText,
            ),
            filled: true,
            fillColor: colors.inputSurface.withValues(alpha: 0.55),
            border: _vehicleTypeInputBorder(colors),
            disabledBorder: _vehicleTypeInputBorder(colors),
            contentPadding: CoolSpace.sectionPadding.copyWith(
              left: CoolSpace.x3,
              right: CoolSpace.x3,
              top: CoolSpace.x3,
              bottom: CoolSpace.x3,
            ),
          ),
        );
      },
    ),
  );
}
