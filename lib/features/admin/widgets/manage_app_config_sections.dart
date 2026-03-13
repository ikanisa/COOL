part of '../screens/manage_app_config_screen.dart';

class AppConfigSectionHeader extends StatelessWidget {
  const AppConfigSectionHeader({
    required this.title,
    required this.subtitle,
    super.key,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.dmSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.text3),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        message,
        style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.text3),
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
    final value = config['value']?.toString() ?? '';
    final preview = value.length > 60 ? '${value.substring(0, 60)}…' : value;
    final country = config['country']?.toString();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        title: Text(
          config['key']?.toString() ?? '',
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        subtitle: Text(
          '$preview\n${config['description'] ?? ''} ${country != null && country.isNotEmpty ? '($country)' : '(global)'}',
          style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.text3),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: GestureDetector(
          onTap: onEdit,
          child: const Icon(
            Icons.edit_rounded,
            size: 18,
            color: AppColors.text3,
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
    final allowedCountries = rollout.rollout.allowedCountries;
    final stageLabel = rollout.rollout.stage.remoteConfigValue.toUpperCase();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
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
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      rollout.description,
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: AppColors.text3,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onEdit,
                icon: const Icon(Icons.tune_rounded, color: AppColors.text),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusPill(
                label: rollout.rollout.killSwitch ? 'Killed' : stageLabel,
                tone: rollout.rollout.killSwitch
                    ? const Color(0xFFFFD1D1)
                    : const Color(0xFFD9F5D6),
                foreground: rollout.rollout.killSwitch
                    ? const Color(0xFF7A1616)
                    : const Color(0xFF0F5132),
              ),
              StatusPill(
                label: rollout.rollout.adminOnly
                    ? 'Admin only'
                    : 'User-accessible',
                tone: rollout.rollout.adminOnly
                    ? const Color(0xFFFFF2C9)
                    : const Color(0xFFDCE8FF),
                foreground: rollout.rollout.adminOnly
                    ? const Color(0xFF725400)
                    : const Color(0xFF173A7A),
              ),
              StatusPill(
                label: allowedCountries.isEmpty
                    ? 'All countries'
                    : '${allowedCountries.length} countries',
                tone: const Color(0xFFE8E3FF),
                foreground: const Color(0xFF3D2F7A),
              ),
            ],
          ),
          if (allowedCountries.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              allowedCountries.join(', '),
              style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.text3),
            ),
          ],
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tone,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}

class MobilitySubscriptionConfigTile extends StatelessWidget {
  const MobilitySubscriptionConfigTile({
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
    final countryCode = config['country']?.toString();
    final scopeLabel = countryCode == null || countryCode.trim().isEmpty
        ? 'Global default'
        : CoolCountryCatalog.byIsoCode(
                countryCode,
                source: countries,
              )?.pickerLabel ??
              countryCode.toUpperCase();
    final code = config['value']?.toString() ?? '';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        title: Text(
          scopeLabel,
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        subtitle: Text(
          'MoMo code: $code',
          style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.text3),
        ),
        trailing: GestureDetector(
          onTap: onEdit,
          child: const Icon(
            Icons.edit_rounded,
            size: 18,
            color: AppColors.text3,
          ),
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
    final countryCode = config['country']?.toString();
    final scopeLabel = CoolCountryCatalog.byIsoCode(
          countryCode,
          source: countries,
        )?.pickerLabel ??
        (countryCode?.toUpperCase() ?? 'Unknown country');
    final partnerName = config['partner_name']?.toString() ?? 'Partner';
    final provider = config['provider']?.toString() ?? 'provider';
    final recipientCode = config['recipient_code']?.toString() ?? 'missing';
    final reconciliationLabel =
        config['reconciliation_label']?.toString() ?? 'missing_label';
    final status = (config['status']?.toString() ?? 'draft').toLowerCase();
    final (tone, foreground) = switch (status) {
      'active' => (const Color(0xFFD9F5D6), const Color(0xFF0F5132)),
      'inactive' => (const Color(0xFFFFF2C9), const Color(0xFF725400)),
      _ => (const Color(0xFFE8E3FF), const Color(0xFF3D2F7A)),
    };

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        title: Text(
          '$partnerName · $scopeLabel',
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${provider.toUpperCase()} · code $recipientCode',
                style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.text2),
              ),
              const SizedBox(height: 4),
              Text(
                'Reconciliation: $reconciliationLabel',
                style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.text3),
              ),
            ],
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            StatusPill(
              label: status.toUpperCase(),
              tone: tone,
              foreground: foreground,
            ),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: onEdit,
              child: const Icon(
                Icons.edit_rounded,
                size: 18,
                color: AppColors.text3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
