import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app/theme/app_theme.dart';
import 'app/theme/collect_colors.dart';
import 'app/theme/collect_typography.dart';
import 'features/landing/collect_landing_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: CollectPublicWebsiteApp()));
}

class CollectPublicWebsiteApp extends StatelessWidget {
  const CollectPublicWebsiteApp({super.key});

  @override
  Widget build(BuildContext context) {
    final router = GoRouter(
      initialLocation: _initialPublicLocation(),
      redirect: (context, state) {
        final path = state.uri.path;
        if (path.length > 1 && path.endsWith('/')) {
          final normalized = path.substring(0, path.length - 1);
          if (publicWebsitePaths.contains(normalized)) return normalized;
        }
        return null;
      },
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const CollectLandingPage(),
        ),
        for (final path in publicWebsitePaths.where((path) => path != '/'))
          GoRoute(
            path: path,
            builder: (context, state) =>
                CollectPublicPage(data: publicPageForPath(path)),
          ),
      ],
      errorBuilder: (context, state) => const _PublicNotFoundPage(),
    );

    return MaterialApp.router(
      title: 'Collect by IKANISA',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: router,
    );
  }
}

String _initialPublicLocation() {
  final fragment = Uri.base.fragment;
  if (fragment.startsWith('/')) {
    final fragmentPath = fragment.split('?').first;
    if (publicWebsitePaths.contains(fragmentPath)) return fragmentPath;
    if (fragmentPath.length > 1 && fragmentPath.endsWith('/')) {
      final normalized = fragmentPath.substring(0, fragmentPath.length - 1);
      if (publicWebsitePaths.contains(normalized)) return normalized;
    }
  }

  final path = Uri.base.path;
  if (publicWebsitePaths.contains(path)) return path;
  if (path.length > 1 && path.endsWith('/')) {
    final normalized = path.substring(0, path.length - 1);
    if (publicWebsitePaths.contains(normalized)) return normalized;
  }
  return '/';
}

class _PublicNotFoundPage extends StatelessWidget {
  const _PublicNotFoundPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CollectColors.brandPaper,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Page not found',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: CollectColors.referenceChromeBlack,
                    fontWeight: CollectTypography.weightBold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Use the public website links to continue with Collect.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: CollectColors.inkSecondary,
                    height: CollectTypography.leadingBody,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => context.go('/'),
                  child: const Text('Go home'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
