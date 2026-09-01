part of 'public_content.dart';

const publicWebsitePaths = <String>{
  '/',
  '/group-savings',
  '/community-groups',
  '/trust',
  '/security',
  '/privacy',
  '/account-deletion',
  '/data-deletion',
  '/terms',
};

const _publicPages = <CollectPublicPageData>[
  ..._publicMarketingPages,
  ..._publicPolicyPages,
];

class CollectPublicPageData {
  const CollectPublicPageData({
    required this.path,
    required this.navLabel,
    required this.title,
    required this.intro,
    required this.sections,
  });

  final String path;
  final String navLabel;
  final String title;
  final String intro;
  final List<CollectPublicSectionData> sections;

  bool get isPolicy =>
      path == '/privacy' ||
      path == '/account-deletion' ||
      path == '/data-deletion' ||
      path == '/terms';
}

class CollectPublicSectionData {
  const CollectPublicSectionData({
    required this.title,
    required this.body,
    required this.bullets,
  });

  final String title;
  final String body;
  final List<String> bullets;
}

CollectPublicPageData publicPageForPath(String path) {
  final normalized = path == '/security' ? '/trust' : path;
  return _publicPages.firstWhere((page) => page.path == normalized);
}

String publicSummaryLabel(CollectPublicPageData data) {
  return switch (data.path) {
    '/group-savings' => 'Rwanda MoMo and diaspora bank contributions',
    '/community-groups' => 'Groups of every kind',
    '/trust' => 'Trust and security',
    '/privacy' => 'Customer information',
    '/account-deletion' => 'Account deletion',
    '/data-deletion' => 'Data deletion',
    '/terms' => 'Service terms',
    _ => data.navLabel,
  };
}
