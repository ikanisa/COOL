// Store capture only: actual app/router/widgets with explicitly synthetic data.
// This entry point is excluded from production builds and requires dev/debug.
// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';

import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/collect_theme_controller.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../test/fixtures/collect_repository_fixture.dart';

void main() {
  if (!kDebugMode ||
      kIsWeb ||
      appFlavor != 'dev' ||
      !const bool.fromEnvironment('COLLECT_PLAY_STORE_CAPTURE')) {
    throw StateError(
      'Only the explicit Android dev store-capture target is allowed.',
    );
  }
  late final GoRouter router;
  final errors = <String>[];
  const routes = {
    '01-home': '/home',
    '02-groups': '/groups',
    '03-featured-groups': '/groups?filter=featured',
    '04-group': '/groups/qa-private-group',
    '05-contribute': '/groups/qa-private-group/contribute',
    '06-activity': '/activity',
  };
  enableFlutterDriverExtension(
    handler: (command) async {
      final route = routes[command];
      if (route == null) throw ArgumentError('Unknown screenshot route');
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      router.go(route);
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      final texts = <String>[];
      void visit(Element element) {
        if (element.widget case Text(:final data)) {
          if (data != null) texts.add(data);
        }
        element.visitChildren(visit);
      }

      WidgetsBinding.instance.rootElement?.visitChildren(visit);
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      return jsonEncode({
        'route': router.routeInformationProvider.value.uri.toString(),
        'logical_width': view.physicalSize.width / view.devicePixelRatio,
        'logical_height': view.physicalSize.height / view.devicePixelRatio,
        'errors': errors,
        'texts': texts,
        'data_source': 'synthetic_store_fixture',
      });
    },
  );
  final seed = FixtureCollectRepository(
    fixtureNow: DateTime.utc(2026, 9, 6, 12),
  );
  final state = seed.state;
  seed.dispose();
  final repository = CollectRepository.fixture(
    initialState: state.copyWith(
      collections: [
        for (final group in state.collections)
          if (group.id == 'qa-private-group')
            group.copyWith(
              title: 'Kigali savings circle',
              description: 'Saving together for our shared goals.',
              collectionType: CollectionType.ikimina,
              categorySubtype: 'group_savings',
              receiverDisplayLabel: 'Kigali savings circle',
              imageUrl: 'collect-cover:rw-01-neighbourhood-ikimina:v1',
            )
          else if (group.id == 'col-public-savings-fixture')
            group.copyWith(imageUrl: 'collect-cover:rw-41-buri-munsi:v1')
          else if (group.id == 'col-public-sport-fixture')
            group.copyWith(imageUrl: 'collect-cover:rw-42-gikundiro:v1')
          else
            group,
      ],
    ),
  );
  router = createAppRouter(initialLocation: '/home');
  final previousError = FlutterError.onError;
  FlutterError.onError = (details) {
    errors.add(details.exceptionAsString());
    previousError?.call(details);
  };
  runApp(
    ProviderScope(
      overrides: [
        collectRepositoryProvider.overrideWith((ref) => repository),
        appRouterProvider.overrideWithValue(router),
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
