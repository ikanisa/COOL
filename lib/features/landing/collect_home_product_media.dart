part of 'collect_landing_page.dart';

class _ProductMediaSection extends StatelessWidget {
  const _ProductMediaSection();

  @override
  Widget build(BuildContext context) {
    return _SectionBand(
      background: CollectColors.publicWhite,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 900;
          const content = _SectionIntro(
            title: 'The product surface is more than group collections',
            body:
                'Collect helps customers turn group activity into records they can understand and use.',
          );
          const media = _MediaProofVisual();
          if (compact) {
            return const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [content, SizedBox(height: 28), media],
            );
          }
          return const Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 7, child: media),
              SizedBox(width: 56),
              Expanded(flex: 6, child: content),
            ],
          );
        },
      ),
    );
  }
}
