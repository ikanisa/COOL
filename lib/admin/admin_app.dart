import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/theme/app_theme.dart';
import 'admin_router.dart';
import 'core/admin_error_boundary.dart';

class CollectAdminApp extends ConsumerWidget {
  const CollectAdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AdminErrorBoundary(
      child: MaterialApp.router(
        title: 'Collect Admin',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        routerConfig: ref.watch(adminRouterProvider),
      ),
    );
  }
}
