import 'package:collect_app/admin/admin_app.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Admin header exposes country and operator actions to semantics',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      final identity = await const AdminEvidenceRepository().currentIdentity();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminAuthGuardProvider.overrideWithValue(
              const AdminAuthGuard(isAuthorized: true),
            ),
            adminIdentityProvider.overrideWith((ref) async => identity),
            adminRepositoryProvider.overrideWithValue(
              const AdminEvidenceRepository(),
            ),
          ],
          child: const CollectAdminApp(),
        ),
      );
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byTooltip('Country: All countries'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Country scope: All countries')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('Operator menu')), findsOneWidget);
      for (final width in [320.0, 834.0, 1440.0]) {
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpAndSettle();
        final size = tester.getSize(find.byTooltip('Operator menu'));
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
      await tester.tap(find.byTooltip('Country: All countries'));
      await tester.pumpAndSettle();
      expect(find.text('Malta'), findsOneWidget);
      await tester.tap(find.text('Malta'));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(RegExp('Country scope: Malta')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      semantics.dispose();
    },
  );
}
