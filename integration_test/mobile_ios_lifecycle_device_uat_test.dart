import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/collect_theme_controller.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'physical iOS background and foreground preserve contribution review',
    (tester) async {
      final lifecycle = _LifecycleRecorder();
      WidgetsBinding.instance.addObserver(lifecycle);
      addTearDown(() => WidgetsBinding.instance.removeObserver(lifecycle));

      final router = createAppRouter(
        initialLocation: '/groups/col-church/contribute',
      );
      final container = ProviderContainer(
        overrides: [
          appRouterProvider.overrideWithValue(router),
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
      );
      addTearDown(router.dispose);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const CollectApp(),
        ),
      );
      await _pumpFrames(tester);

      expect(
        router.routeInformationProvider.value.uri.path,
        '/groups/col-church/contribute',
      );
      expect(find.text('Review contribution'), findsWidgets);
      await tester.enterText(find.byType(TextField).first, '12345');
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Review contribution'),
      );
      await _pumpFrames(tester);
      expect(find.textContaining('12,345'), findsOneWidget);
      expect(find.text('Edit amount'), findsWidgets);

      _mark('ready-for-background');
      await _pumpUntil(
        tester,
        lifecycle.hasBackgroundThenResume,
        timeout: const Duration(seconds: 90),
      );

      expect(lifecycle.hasBackgroundThenResume(), isTrue);
      _mark('ordered-transition:${lifecycle.serializedStates}');
      expect(
        router.routeInformationProvider.value.uri.path,
        '/groups/col-church/contribute',
      );
      expect(find.textContaining('12,345'), findsOneWidget);
      expect(find.text('Edit amount'), findsWidgets);
      expect(find.text('Contribute with MoMo'), findsOneWidget);
      expect(tester.takeException(), isNull);
      _mark('contribution-review-preserved');
      _mark('pass');
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

class _LifecycleRecorder with WidgetsBindingObserver {
  final List<AppLifecycleState> _states = <AppLifecycleState>[];

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _states.add(state);
    _mark('state:${state.name}');
  }

  bool hasBackgroundThenResume() {
    final backgroundIndex = _states.indexWhere(
      (state) =>
          state == AppLifecycleState.inactive ||
          state == AppLifecycleState.hidden ||
          state == AppLifecycleState.paused,
    );
    if (backgroundIndex < 0) return false;
    return _states
        .skip(backgroundIndex + 1)
        .contains(AppLifecycleState.resumed);
  }

  String get serializedStates => _states.map((state) => state.name).join(',');
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var index = 0; index < 14; index += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await tester.pump();
  }
  if (predicate()) return;
  fail('Timed out waiting for a physical iOS background/resume transition.');
}

void _mark(String marker) {
  // ignore: avoid_print
  print('collect_ios_lifecycle_uat:$marker');
}
