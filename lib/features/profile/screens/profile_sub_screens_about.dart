part of 'profile_sub_screens.dart';

class AboutAppScreen extends StatelessWidget {
  const AboutAppScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;

    return _ProfileSubScaffold(
      title: 'ABOUT',
      subtitle: 'RAYON SPORTS APP',
      icon: Icons.info_outline_rounded,
      slivers: [
        Center(
          child: Column(
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [RsColors.rsBlueLight, RsColors.rsBlue],
                  ),
                  borderRadius: BorderRadius.circular(CoolRadii.xl),
                  boxShadow: [
                    BoxShadow(
                      color: RsColors.rsBlue.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  'RS',
                  style: context.coolText.rayonCondensed(
                    Theme.of(context).textTheme.headlineLarge,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: CoolSpace.x4),
              Text(
                'RAYON SPORTS',
                style: context.coolText.rayonCondensed(
                  Theme.of(context).textTheme.headlineMedium,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: CoolSpace.x1),
              Text(
                'VERSION 2.4.0',
                style: context.coolText.mono(
                  Theme.of(context).textTheme.labelSmall,
                  fontWeight: FontWeight.w700,
                  color: colors.secondaryText,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: CoolSpace.x6),
        const _SectionLabel(label: 'APP INFO'),
        const SizedBox(height: CoolSpace.x3),
        const _GlassCard(
          child: Column(
            children: [
              _InfoRow(
                icon: Icons.code_rounded,
                title: 'BUILD',
                value: '2026.03.27',
              ),
              _RowDivider(),
              _InfoRow(
                icon: Icons.flutter_dash_rounded,
                title: 'FRAMEWORK',
                value: 'FLUTTER',
              ),
              _RowDivider(),
              _InfoRow(
                icon: Icons.cloud_outlined,
                title: 'BACKEND',
                value: 'SUPABASE',
              ),
            ],
          ),
        ),
        const SizedBox(height: CoolSpace.x6),
        const _SectionLabel(label: 'LEGAL'),
        const SizedBox(height: CoolSpace.x3),
        _GlassCard(
          child: Column(
            children: [
              _SettingsActionRow(
                icon: Icons.description_outlined,
                title: 'TERMS OF SERVICE',
                onTap: () async {
                  final uri = Uri.parse('https://rayonsports.rw/terms');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
              const _RowDivider(),
              _SettingsActionRow(
                icon: Icons.privacy_tip_outlined,
                title: 'PRIVACY POLICY',
                onTap: () async {
                  final uri = Uri.parse('https://rayonsports.rw/privacy');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
              const _RowDivider(),
              _SettingsActionRow(
                icon: Icons.gavel_rounded,
                title: 'OPEN SOURCE',
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'Rayon Sports',
                  applicationVersion: '2.4.0',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.isLoading,
    this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool isLoading;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CoolSpace.x3),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(CoolRadii.md),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: colors.primaryText, size: 20),
          ),
          const SizedBox(width: CoolSpace.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.coolText.mono(
                    Theme.of(context).textTheme.titleSmall,
                    fontWeight: FontWeight.w800,
                    color: colors.primaryText,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: context.coolText.mono(
                    Theme.of(context).textTheme.labelSmall,
                    fontWeight: FontWeight.w600,
                    color: colors.secondaryText,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          if (isLoading)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeTrackColor: RsColors.rsBlue,
            ),
        ],
      ),
    );
  }
}

class _SettingsActionRow extends StatelessWidget {
  const _SettingsActionRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: CoolSpace.x3),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(CoolRadii.md),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: colors.primaryText, size: 20),
            ),
            const SizedBox(width: CoolSpace.x4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: context.coolText.mono(
                      Theme.of(context).textTheme.titleSmall,
                      fontWeight: FontWeight.w800,
                      color: colors.primaryText,
                      letterSpacing: 0.8,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: context.coolText.mono(
                        Theme.of(context).textTheme.labelSmall,
                        fontWeight: FontWeight.w600,
                        color: colors.secondaryText,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onTap != null)
              Icon(
                Icons.chevron_right_rounded,
                color: colors.secondaryText,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}

class _FaqItem extends StatefulWidget {
  const _FaqItem({required this.question, required this.answer});

  final String question;
  final String answer;

  @override
  State<_FaqItem> createState() => _FaqItemState();
}

class _FaqItemState extends State<_FaqItem> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;

    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: CoolSpace.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(CoolRadii.md),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.help_outline_rounded,
                    color: RsColors.rsBlue,
                    size: 20,
                  ),
                ),
                const SizedBox(width: CoolSpace.x4),
                Expanded(
                  child: Text(
                    widget.question,
                    style: context.coolText.mono(
                      Theme.of(context).textTheme.titleSmall,
                      fontWeight: FontWeight.w800,
                      color: colors.primaryText,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: colors.secondaryText,
                  size: 22,
                ),
              ],
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.only(left: 60, top: CoolSpace.x3),
                child: Text(
                  widget.answer,
                  style: context.coolText.mono(
                    Theme.of(context).textTheme.bodySmall,
                    fontWeight: FontWeight.w600,
                    color: colors.secondaryText,
                    height: 1.6,
                  ),
                ),
              ),
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
          ],
        ),
      ),
    );
  }
}
