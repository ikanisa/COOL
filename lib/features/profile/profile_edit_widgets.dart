part of 'profile_edit_screen.dart';

class _ProfileAppBar extends StatelessWidget {
  const _ProfileAppBar({required this.onBack});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: CollectSpacing.x3,
      vertical: CollectSpacing.x2,
    ),
    child: Row(
      children: [
        IconButton(
          tooltip: 'Back',
          onPressed: onBack,
          icon: const Icon(CollectIcons.back),
          constraints: const BoxConstraints.tightFor(
            width: CollectSpacing.target,
            height: CollectSpacing.target,
          ),
        ),
        CollectSpacing.gapW8,
        Expanded(
          child: Text('Profile', style: Theme.of(context).textTheme.titleLarge),
        ),
      ],
    ),
  );
}

class _ProfileIdentity extends StatelessWidget {
  const _ProfileIdentity({required this.publicId});

  final String publicId;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Row(
      children: [
        Container(
          width: CollectSpacing.x8 * 2,
          height: CollectSpacing.x8 * 2,
          decoration: BoxDecoration(
            color: colors.surfaceRaised,
            shape: BoxShape.circle,
          ),
          child: Icon(
            CollectIcons.profile,
            size: CollectSpacing.x8,
            color: colors.textPrimary,
          ),
        ),
        CollectSpacing.gapW16,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Collect ID',
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: colors.textMuted),
              ),
              CollectSpacing.gap4,
              Text(
                publicId,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: CollectTypography.weightBold,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Copy Collect ID',
          onPressed: () =>
              copyToClipboard(context, publicId, message: 'Collect ID copied.'),
          icon: const Icon(CollectIcons.copy),
          constraints: const BoxConstraints.tightFor(
            width: CollectSpacing.target,
            height: CollectSpacing.target,
          ),
        ),
      ],
    );
  }
}

class _ProfileInput extends StatefulWidget {
  const _ProfileInput({
    required this.controller,
    required this.label,
    required this.enabled,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_ProfileInput> createState() => _ProfileInputState();
}

class _ProfileInputState extends State<_ProfileInput> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Focus(
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: Container(
        padding: const EdgeInsets.all(CollectSpacing.x4),
        decoration: BoxDecoration(
          color: colors.surfaceRaised,
          borderRadius: CollectRadius.cardBorder,
          border: Border.all(
            color: _focused ? colors.focusRing : colors.transparent,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Text(
                widget.label,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: colors.textMuted),
              ),
            ),
            CollectSpacing.gap4,
            Semantics(
              label: widget.label,
              child: TextField(
                controller: widget.controller,
                enabled: widget.enabled,
                keyboardType: widget.keyboardType,
                textInputAction: widget.textInputAction,
                onSubmitted: widget.onSubmitted,
                autocorrect: widget.keyboardType == null,
                style: Theme.of(context).textTheme.bodyLarge,
                decoration: const InputDecoration(
                  isCollapsed: true,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileDetails extends StatelessWidget {
  const _ProfileDetails({
    required this.country,
    required this.currencyCode,
    required this.whatsappPhone,
    required this.onCountryTap,
  });

  final Country country;
  final String currencyCode;
  final String whatsappPhone;
  final VoidCallback? onCountryTap;

  @override
  Widget build(BuildContext context) => Material(
    color: context.collectColors.surfaceRaised,
    borderRadius: CollectRadius.cardBorder,
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        Semantics(
          label: 'Profile country, ${country.name}, currency $currencyCode',
          container: true,
          button: true,
          enabled: onCountryTap != null,
          child: InkWell(
            key: const ValueKey('profile_country_picker'),
            onTap: onCountryTap,
            child: _ProfileDetailRow(
              leading: const Icon(CollectIcons.public),
              label: 'Country',
              value: '${country.name} · $currencyCode',
              trailing: const Icon(CollectIcons.chevron),
            ),
          ),
        ),
        Semantics(
          key: const ValueKey('profile_whatsapp_semantics'),
          container: true,
          label: 'Verified WhatsApp, read only',
          readOnly: true,
          child: _ProfileDetailRow(
            leading: const FaIcon(
              FontAwesomeIcons.whatsapp,
              key: ValueKey('profile_whatsapp_icon'),
            ),
            label: 'WhatsApp',
            value: whatsappPhone,
            trailing: Tooltip(
              message: 'Verified WhatsApp',
              child: Icon(
                CollectIcons.check,
                color: context.collectColors.textSecondary,
                size: CollectSpacing.x5,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _ProfileDetailRow extends StatelessWidget {
  const _ProfileDetailRow({
    required this.leading,
    required this.label,
    required this.value,
    required this.trailing,
  });

  final Widget leading;
  final String label;
  final String value;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(CollectSpacing.x4),
    child: Row(
      children: [
        IconTheme.merge(
          data: IconThemeData(
            color: context.collectColors.textSecondary,
            size: CollectSpacing.x6,
          ),
          child: SizedBox(
            width: CollectSpacing.x6,
            child: Center(child: leading),
          ),
        ),
        CollectSpacing.gapW12,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: context.collectColors.textMuted,
                ),
              ),
              CollectSpacing.gap4,
              Text(value, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
        CollectSpacing.gapW8,
        trailing,
      ],
    ),
  );
}

class _ProfileSectionTitle extends StatelessWidget {
  const _ProfileSectionTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: context.collectColors.textSecondary,
      ),
    ),
  );
}
