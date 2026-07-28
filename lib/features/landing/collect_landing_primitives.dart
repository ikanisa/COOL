part of 'collect_landing_page.dart';

class _SectionBand extends StatelessWidget {
  const _SectionBand({
    required this.child,
    required this.background,
    super.key,
  });

  final Widget child;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return ColoredBox(
      color: background,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 20 : 40,
          vertical: compact ? 40 : 56,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _SplitSection extends StatelessWidget {
  const _SplitSection({
    required this.title,
    required this.body,
    required this.steps,
  });

  final String title;
  final String body;
  final List<LandingStepData> steps;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 900;
        final copy = _SectionIntro(title: title, body: body);
        final rail = _StepRail(steps: steps);
        if (isCompact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [copy, const SizedBox(height: 34), rail],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(width: 340, child: copy),
            const SizedBox(width: 52),
            Expanded(child: rail),
          ],
        );
      },
    );
  }
}

class _SectionIntro extends StatelessWidget {
  const _SectionIntro({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
            color: CollectColors.referenceChromeBlack,
            fontWeight: CollectTypography.weightBold,
            height: CollectTypography.leadingDisplayRelaxed,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          body,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: CollectColors.inkSecondary,
            height: CollectTypography.leadingBody,
          ),
        ),
      ],
    );
  }
}

class _StepRail extends StatelessWidget {
  const _StepRail({required this.steps});

  final List<LandingStepData> steps;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 24,
      children: [
        for (var index = 0; index < steps.length; index += 1) ...[
          _StepTile(data: steps[index]),
          if (index < steps.length - 1)
            Icon(
              Icons.arrow_forward,
              color: CollectColors.inkMuted.withValues(alpha: 0.62),
            ),
        ],
      ],
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.data});

  final LandingStepData data;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 164,
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: data.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: data.color.withValues(alpha: 0.22)),
            ),
            child: SizedBox.square(
              dimension: 74,
              child: Icon(data.icon, color: data.color, size: 34),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            data.title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: CollectColors.referenceChromeBlack,
              fontWeight: CollectTypography.weightBold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            data.body,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: CollectColors.inkSecondary,
              height: CollectTypography.leadingFine,
            ),
          ),
        ],
      ),
    );
  }
}
