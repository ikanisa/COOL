import 'package:collect_app/admin/admin_app.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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
      final reportedErrors = <FlutterErrorDetails>[];
      final reportError = FlutterError.onError!;
      FlutterError.onError = (details) {
        reportedErrors.add(details);
        reportError(details);
      };
      addTearDown(() => FlutterError.onError = reportError);
      final semantics = tester.ensureSemantics();
      final identity = await const AdminEvidenceRepository().currentIdentity();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            collectBackendClientProvider.overrideWithValue(null),
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
      expect(
        tester.takeException(),
        isNull,
        reason: 'Initial 1440px Admin layout: ${reportedErrors.join('\n')}',
      );
      expect(find.bySemanticsLabel('Rwanda operations'), findsOneWidget);
      expect(find.byTooltip('Rwanda'), findsOneWidget);
      final operator = find.byTooltip('Operator menu');
      expect(operator, findsOneWidget);
      final operatorSemantics = tester
          .getSemantics(operator)
          .getSemanticsData();
      expect(operatorSemantics.tooltip, 'Operator menu');
      expect(operatorSemantics.hasAction(SemanticsAction.tap), isTrue);
      for (final width in [320.0, 834.0, 1440.0]) {
        reportedErrors.clear();
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '${width}px Admin layout: ${reportedErrors.join('\n')}',
        );
        final size = tester.getSize(find.byTooltip('Operator menu'));
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
      expect(find.text('Malta'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      semantics.dispose();
    },
  );
}
