part of '../screens/manage_app_config_screen.dart';

BoxDecoration _adminSheetDecoration(BuildContext context) {
  final colors = context.coolSemanticColors;
  return BoxDecoration(
    color: colors.cardSurfaceStrong,
    borderRadius: const BorderRadius.vertical(
      top: Radius.circular(CoolRadii.lg),
    ),
  );
}

Widget _adminSheetHandle(BuildContext context) {
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

OutlineInputBorder _adminSheetInputBorder(
  CoolSemanticColors colors, {
  Color? borderColor,
}) {
  return OutlineInputBorder(
    borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.xs)),
    borderSide: BorderSide(color: borderColor ?? colors.border, width: 1.1),
  );
}

EdgeInsets _adminSheetInsets(BuildContext context) {
  final space = context.coolSpace;
  return CoolSpace.pagePadding.copyWith(
    top: space.x3,
    bottom: MediaQuery.of(context).viewInsets.bottom + space.x4,
  );
}

Widget _adminSheetFrame(BuildContext context, {required Widget child}) {
  final size = MediaQuery.sizeOf(context);
  final constraints = size.width > 720
      ? const BoxConstraints(maxWidth: 720)
      : const BoxConstraints();
  return FractionallySizedBox(
    alignment: Alignment.bottomCenter,
    heightFactor: 0.96,
    child: Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: constraints,
        child: DecoratedBox(
          decoration: _adminSheetDecoration(context),
          child: SafeArea(
            top: false,
            child: Padding(padding: _adminSheetInsets(context), child: child),
          ),
        ),
      ),
    ),
  );
}

EdgeInsets _adminFieldInsets(BuildContext context) {
  return CoolSpace.sectionPadding.copyWith(
    left: 0,
    right: 0,
    top: 0,
    bottom: context.coolSpace.x3,
  );
}

InputDecoration _adminSheetInputDecoration(
  BuildContext context, {
  required String label,
  bool enabled = true,
}) {
  final colors = context.coolSemanticColors;
  final theme = Theme.of(context);
  return InputDecoration(
    labelText: label,
    labelStyle: theme.textTheme.labelMedium?.copyWith(
      color: colors.secondaryText,
      fontWeight: FontWeight.w600,
    ),
    filled: true,
    fillColor: enabled ? colors.inputSurface : colors.buttonSecondaryBackground,
    border: _adminSheetInputBorder(colors),
    enabledBorder: _adminSheetInputBorder(colors),
    focusedBorder: _adminSheetInputBorder(colors, borderColor: colors.accent),
    disabledBorder: _adminSheetInputBorder(
      colors,
      borderColor: colors.border.withValues(alpha: 0.65),
    ),
  );
}

TextStyle? _adminSheetFieldStyle(BuildContext context) {
  final colors = context.coolSemanticColors;
  return Theme.of(context).textTheme.bodyMedium?.copyWith(
    color: colors.primaryText,
    fontWeight: FontWeight.w600,
  );
}

TextStyle? _adminSheetTitleStyle(BuildContext context) {
  final colors = context.coolSemanticColors;
  return Theme.of(context).textTheme.titleLarge?.copyWith(
    color: colors.primaryText,
    fontWeight: FontWeight.w700,
  );
}

TextStyle? _adminSheetMessageStyle(BuildContext context) {
  final colors = context.coolSemanticColors;
  return Theme.of(context).textTheme.bodySmall?.copyWith(
    color: colors.secondaryText,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );
}

ButtonStyle _adminSheetOutlineStyle(
  BuildContext context, {
  required Color foregroundColor,
  required Color borderColor,
}) {
  return OutlinedButton.styleFrom(
    foregroundColor: foregroundColor,
    side: BorderSide(color: borderColor),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(CoolRadii.xs)),
    ),
  );
}

Widget _adminSheetPrimaryButton(
  BuildContext context, {
  required String label,
  required bool isLoading,
  required VoidCallback? onPressed,
}) {
  final colors = context.coolSemanticColors;
  final theme = Theme.of(context);
  return SizedBox(
    width: double.infinity,
    height: 48,
    child: ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: colors.accent,
        foregroundColor: theme.colorScheme.onPrimary,
        disabledBackgroundColor: colors.buttonSecondaryBackground,
        disabledForegroundColor: colors.tertiaryText,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(CoolRadii.xs)),
        ),
      ),
      child: isLoading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CupertinoActivityIndicator(radius: 10),
            )
          : Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onPrimary,
              ),
            ),
    ),
  );
}

class EditPartnerPaymentRouteSheet extends StatefulWidget {
  const EditPartnerPaymentRouteSheet({
    this.route,
    required this.ref,
    required this.countries,
    required this.partners,
    super.key,
  });

  final Map<String, dynamic>? route;
  final WidgetRef ref;
  final List<CoolCountry> countries;
  final List<Map<String, dynamic>> partners;

  @override
  State<EditPartnerPaymentRouteSheet> createState() =>
      _EditPartnerPaymentRouteSheetState();
}

class _EditPartnerPaymentRouteSheetState
    extends State<EditPartnerPaymentRouteSheet> {
  late final TextEditingController _providerCtl;
  late final TextEditingController _recipientCodeCtl;
  late final TextEditingController _reconciliationCtl;
  String? _selectedPartnerId;
  String _status = 'draft';
  bool _saving = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    final route = widget.route;
    _providerCtl = TextEditingController(
      text: route?['provider']?.toString() ?? '',
    );
    _recipientCodeCtl = TextEditingController(
      text: route?['recipient_code']?.toString() ?? '',
    );
    _reconciliationCtl = TextEditingController(
      text: route?['reconciliation_label']?.toString() ?? '',
    );
    _selectedPartnerId = route?['partner_id']?.toString();
    _status = route?['status']?.toString().toLowerCase() ?? 'draft';
  }

  @override
  void dispose() {
    _providerCtl.dispose();
    _recipientCodeCtl.dispose();
    _reconciliationCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final partnerId = _selectedPartnerId?.trim();
    final provider = _providerCtl.text.trim().toLowerCase();
    final recipientCode = _recipientCodeCtl.text.trim();
    final reconciliationLabel = _reconciliationCtl.text.trim();
    if (partnerId == null || partnerId.isEmpty) {
      CoolToast.error(context, 'Select a partner.');
      return;
    }
    if (provider.isEmpty) {
      CoolToast.error(context, 'Enter a provider id such as mtn_rwanda.');
      return;
    }
    if (reconciliationLabel.isEmpty) {
      CoolToast.error(context, 'Enter a reconciliation label.');
      return;
    }

    final country = AppMarket.country;
    if (!country.supportsMomoCode) {
      CoolToast.error(
        context,
        '${country.name} is not configured for merchant-code payments.',
      );
      return;
    }
    if (_status == 'active' && recipientCode.isEmpty) {
      CoolToast.error(context, 'Active routes require a merchant code.');
      return;
    }
    if (recipientCode.isNotEmpty &&
        !country.isValidMerchantCode(recipientCode)) {
      CoolToast.error(
        context,
        'Merchant code is invalid for ${country.name}. Example: ${country.momoCodeExample ?? 'configured code'}',
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.ref
          .read(adminContentRepositoryProvider)
          .upsertPartnerPaymentRoute(<String, dynamic>{
            'id': widget.route?['id'],
            'partner_id': partnerId,
            'country': AppMarket.countryCode,
            'provider': provider,
            'recipient_code': recipientCode,
            'reconciliation_label': reconciliationLabel,
            'status': _status,
          });
      widget.ref.invalidate(adminPartnerPaymentRoutesProvider);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        CoolToast.error(context, 'Error: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _delete() async {
    final routeId = widget.route?['id']?.toString();
    if (routeId == null || routeId.isEmpty) {
      return;
    }
    setState(() => _deleting = true);
    try {
      await widget.ref
          .read(adminContentRepositoryProvider)
          .deletePartnerPaymentRoute(routeId);
      widget.ref.invalidate(adminPartnerPaymentRoutesProvider);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        CoolToast.error(context, 'Error: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _deleting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return _adminSheetFrame(
      context,
      child: ListView(
        padding: EdgeInsets.zero,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          _adminSheetHandle(context),
          const SizedBox(height: CoolSpace.x4),
          Text(
            widget.route == null
                ? 'Add Partner Payment Route'
                : 'Edit Partner Payment Route',
            style: _adminSheetTitleStyle(context),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: CoolSpace.x2),
          Text(
            'Manage Rwanda partner checkout routing.',
            style: _adminSheetMessageStyle(context),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: CoolSpace.x4),
          _partnerField(),
          _marketField(),
          _field('Provider id', _providerCtl),
          _field('Merchant code', _recipientCodeCtl),
          _field('Reconciliation label', _reconciliationCtl),
          _statusField(),
          const SizedBox(height: CoolSpace.x3),
          _adminSheetPrimaryButton(
            context,
            label: 'Save route',
            isLoading: _saving,
            onPressed: _saving || _deleting ? null : _save,
          ),
          if (widget.route != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton(
                onPressed: _saving || _deleting ? null : _delete,
                style: _adminSheetOutlineStyle(
                  context,
                  foregroundColor: colors.danger,
                  borderColor: colors.danger,
                ),
                child: _deleting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CupertinoActivityIndicator(radius: 9),
                      )
                    : Text(
                        'Delete route',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
          const SizedBox(height: CoolSpace.x2),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController ctl) => Padding(
    padding: _adminFieldInsets(context),
    child: Semantics(
      textField: true,
      label: label,
      hint: 'Enter $label',
      child: TextField(
        controller: ctl,
        maxLines: 1,
        style: _adminSheetFieldStyle(context),
        decoration: _adminSheetInputDecoration(context, label: label),
      ),
    ),
  );

  Widget _partnerField() => Padding(
    padding: _adminFieldInsets(context),
    child: Semantics(
      label: context.l10n.partnerSelector,
      hint: 'Choose partner',
      child: DropdownButtonFormField<String>(
        initialValue: _selectedPartnerId,
        style: _adminSheetFieldStyle(context),
        dropdownColor: context.coolSemanticColors.cardSurfaceStrong,
        decoration: _adminSheetInputDecoration(context, label: 'Partner'),
        items: widget.partners
            .map(
              (partner) => DropdownMenuItem<String>(
                value: partner['id']?.toString() ?? '',
                child: Text(partner['name']?.toString() ?? 'Partner'),
              ),
            )
            .toList(growable: false),
        onChanged: _saving || _deleting
            ? null
            : (value) => setState(() => _selectedPartnerId = value),
      ),
    ),
  );

  Widget _marketField() => Padding(
    padding: _adminFieldInsets(context),
    child: TextFormField(
      initialValue: 'Rwanda',
      enabled: false,
      style: _adminSheetFieldStyle(context),
      decoration: _adminSheetInputDecoration(
        context,
        label: 'Market',
        enabled: false,
      ),
    ),
  );

  Widget _statusField() => Padding(
    padding: _adminFieldInsets(context),
    child: Semantics(
      label: context.l10n.statusSelector,
      hint: 'Choose route status',
      child: DropdownButtonFormField<String>(
        initialValue: _status,
        style: _adminSheetFieldStyle(context),
        dropdownColor: context.coolSemanticColors.cardSurfaceStrong,
        decoration: _adminSheetInputDecoration(context, label: 'Status'),
        items: const [
          DropdownMenuItem<String>(value: 'draft', child: Text('Draft')),
          DropdownMenuItem<String>(value: 'active', child: Text('Active')),
          DropdownMenuItem<String>(value: 'inactive', child: Text('Inactive')),
        ],
        onChanged: _saving || _deleting
            ? null
            : (value) => setState(() => _status = value ?? 'draft'),
      ),
    ),
  );
}
