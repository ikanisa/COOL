part of 'public_content.dart';

const publicWebsitePaths = <String>{
  '/',
  '/group-savings',
  '/diaspora',
  '/insurance',
  '/craas',
  '/community-groups',
  '/our-partners',
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
    required this.mediaRole,
    required this.metricA,
    required this.metricALabel,
    required this.metricB,
    required this.metricBLabel,
    required this.sections,
  });

  final String path;
  final String navLabel;
  final String title;
  final String intro;
  final CollectPublicMediaRole mediaRole;
  final String metricA;
  final String metricALabel;
  final String metricB;
  final String metricBLabel;
  final List<CollectPublicSectionData> sections;

  bool get isPolicy => path == '/privacy' || path == '/terms';
}

enum CollectPublicMediaRole { group, payment, share }

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
  switch (data.path) {
    case '/group-savings':
      return 'Ibimina operating model';
    case '/diaspora':
      return 'Diaspora group records';
    case '/insurance':
      return 'Protection layer';
    case '/craas':
      return 'Credit-readiness service';
    case '/community-groups':
      return 'Mobile group operations';
    case '/our-partners':
      return 'Banking opportunity';
    case '/trust':
    case '/security':
      return 'Trust and security';
    case '/privacy':
      return 'Customer information';
    case '/account-deletion':
      return 'Account deletion';
    case '/data-deletion':
      return 'Data deletion';
    case '/terms':
      return 'Service terms';
  }
  return data.navLabel;
}
