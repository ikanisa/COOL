import 'package:app_links/app_links.dart';
import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/app/theme/collect_theme_controller.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:collect_app/shared/repositories/pending_shared_group_intent_store.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _seedMarkerKey = 'collect.evidence.interrupted_intent_seeded.v1';
const _seedSlug = 'st-michel-building-fund';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = SharedPreferencesAsync();
  final alreadySeeded = await preferences.getBool(_seedMarkerKey) ?? false;
  if (!alreadySeeded) {
    await PendingSharedGroupIntentStore().saveSlug(_seedSlug);
    await preferences.setBool(_seedMarkerKey, true);
    runApp(const _InterruptedIntentSeededApp());
    return;
  }

  final router = createAppRouter(initialLocation: '/home');
  runApp(
    ProviderScope(
      overrides: [
        appRouterProvider.overrideWithValue(router),
        collectIncomingAppLinksProvider.overrideWithValue(
          AppLinks().uriLinkStream,
        ),
        collectRepositoryProvider.overrideWith(
          (ref) => CollectRepository.fixture(),
        ),
        collectThemeModeProvider.overrideWith(
          (ref) => CollectThemeModeController(
            initialMode: ThemeMode.dark,
            loadPersistedMode: false,
          ),
        ),
      ],
      child: const CollectApp(),
    ),
  );
}

class _InterruptedIntentSeededApp extends StatelessWidget {
  const _InterruptedIntentSeededApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Collect interrupted-intent evidence',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: Scaffold(
        body: CollectGradientBackground(
          routePath: '/groups',
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(CollectSpacing.x6),
                child: Semantics(
                  liveRegion: true,
                  label: 'Interrupted intent safely retained',
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox.square(
                        dimension: 88,
                        child: Image(
                          image: AssetImage(CollectRuntimeAssets.officialLogo),
                          fit: BoxFit.contain,
                        ),
                      ),
                      CollectSpacing.gap24,
                      Text(
                        'Interrupted intent retained',
                        textAlign: TextAlign.center,
                      ),
                      CollectSpacing.gap8,
                      Text(
                        'The controlled harness can now stop this process.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
