part of '../screens/manage_app_config_screen.dart';

String _configScopeLabel(String? countryCode) {
  return AppMarket.country.name;
}

({Color tone, Color foreground}) _adminStatusPillColors(Color foreground) {
  return (tone: foreground.withValues(alpha: 0.16), foreground: foreground);
}

EdgeInsets _appConfigCardPadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x4,
  right: CoolSpace.x4,
  top: CoolSpace.x4,
  bottom: CoolSpace.x4,
);

EdgeInsets _appConfigStatusPillPadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x3,
  right: CoolSpace.x3,
  top: CoolSpace.x1,
  bottom: CoolSpace.x1,
);

EdgeInsets _appConfigSubtitlePadding() => CoolSpace.sectionPadding.copyWith(
  left: 0,
  right: 0,
  top: CoolSpace.x1,
  bottom: 0,
);

EdgeInsets _appConfigEditIconPadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x2,
  right: CoolSpace.x2,
  top: CoolSpace.x2,
  bottom: CoolSpace.x2,
);

class AppConfigSectionHeader extends StatelessWidget {
  const AppConfigSectionHeader({
    required this.title,
    required this.message,
    super.key,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            color: colors.primaryText,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: CoolSpace.x1),
        Text(
          message,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.secondaryText,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class EmptyConfigCard extends StatelessWidget {
  const EmptyConfigCard({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Container(
      padding: _appConfigCardPadding(),
      decoration: BoxDecoration(
        color: colors.cardSurfaceStrong,
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.sm)),
        boxShadow: CoolShadows.ambientFloat(strength: 0.15),
      ),
      child: Text(
        message,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colors.secondaryText,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class ConfigTile extends StatelessWidget {
  const ConfigTile({required this.config, required this.onEdit, super.key});

  final Map<String, dynamic> config;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final value = config['value']?.toString() ?? '';
    final preview = value.length > 60 ? '${value.substring(0, 60)}…' : value;
    final scopeLabel = _configScopeLabel(config['country']?.toString());

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.cardSurfaceStrong,
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.sm)),
        boxShadow: CoolShadows.ambientFloat(strength: 0.15),
      ),
      child: ListTile(
        title: Text(
          config['key']?.toString() ?? '',
          style: theme.textTheme.titleMedium?.copyWith(
            color: colors.primaryText,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        subtitle: Text(
          '$preview ${config['description'] ?? ''} ($scopeLabel)',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.tertiaryText,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Semantics(
          button: true,
          label: 'Edit ${config['key'] ?? 'config'}',
          child: IconButton(
            onPressed: onEdit,
            tooltip: 'Edit ${config['key'] ?? 'config'}',
            icon: Icon(
              Icons.edit_rounded,
              size: 18,
              color: colors.secondaryText,
            ),
          ),
        ),
      ),
    );
  }
}

class RolloutCard extends StatelessWidget {
  const RolloutCard({required this.rollout, required this.onEdit, super.key});

  final AdminFeatureRolloutConfig rollout;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final stageLabel = rollout.rollout.stage.remoteConfigValue.toUpperCase();
    final stageColors = _adminStatusPillColors(
      rollout.rollout.killSwitch ? colors.danger : colors.success,
    );
    final accessColors = _adminStatusPillColors(
      rollout.rollout.adminOnly ? colors.warning : colors.info,
    );
    final marketColors = _adminStatusPillColors(colors.accent);

    return Container(
      padding: _appConfigCardPadding(),
      decoration: BoxDecoration(
        color: colors.cardSurfaceStrong,
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.sm)),
        boxShadow: CoolShadows.ambientFloat(strength: 0.15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rollout.label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.primaryText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: CoolSpace.x1),
                    Text(
                      rollout.description,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.secondaryText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onEdit,
                tooltip: context.l10n.editRolloutSettings,
                icon: Icon(Icons.tune_rounded, color: colors.primaryText),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x3),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusPill(
                label: rollout.rollout.killSwitch ? 'Killed' : stageLabel,
                tone: stageColors.tone,
                foreground: stageColors.foreground,
              ),
              StatusPill(
                label: rollout.rollout.adminOnly
                    ? 'Admin only'
                    : 'User-accessible',
                tone: accessColors.tone,
                foreground: accessColors.foreground,
              ),
              StatusPill(
                label: context.l10n.rwandaOnly,
                tone: marketColors.tone,
                foreground: marketColors.foreground,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({
    required this.label,
    required this.tone,
    required this.foreground,
    super.key,
  });

  final String label;
  final Color tone;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: _appConfigStatusPillPadding(),
      decoration: BoxDecoration(
        color: tone,
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.pill)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w800,
          color: foreground,
        ),
      ),
    );
  }
}

class PartnerPaymentRouteConfigTile extends StatelessWidget {
  const PartnerPaymentRouteConfigTile({
    required this.config,
    required this.countries,
    required this.onEdit,
    super.key,
  });

  final Map<String, dynamic> config;
  final List<CoolCountry> countries;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final partnerName = config['partner_name']?.toString() ?? 'Partner';
    final provider = config['provider']?.toString() ?? 'provider';
    final recipientCode = config['recipient_code']?.toString() ?? 'missing';
    final reconciliationLabel =
        config['reconciliation_label']?.toString() ?? 'missing_label';
    final status = (config['status']?.toString() ?? 'draft').toLowerCase();
    final statusColors = switch (status) {
      'active' => _adminStatusPillColors(colors.success),
      'inactive' => _adminStatusPillColors(colors.warning),
      _ => _adminStatusPillColors(colors.info),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.cardSurfaceStrong,
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.sm)),
        boxShadow: CoolShadows.ambientFloat(strength: 0.15),
      ),
      child: ListTile(
        title: Text(
          '$partnerName · Rwanda',
          style: theme.textTheme.titleMedium?.copyWith(
            color: colors.primaryText,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Padding(
          padding: _appConfigSubtitlePadding(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${provider.toUpperCase()} · code $recipientCode',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.secondaryText,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: CoolSpace.x1),
              Text(
                'Reconciliation: $reconciliationLabel',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.tertiaryText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusPill(
              label: status.toUpperCase(),
              tone: statusColors.tone,
              foreground: statusColors.foreground,
            ),
            const SizedBox(width: 6),
            Semantics(
              button: true,
              label: context.l10n.editPaymentRouteFor,
              child: Material(
                type: MaterialType.transparency,
                child: InkResponse(
                  onTap: onEdit,
                  radius: 18,
                  child: Padding(
                    padding: _appConfigEditIconPadding(),
                    child: Icon(
                      Icons.edit_rounded,
                      size: 18,
                      color: colors.secondaryText,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
