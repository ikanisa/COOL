part of 'collect_landing_page.dart';

class CollectPublicPage extends StatelessWidget {
  const CollectPublicPage({required this.data, super.key});

  final CollectPublicPageData data;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CollectColors.brandPaper,
      body: SelectionArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _PublicPageHero(data: data)),
            SliverToBoxAdapter(child: _PublicPageSummary(data: data)),
            if (!data.isPolicy)
              SliverToBoxAdapter(child: _PublicPageInfographic(data: data)),
            SliverToBoxAdapter(child: _PublicPageSections(data: data)),
            if (!data.isPolicy)
              const SliverToBoxAdapter(child: _CustomerActionSection()),
            const SliverToBoxAdapter(child: _LandingFooter()),
          ],
        ),
      ),
    );
  }
}
