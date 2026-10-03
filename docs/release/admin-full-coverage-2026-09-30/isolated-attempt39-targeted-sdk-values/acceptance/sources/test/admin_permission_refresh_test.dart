import 'dart:async';

import 'package:collect_app/admin/admin_shell.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/admin/shared/components/admin_loading_state.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _identity = AdminIdentity(
  userId: '00000000-0000-4000-8000-000000000001',
  displayName: 'Synthetic operator',
  roles: ['admin'],
  permissions: ['overview.read'],
);
const _protected = 'SYNTHETIC_CURRENT_ADMIN_RECORD';

class _Repository extends AdminEvidenceRepository {
  @override
  Future<AdminRuntimeConfig?> runtimeConfig() async => null;
}

void main() {
  for (final ending in ['authorized', 'revoked', 'failure']) {
    testWidgets('identity refresh hides old records until $ending resolves', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Future<AdminIdentity?> next = Future.value(_identity);
      final container = ProviderContainer(
        overrides: [
          supabaseClientProvider.overrideWithValue(null),
          adminRepositoryProvider.overrideWithValue(_Repository()),
          adminIdentityProvider.overrideWith((ref) => next),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const AdminShell(location: '/admin', child: Text(_protected)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(_protected), findsOneWidget);
      final pending = Completer<AdminIdentity?>();
      next = pending.future;
      container.invalidate(adminIdentityProvider);
      expect(container.read(adminIdentityProvider).isLoading, isTrue);
      await tester.pump();
      await tester.pump();
      expect(find.text(_protected), findsNothing);
      expect(find.byType(AdminLoadingState), findsOneWidget);
      if (ending == 'failure') {
        pending.completeError(StateError('PRIVATE_REFRESH_ERROR_CANARY'));
      } else {
        pending.complete(ending == 'authorized' ? _identity : null);
      }
      await tester.pumpAndSettle();
      expect(
        find.text(_protected),
        ending == 'authorized' ? findsOneWidget : findsNothing,
      );
      expect(find.textContaining('PRIVATE_REFRESH_ERROR_CANARY'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
