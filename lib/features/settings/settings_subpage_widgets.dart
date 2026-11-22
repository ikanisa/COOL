import 'package:flutter/material.dart';

import '../../shared/widgets/collect_components.dart';

class SettingsSubpageHeader extends StatelessWidget {
  const SettingsSubpageHeader({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    final colors = context.collectColors;
    final foreground = CollectRuntimeTokens.chromeForeground(colors);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: () => goBackOrHome(context),
            icon: const Icon(Icons.arrow_back_rounded),
            style: IconButton.styleFrom(
              minimumSize: const Size(48, 48),
              foregroundColor: foreground,
            ),
          ),
          ...[
            CollectSpacing.gapW12,
            Expanded(
              child: CollectHeadingText(
                title: title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: foreground,
                  fontWeight: CollectTypography.weightBold,
                  letterSpacing: CollectTypography.trackingDefault,
                ),
                maxLines: largeText ? null : 1,
                overflow: largeText
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class SettingsOptionPanel extends StatelessWidget {
  const SettingsOptionPanel({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return CollectCard(
      emphasis: CollectCardEmphasis.normal,
      padding: const EdgeInsets.symmetric(horizontal: CollectSpacing.x3),
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1)
              Divider(
                height: 1,
                indent: 52,
                color: colors.border.withValues(alpha: 0.48),
              ),
          ],
        ],
      ),
    );
  }
}

class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      enabled: onChanged != null,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      label: '$title. $subtitle',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: CollectSpacing.x2),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: CollectTypography.weightSemibold,
                      ),
                    ),
                  ],
                ),
              ),
              CollectSpacing.gapW12,
              Switch.adaptive(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsLinkRow extends StatelessWidget {
  const SettingsLinkRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      hint: subtitle,
      child: CollectListTile(leading: icon, title: title, onTap: onTap),
    );
  }
}
