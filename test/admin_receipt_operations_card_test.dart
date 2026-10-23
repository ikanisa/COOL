import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_receipt_operations_checkpoint.dart';
import 'package:collect_app/admin/core/admin_receipt_operations_models.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'admin_action_session_test.dart' as auth;
import 'admin_receipt_operations_checkpoint_test.dart';
import 'support/admin_receipt_operations_fixture.dart';

const operationsOwner = AdminIdentity(
  userId: auth.actor,
  displayName: 'Synthetic policy owner',
  roles: ['platform_owner'],
  permissions: [
    'admin_users.manage',
    'notifications.manage',
    'system_health.read',
  ],
);

class _Probe {
  late CollectCloudflareClient client;
  late ProviderContainer container;
  final store = MemoryOperationsStore();
  final authority = StateProvider<Future<AdminIdentity?>>(
    (_) async => operationsOwner,
  );
  final clock = StateProvider<DateTime>(
    (_) => operationsTime.add(const Duration(seconds: 10)),
  );
  final raw = operationsPolicyFixture();
  int reads = 0;
  Completer<void>? held;
  Object? error;
  final listeners = <ProviderSubscription<Object?>>[];
  Future<void> start() async {
    client = CollectCloudflareClient(
      'https://synthetic.invalid',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/verify')) {
          final token = (jsonDecode(request.body)['token'] as String).split(
            '|',
          );
          return auth.response(auth.authReceipt(token[0], token[1]));
        }
        throw StateError('No hosted request allowed in widget tests.');
      }),
    );
    await auth.session(client, 'operations-session-a');
    container = ProviderContainer(
      overrides: [
        collectBackendClientProvider.overrideWithValue(client),
        adminIdentityProvider.overrideWith((ref) => ref.watch(authority)),
        adminClockProvider.overrideWith((ref) {
          final time = ref.watch(clock);
          return () => time;
        }),
        adminReceiptOperationsCheckpointStoreProvider.overrideWithValue(store),
        adminReceiptOperationsPolicyProvider.overrideWith((ref) async {
          reads += 1;
          if (held != null) await held!.future;
          if (error != null) throw error!;
          return AdminReceiptOperationsPolicy.parse(raw);
        }),
      ],
    );
    await container.read(adminIdentityProvider.future);
  }

  Future<void> preload() async {
    listeners.add(
      container.listen(adminReceiptOperationsPolicyProvider, (_, _) {}),
    );
    try {
      await container.read(adminReceiptOperationsPolicyProvider.future);
    } catch (_) {}
  }

  Future<void> close() async {
    if (held != null && !held!.isCompleted) held!.complete();
    for (final listener in listeners) {
      listener.close();
    }
    container.dispose();
    await client.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  late _Probe probe;
  setUp(() async {
    probe = _Probe();
    await probe.start();
  });
  tearDown(() => probe.close());
  Future<void> mount(
    WidgetTester tester, {
    double width = 1440,
    double height = 2100,
    bool dark = false,
    double scale = 1,
  }) async {
    await tester.runAsync(() async {
      probe.container.read(adminAuthSessionScopeProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.binding.setSurfaceSize(Size(width, height));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: probe.container,
        child: MaterialApp(
          theme: dark ? CollectTheme.dark() : CollectTheme.light(),
          themeAnimationDuration: Duration.zero,
          home: RepaintBoundary(
            key: const ValueKey('operations-capture'),
            child: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, height),
                  textScaler: TextScaler.linear(scale),
                ),
                child: const SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: AdminReceiptOperationsCard(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'configured controls retain actual modes and boundaries without sender proof',
    (tester) async {
      await tester.runAsync(probe.preload);
      await mount(tester);
      expect(find.text('Receipt operations policy'), findsOneWidget);
      expect(
        find.textContaining('carrier delivery or payment settlement'),
        findsOneWidget,
      );
      expect(find.text('Emergency stop set'), findsOneWidget);
      final field = tester.widget<DropdownButton<AdminReceiptOperationsMode>>(
        find.byType(DropdownButton<AdminReceiptOperationsMode>),
      );
      expect(
        field.items!.map((item) => (item.child as Text).data),
        AdminReceiptOperationsMode.values.map((m) => m.label),
      );
      expect(find.text('Collection IDs (one per line)'), findsOneWidget);
    },
  );
  for (final missing in [
    'role',
    'admin_users.manage',
    'notifications.manage',
    'system_health.read',
  ]) {
    testWidgets(
      'missing $missing hides controls and never starts a policy read',
      (tester) async {
        await tester.runAsync(() async {
          probe.container.read(probe.authority.notifier).state = Future.value(
            AdminIdentity(
              userId: auth.actor,
              displayName: 'Synthetic denied owner',
              roles: missing == 'role' ? ['admin'] : operationsOwner.roles,
              permissions: operationsOwner.permissions
                  .where((v) => v != missing)
                  .toList(),
            ),
          );
          await probe.container.read(adminIdentityProvider.future);
        });
        await mount(tester);
        expect(find.text('Emergency stop'), findsNothing);
        expect(probe.reads, 0);
      },
    );
  }
  testWidgets(
    'loading and redacted failed observations offer bounded recovery',
    (tester) async {
      probe.held = Completer<void>();
      await mount(tester);
      expect(find.text('Checking receipt operations policy…'), findsOneWidget);
      probe.error = StateError('PRIVATE_CANARY');
      await tester.runAsync(() async {
        probe.held!.complete();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();
      expect(
        find.text('Receipt operations policy could not be verified.'),
        findsOneWidget,
      );
      expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
      expect(find.text('Refresh policy'), findsOneWidget);
    },
  );
  testWidgets(
    'expired observations label emergency stop unverified and disable mutations',
    (tester) async {
      probe.container.read(probe.clock.notifier).state = operationsTime.add(
        const Duration(seconds: 60),
      );
      await tester.runAsync(probe.preload);
      await mount(tester);
      expect(find.text('Emergency stop unverified'), findsOneWidget);
      expect(find.text('Emergency stop set'), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Emergency stop'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Review and apply policy'),
            )
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets(
    'an unresolved configuration keeps its original request visible and permits only a distinct stop',
    (tester) async {
      final owner = adminReceiptOperationsOwnerDigest(auth.actor),
          intent = operationsIntent();
      final bookmark = AdminReceiptOperationsCheckpoint.fromIntent(
        owner,
        intent,
      );
      probe.store.write(owner, intent.requestId, bookmark.encode());
      await tester.runAsync(probe.preload);
      await mount(tester);
      expect(find.textContaining(operationsRequest), findsOneWidget);
      expect(find.text('Check original request'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Review and apply policy'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Emergency stop'),
            )
            .onPressed,
        isNotNull,
      );
    },
  );
  testWidgets('unknown emergency stop prevents stacking another stop UUID', (
    tester,
  ) async {
    final owner = adminReceiptOperationsOwnerDigest(auth.actor),
        intent = operationsIntent(stop: true);
    probe.store.write(
      owner,
      intent.requestId,
      AdminReceiptOperationsCheckpoint.fromIntent(owner, intent).encode(),
    );
    await tester.runAsync(probe.preload);
    await mount(tester);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Emergency stop'),
          )
          .onPressed,
      isNull,
    );
  });
  testWidgets(
    'authority loss clears the reason dialog immediately and cannot resurrect its draft',
    (tester) async {
      await tester.runAsync(probe.preload);
      await mount(tester);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Emergency stop'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'PRIVATE_REASON_CANARY',
      );
      await tester.runAsync(() async {
        probe.container.read(probe.authority.notifier).state = Future.value(
          null,
        );
        await probe.container.read(adminIdentityProvider.future);
      });
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('PRIVATE_REASON_CANARY'), findsNothing);
      await tester.runAsync(() async {
        probe.container.read(probe.authority.notifier).state = Future.value(
          operationsOwner,
        );
        await probe.container.read(adminIdentityProvider.future);
      });
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(probe.store.originals, isEmpty);
    },
  );
  testWidgets(
    'capability loss and restoration in the same session clears typed scope IDs',
    (tester) async {
      await tester.runAsync(probe.preload);
      await mount(tester);
      final principalField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Principal IDs (one per line)',
      );
      await tester.enterText(principalField, operationsPrincipal);
      await tester.runAsync(() async {
        probe.container.read(probe.authority.notifier).state = Future.value(
          null,
        );
        await probe.container.read(adminIdentityProvider.future);
      });
      await tester.pump();
      await tester.runAsync(() async {
        probe.container.read(probe.authority.notifier).state = Future.value(
          operationsOwner,
        );
        await probe.container.read(adminIdentityProvider.future);
      });
      await tester.pump();
      expect(
        tester.widget<TextField>(principalField).controller!.text,
        isEmpty,
      );
    },
  );
  for (final dark in [false, true]) {
    for (final width in [1440.0, 360.0]) {
      testWidgets(
        'theme $dark width $width reflows at enlarged text without overflow',
        (tester) async {
          await tester.runAsync(probe.preload);
          await mount(tester, width: width, height: 2200, dark: dark, scale: 2);
          expect(tester.takeException(), isNull);
          expect(find.text('Receipt operations policy'), findsOneWidget);
        },
      );
    }
  }
  testWidgets(
    'optional source-bound light/dark captures render through actual shared theme',
    (tester) async {
      final directory =
          Platform.environment['COLLECT_RECEIPT_OPERATIONS_CAPTURE_DIRECTORY'];
      if (directory == null) return;
      await tester.runAsync(probe.preload);
      for (final dark in [false, true]) {
        for (final width in [1440.0, 360.0]) {
          await mount(tester, width: width, height: 2300, dark: dark);
          await tester.pumpAndSettle();
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('operations-capture')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            image.dispose();
            await File(
              '$directory/operations-${dark ? 'dark' : 'light'}-${width.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
          });
        }
      }
      expect(tester.takeException(), isNull);
    },
  );
}
