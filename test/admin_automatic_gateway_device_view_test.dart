import 'dart:async';

import 'package:collect_app/admin/core/admin_automatic_gateway_models.dart';
import 'package:collect_app/admin/core/admin_automatic_gateway_view.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';

import 'admin_automatic_gateway_models_test.dart' as fixtures;
import 'admin_automatic_gateway_view_test.dart' as harness;

// Actual SQL-observed fields, with a synthetic 20-scanned-row window for the
// card's fixed page size. This UI fixture is not an executed SQL observation.
Map<String, dynamic> emptyWindow() =>
    fixtures.automaticFixture('filtered-empty-directory')
      ..['limit'] = 20
      ..['scanned_count'] = 20;

Map<String, dynamic> olderWindow() {
  final data = fixtures.automaticFixture('directory-first');
  data['limit'] = 20;
  data['next_cursor'] = null;
  final row = (data['rows'] as List).single as Map<String, dynamic>;
  for (final field in ['issued_at', 'expires_at', 'updated_at']) {
    row[field] = DateTime.parse(
      row[field] as String,
    ).subtract(const Duration(seconds: 1)).toIso8601String();
  }
  return data;
}

class DeviceRepository extends AdminEvidenceRepository {
  Map<String, dynamic> current = emptyWindow();
  final older = olderWindow();
  final cursors = <AdminAutomaticDeviceCursor?>[];
  Completer<Map<String, dynamic>>? first;
  Object? error;

  @override
  Future<Map<String, dynamic>> automaticDeviceAttempts(
    String deviceId, {
    int limit = 20,
    AdminAutomaticDeviceCursor? before,
  }) async {
    cursors.add(before);
    if (error != null) throw error!;
    if (cursors.length == 1 && first != null) return first!.future;
    return before == null ? current : older;
  }
}

Future<ProviderContainer> mountDevice(
  WidgetTester tester,
  DeviceRepository repository, {
  AdminIdentity actor = harness.identity,
  harness.Sessions? sessions,
  DateTime Function()? clock,
  double width = 1440,
}) async {
  tester.view.physicalSize = Size(width, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      adminRepositoryProvider.overrideWithValue(repository),
      adminIdentityProvider.overrideWith((_) async => actor),
      adminAuthSessionScopeProvider.overrideWith(
        (_) => sessions ?? harness.Sessions(),
      ),
      adminClockProvider.overrideWithValue(
        clock ??
            () => DateTime.parse(repository.current['checked_at'] as String),
      ),
    ],
  );
  addTearDown(container.dispose);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          body: SingleChildScrollView(
            child: AdminAutomaticDeviceCard(
              deviceId: repository.current['device_id'] as String,
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/admin/sms-receipts/:id',
        builder: (_, state) => Scaffold(
          body: Text('Selected receipt ${state.pathParameters['id']}'),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: CollectTheme.light(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  for (final width in [1440.0, 390.0]) {
    testWidgets('filtered empty window advances and returns at $width', (
      tester,
    ) async {
      final repository = DeviceRepository();
      await mountDevice(tester, repository, width: width);
      expect(find.textContaining('Continue to check older evidence'), findsOne);
      await tester.tap(find.text('Older evidence'));
      await tester.pumpAndSettle();
      expect(repository.cursors, hasLength(2));
      expect(
        repository.cursors.last!.attemptId,
        (repository.current['next_cursor'] as Map)['attempt_id'],
      );
      expect(find.text('Recorded state: granted'), findsOne);
      expect(find.text('Open receipt evidence'), findsOne);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Previous evidence'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Continue to check older evidence'), findsOne);
      expect(find.text('Recorded state: granted'), findsNothing);
    });
  }

  testWidgets('device evidence requires independent health read permission', (
    tester,
  ) async {
    final repository = DeviceRepository();
    await mountDevice(
      tester,
      repository,
      actor: const AdminIdentity(
        userId: 'actor',
        displayName: 'Limited reviewer',
        roles: ['admin'],
        permissions: ['notifications.read'],
      ),
    );
    expect(repository.cursors, isEmpty);
    expect(find.text('Automatic attempt access required'), findsOne);
  });

  testWidgets('expiry hides the retained scanned cursor and rows', (
    tester,
  ) async {
    final repository = DeviceRepository();
    var now = DateTime.parse(repository.current['checked_at'] as String);
    await mountDevice(tester, repository, clock: () => now);
    now = now.add(const Duration(seconds: 60));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Automatic attempts expired'), findsOne);
    expect(find.text('Older evidence'), findsNothing);
    expect(find.text('Open receipt evidence'), findsNothing);
  });

  for (final error in [
    const CollectApiException(message: 'private backend detail', code: '42501'),
    const FormatException('private malformed observation'),
    UnsupportedError('private missing service'),
  ]) {
    testWidgets('device read ${error.runtimeType} stays redacted', (
      tester,
    ) async {
      await mountDevice(tester, DeviceRepository()..error = error);
      expect(find.textContaining('could not be authorized'), findsOne);
      expect(find.textContaining('private'), findsNothing);
      expect(find.text('Older evidence'), findsNothing);
    });
  }

  testWidgets('session replacement clears paging and ignores the old reply', (
    tester,
  ) async {
    final repository = DeviceRepository()
      ..first = Completer<Map<String, dynamic>>();
    final old = repository.current;
    final sessions = harness.Sessions();
    await mountDevice(tester, repository, sessions: sessions);
    repository.current = emptyWindow()
      ..['status'] = 'unavailable'
      ..['scanned_count'] = 0
      ..['next_cursor'] = null;
    sessions.change(2);
    await tester.pumpAndSettle();
    repository.first!.complete(old);
    await tester.pumpAndSettle();
    expect(find.text('Device unavailable'), findsOne);
    expect(find.text('Older evidence'), findsNothing);
    expect(repository.cursors, [null, null]);
  });

  testWidgets('visible attempt opens its exact retained receipt route', (
    tester,
  ) async {
    final repository = DeviceRepository()..current = olderWindow();
    await mountDevice(tester, repository);
    await tester.tap(find.text('Open receipt evidence'));
    await tester.pumpAndSettle();
    final receipt =
        ((repository.current['rows'] as List).single as Map)['receipt_id'];
    expect(find.text('Selected receipt $receipt'), findsOne);
  });
}
