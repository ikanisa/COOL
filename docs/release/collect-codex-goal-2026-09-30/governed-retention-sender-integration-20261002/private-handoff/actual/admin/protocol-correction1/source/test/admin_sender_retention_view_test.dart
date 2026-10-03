import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_models.dart';
import 'package:collect_app/admin/core/admin_runtime.dart';
import 'package:collect_app/admin/core/admin_gateway_models.dart';
import 'package:collect_app/admin/core/admin_sender_picker.dart';
import 'package:collect_app/admin/core/admin_sender_retention_models.dart';
import 'package:collect_app/admin/core/admin_sender_retention_view.dart';
import 'package:collect_app/admin/core/admin_sender_retention_host.dart';
import 'support/retention_fixture.dart';
import 'support/retention_api_fixture.dart';

Widget view(Api api, Store store, {double scale = 1}) => MaterialApp(
  theme: CollectTheme.light(),
  home: RepaintBoundary(
    key: const ValueKey('retention-capture'),
    child: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: SingleChildScrollView(
          child: AdminSenderRetentionView(controller: control(api, store)),
        ),
      ),
    ),
  ),
);

class SessionFixture extends AdminSessionController {
  SessionFixture() : super(null) {
    state = (key: (userId: actor, sessionId: session), generation: 1);
  }
}

class RepositoryFixture extends AdminRepository {
  RepositoryFixture() : super(null);
  final calls = <String>[];
  @override
  Future<Map<String, dynamic>> rpcMap(
    String name, {
    Map<String, dynamic>? params,
    bool automaticRetry = true,
  }) async {
    expect(automaticRetry, isFalse);
    calls.add(name);
    return decoded(readInitialRaw);
  }
}

void main() {
  testWidgets(
    'actual-font compact and wide labelled maintenance states and captures',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.runAsync(() async {
        await (FontLoader('Inter')
              ..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf')))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      });
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final width in [1440.0, 390.0]) {
        tester.view.physicalSize = Size(width, 1000);
        final api = Api(), store = Store(), c = control(api, store);
        await tester.pumpWidget(
          MaterialApp(
            theme: CollectTheme.light(),
            home: RepaintBoundary(
              key: const ValueKey('retention-capture'),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: AdminSenderRetentionView(controller: c),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          tester
              .getSemantics(find.text('Evidence retention'))
              .flagsCollection
              .isHeader,
          isTrue,
        );
        expect(
          find.text('Release-declared · runtime observation unavailable'),
          findsNWidgets(2),
        );
        expect(find.text('Record maintenance change'), findsOneWidget);
        expect(find.text('Send'), findsNothing);
        expect(tester.takeException(), isNull);
        final b = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('retention-capture')),
        );
        await tester.runAsync(() async {
          final image = await b.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          Directory('captures').createSync();
          File(
            'captures/retention-${width.toInt()}.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      }
      semantics.dispose();
    },
  );
  testWidgets(
    'enlarged compact keyboard refresh and meaningful labels remain usable',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = control(Api(), Store());
      await tester.pumpWidget(
        MaterialApp(
          theme: CollectTheme.light(),
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: SingleChildScrollView(
                child: AdminSenderRetentionView(controller: c),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Batch limit'), findsOneWidget);
      expect(find.text('Byte limit'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(FocusManager.instance.primaryFocus, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets(
    'valid read without manage preserves observed evidence but disables action',
    (tester) async {
      final api = Api()
            ..snapshot = AdminRetentionSnapshot.parse(
              decoded(readNoManageRaw),
              actor,
              session,
            ),
          c = control(api, Store());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdminSenderRetentionView(controller: c),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Record maintenance change'),
            )
            .onPressed,
        isNull,
      );
      expect(find.textContaining('Settings manage permission'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets(
    'host uses exact owner floor and existing no-retry rpc consumer',
    (tester) async {
      final repo = RepositoryFixture();
      Widget mounted(Set<String> permissions) => ProviderScope(
        overrides: [
          adminAuthSessionScopeProvider.overrideWith((_) => SessionFixture()),
          adminRepositoryProvider.overrideWithValue(repo),
          adminIdentityProvider.overrideWith(
            (_) async => AdminIdentity(
              userId: actor,
              displayName: 'Synthetic owner',
              roles: const ['platform_owner'],
              permissions: permissions.toList(),
            ),
          ),
          adminClockProvider.overrideWithValue(() => fixtureNow),
          adminRetentionStoreProvider.overrideWithValue(Store()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: AdminSenderRetentionHost()),
          ),
        ),
      );
      await tester.pumpWidget(
        mounted({
          'admin_users.manage',
          'notifications.manage',
          'system_health.read',
          'settings.read',
        }),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(repo.calls, ['admin_get_receipt_retention_controls_v1']);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        mounted({
          'notifications.manage',
          'system_health.read',
          'settings.read',
        }),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Current email-owner access'), findsOneWidget);
      expect(repo.calls.length, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'finite sender page resolves real active identity and keeps unresolved IDs blocked',
    (tester) async {
      final s = AdminGatewaySnapshot.parse(decoded(gatewayActiveRaw)),
          active = s.rows.firstWhere((v) => v.state.name == 'active'),
          missing = '11111111-1111-4111-8111-111111111111';
      var changes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdminSenderPicker(
                deviceIds: [active.identity.deviceId, missing],
                snapshot: s,
                now: s.checkedAt,
                enabled: true,
                onChanged: (_) => changes++,
              ),
            ),
          ),
        ),
      );
      expect(
        find.textContaining('Installation ${active.identity.installationId}'),
        findsOneWidget,
      );
      expect(find.textContaining('Standby · $missing'), findsOneWidget);
      expect(
        find.textContaining('Unavailable in this finite gateway page'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>),
            )
            .onChanged,
        isNull,
      );
      expect(changes, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'primary selector reorders only allowed IDs preserving standby membership',
    (tester) async {
      final r = decoded(gatewayActiveRaw),
          first = Map<String, dynamic>.from(
            (r['rows'] as List).firstWhere((x) => x['state'] == 'active')
                as Map,
          );
      final second = Map<String, dynamic>.from(first);
      second['device_id'] = '11111111-1111-4111-8111-111111111111';
      second['installation_id'] = '22222222-2222-4222-8222-222222222222';
      second['key_sha256'] = 'e' * 64;
      second['enrolled_at'] = retentionUtc(
        DateTime.parse(
          first['enrolled_at'] as String,
        ).subtract(const Duration(seconds: 1)),
      );
      second['last_owner_action'] = null;
      r['rows'] = [first, second];
      r['total'] = 2;
      final s = AdminGatewaySnapshot.parse(r);
      List<String>? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdminSenderPicker(
                deviceIds: [
                  first['device_id'] as String,
                  second['device_id'] as String,
                ],
                snapshot: s,
                now: s.checkedAt,
                enabled: true,
                onChanged: (v) => picked = v,
              ),
            ),
          ),
        ),
      );
      final dropdown = tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>),
      );
      dropdown.onChanged!(second['device_id'] as String);
      expect(picked, [second['device_id'], first['device_id']]);
      expect(picked!.toSet(), {first['device_id'], second['device_id']});
    },
  );
}
