import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'group link and QR open the native Android share surface',
    (tester) async {
      final router = createAppRouter(
        initialLocation: '/groups/col-church/share',
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appRouterProvider.overrideWithValue(router),
            collectRepositoryProvider.overrideWith(
              (ref) => CollectRepository.fixture(),
            ),
          ],
          child: const CollectApp(),
        ),
      );
      await _pumpLaunchFrames(tester);

      expect(find.text('Share group'), findsOneWidget);
      expect(find.text('Share link'), findsOneWidget);
      expect(find.text('Share QR code'), findsOneWidget);

      debugPrint('collect_native_share_ready:link');
      await tester.tap(find.text('Share link'));
      await Future<void>.delayed(const Duration(seconds: 20));
      await tester.pump();
      expect(find.text('Share group'), findsOneWidget);
      debugPrint('collect_native_share_complete:link');

      debugPrint('collect_native_share_ready:qr');
      await tester.tap(find.text('Share QR code'));
      await Future<void>.delayed(const Duration(seconds: 25));
      await tester.pump();
      expect(find.text('Share group'), findsOneWidget);
      debugPrint('collect_native_share_complete:qr');

      router.go('/home');
      await _pumpLaunchFrames(tester);
      expect(find.text('Share'), findsOneWidget);
      debugPrint('collect_native_share_ready:app');
      await tester.tap(find.text('Share'));
      await Future<void>.delayed(const Duration(seconds: 20));
      await tester.pump();
      expect(find.text('Share'), findsOneWidget);
      debugPrint('collect_native_share_complete:app');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<void> _pumpLaunchFrames(WidgetTester tester) async {
  for (var index = 0; index < 16; index += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
