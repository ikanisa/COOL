import 'dart:convert';
import 'dart:ui';

import 'package:collect_app/admin/core/admin_pending_attempt_store.dart';
import 'package:collect_app/admin/core/cloudflare_admin_recovery_host.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/core/logging/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cloudflare_canonical_reconciliation_support.dart';

class _SensitiveFailure {
  @override
  String toString() => throw StateError('Raw evidence must not be inspected');
}

void main() {
  for (final platform in [false, true]) {
    testWidgets(
      'cookie Admin ${platform ? 'platform' : 'framework'} failure keeps the original pending request and restores handlers',
      (tester) async {
        final originalFramework = FlutterError.onError,
            originalPlatform = PlatformDispatcher.instance.onError,
            originalWidget = ErrorWidget.builder,
            events = <String>[];
        final storage = MemoryAdminPendingAttemptStorage();
        final store = AdminPendingAttemptStore(storage: storage)
          ..bind(CloudflareAdminUser.parse(canonicalSession()));
        const schema = AdminPendingAttemptSchema(fields: {'amount_rwf'});
        store.retain(
          family: 'canonical.review',
          resourceId: 'controlled-payment',
          requestKey: 'original-pending-request',
          permission: 'reconciliations.review',
          intent: {'amount_rwf': 5000},
          schema: schema,
        );
        final persisted = Map<String, String>.from(storage.values);
        ProviderContainer? container;
        var applicationBuilds = 0;
        try {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                adminPendingAttemptStoreProvider.overrideWith((_) => store),
              ],
              child: CloudflareAdminRecoveryHost(
                diagnostics: CollectDiagnostics(
                  surface: CollectDiagnosticSurface.admin,
                  environmentName: 'local',
                  sink: events.add,
                ),
                child: Consumer(
                  builder: (context, ref, _) {
                    container = ProviderScope.containerOf(context);
                    ref.watch(adminPendingAttemptStoreProvider);
                    applicationBuilds++;
                    return const MaterialApp(home: Text('Cookie workspace'));
                  },
                ),
              ),
            ),
          );
          expect(find.text('Cookie workspace'), findsOneWidget);
          if (platform) {
            expect(
              PlatformDispatcher.instance.onError!(
                _SensitiveFailure(),
                StackTrace.current,
              ),
              isTrue,
            );
          } else {
            FlutterError.onError!(
              FlutterErrorDetails(exception: _SensitiveFailure()),
            );
          }
          // Reporting is deferred; no state is replaced within the bad frame.
          expect(find.text('Cookie workspace'), findsOneWidget);
          await tester.pump();
          await tester.pump();
          expect(find.text('Collect could not continue'), findsOneWidget);
          expect(find.text('Restart Collect and try again.'), findsOneWidget);
          expect(find.text('Try again'), findsNothing);
          expect(find.text('Cookie workspace'), findsNothing);
          expect(
            container!.read(adminPendingAttemptStoreProvider),
            same(store),
          );
          expect(
            store
                .restore(
                  family: 'canonical.review',
                  resourceId: 'controlled-payment',
                  schema: schema,
                )!
                .requestKey,
            'original-pending-request',
          );
          expect(storage.values, persisted);
          expect(applicationBuilds, 1);
          expect(events, hasLength(1));
          final event = jsonDecode(events.single) as Map<String, dynamic>;
          expect(event['surface'], 'admin');
          expect(
            event['code'],
            platform ? 'platformFailure' : 'frameworkFailure',
          );
          expect(events.single, isNot(contains('controlled-payment')));
          expect(events.single, isNot(contains('original-pending-request')));
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
        }
        expect(FlutterError.onError, same(originalFramework));
        expect(PlatformDispatcher.instance.onError, same(originalPlatform));
        expect(ErrorWidget.builder, same(originalWidget));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
