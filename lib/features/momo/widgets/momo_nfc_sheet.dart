part of 'momo_nfc_widgets.dart';

class MomoNfcSheet extends StatelessWidget {
  const MomoNfcSheet({
    required this.country,
    required this.momoNumber,
    required this.momoService,
    required this.appAccessService,
    this.momoCode,
    super.key,
  });

  final CoolCountry country;
  final String momoNumber;
  final MomoService momoService;
  final AppAccessService appAccessService;
  final String? momoCode;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.elevatedBackground,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(CoolRadii.xl),
          topRight: Radius.circular(CoolRadii.xl),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            CoolSpace.x4 + CoolSpace.x1 / 2,
            CoolSpace.x3,
            CoolSpace.x4 + CoolSpace.x1 / 2,
            CoolSpace.x6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: CoolSpace.x2),
              Row(
                children: [
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'NFC pay',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.primaryText,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: context.l10n.close,
                  ),
                ],
              ),
              SizedBox(height: space.x3),
              MomoNfcCard(
                country: country,
                momoNumber: momoNumber,
                momoCode: momoCode,
                momoService: momoService,
                appAccessService: appAccessService,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
