import 'dart:convert';
import 'dart:io';
import 'dart:ui' show SemanticsAction;

import 'package:collect_app/admin/core/admin_operational_health.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _actual() {
  final fixture =
      jsonDecode(
            File(
              'test/fixtures/admin_operational_health148.json',
            ).readAsStringSync(),
          )
          as Map;
  return Map<String, dynamic>.from(fixture['receipt'] as Map);
}

Map<String, dynamic> _alert(Map<String, dynamic> data, String code) =>
    (data['alerts'] as List).cast<Map<String, dynamic>>().singleWhere(
      (alert) => alert['code'] == code,
    );

void main() {
  test(
    'actual installed SQL receipt retains missing measurements and limits',
    () {
      final health = AdminOperationalHealth.parse(_actual());
      expect(health.metrics.length, 31);
      expect(health.alerts.length, 13);
      expect(health.status, 'unknown');
      expect(health.metrics['receipt_telemetry_age_seconds'], isNull);
      expect(health.alerts['receipt_telemetry_stale'], 'unknown');
      expect(health.metrics['push_due'], 0);
      expect(health.alerts['push_scheduler_stale'], 'not_applicable');
      expect(health.schedulerState, 'disabled');
      expect(() => health.metrics['push_due'] = 1, throwsUnsupportedError);
      expect(() => health.alerts.clear(), throwsUnsupportedError);
    },
  );

  test('one actual queue work item requires a measured scheduler', () {
    final data = _actual();
    (data['metrics'] as Map)['push_due'] = 1;
    _alert(data, 'push_queue_age')['state'] = 'unknown';
    _alert(data, 'push_scheduler_stale')['state'] = 'unknown';
    final health = AdminOperationalHealth.parse(data);
    expect(health.alerts['push_scheduler_stale'], 'unknown');
    expect(health.alerts['push_queue_age'], 'unknown');
    expect(health.status, 'unknown');
  });

  test(
    'backlog boundary is inclusive and attention outranks missing telemetry',
    () {
      final data = _actual();
      final metrics = data['metrics'] as Map;
      metrics['sms_pending'] = 99;
      data['parser_pending_sms'] = 99;
      expect(AdminOperationalHealth.parse(data).status, 'unknown');
      metrics['sms_pending'] = 100;
      data['parser_pending_sms'] = 100;
      _alert(data, 'receipt_parse_backlog')['state'] = 'attention';
      data['health_status'] = 'attention';
      expect(AdminOperationalHealth.parse(data).status, 'attention');
      _alert(data, 'receipt_parse_backlog')['state'] = 'ok';
      expect(() => AdminOperationalHealth.parse(data), throwsFormatException);
    },
  );

  test(
    'exact freshness boundary and future clock do not imply healthy data',
    () {
      final health = AdminOperationalHealth.parse(_actual());
      expect(health.isFresh(health.checkedAt), isTrue);
      expect(
        health.isFresh(health.checkedAt.subtract(const Duration(seconds: 5))),
        isTrue,
      );
      expect(
        health.isFresh(health.checkedAt.subtract(const Duration(seconds: 6))),
        isFalse,
      );
      expect(
        health.isFresh(
          health.validUntil.subtract(const Duration(microseconds: 1)),
        ),
        isTrue,
      );
      expect(health.isFresh(health.validUntil), isFalse);
    },
  );

  final corruptions = <String, void Function(Map<String, dynamic>)>{
    'extra private diagnostic': (d) => d['provider_error'] = 'PRIVATE_CANARY',
    'missing required measurement': (d) =>
        (d['metrics'] as Map).remove('push_due'),
    'unrecognized measurement': (d) =>
        (d['metrics'] as Map)['private_canary'] = 1,
    'null count': (d) => (d['metrics'] as Map)['push_due'] = null,
    'decimal count': (d) => (d['metrics'] as Map)['push_due'] = 0.0,
    'string count': (d) => (d['metrics'] as Map)['push_due'] = '0',
    'negative count': (d) => (d['metrics'] as Map)['push_due'] = -1,
    'unsafe integer': (d) =>
        (d['metrics'] as Map)['push_due'] = 9007199254740992,
    'decimal contract': (d) => d['contract_version'] = 1.0,
    'decimal window': (d) => d['window_seconds'] = 86400.0,
    'decimal threshold version': (d) => d['threshold_version'] = 1.0,
    'wrong contract': (d) => d['contract_version'] = 2,
    'decimal alias': (d) => d['parser_pending_sms'] = 1.0,
    'inconsistent alias': (d) => d['parser_pending_sms'] = 999,
    'calendar normalization': (d) => d['checked_at'] = '2026-02-30T12:00:00Z',
    'missing timezone': (d) => d['checked_at'] = '2026-09-30T12:00:00',
    'unbounded TTL': (d) => d['sample_valid_until'] = '2099-01-01T00:00:00Z',
    'unknown alert': (d) =>
        _alert(d, 'push_queue_age')['code'] = 'PRIVATE_CANARY',
    'duplicate alert': (d) =>
        (d['alerts'] as List)[0] = (d['alerts'] as List)[1],
    'missing alert': (d) => (d['alerts'] as List).removeLast(),
    'wrong alert metric': (d) =>
        _alert(d, 'push_queue_age')['metric'] = 'push_failed',
    'decimal alert threshold': (d) =>
        _alert(d, 'push_queue_age')['threshold'] = 120.0,
    'weakened alert threshold': (d) =>
        _alert(d, 'push_queue_age')['threshold'] = 121,
    'fabricated measured zero': (d) =>
        _alert(d, 'receipt_telemetry_stale')['state'] = 'ok',
    'fabricated overall healthy': (d) => d['health_status'] = 'ok',
    'fabricated configuration': (d) =>
        (d['scheduler'] as Map)['configuration_verified'] = true,
    'unbounded scheduler details': (d) =>
        (d['scheduler'] as Map)['provider'] = 'PRIVATE_CANARY',
    'unsupported scheduler state': (d) =>
        (d['scheduler'] as Map)['state'] = 'healthy',
    'missing evidence limit': (d) =>
        (d['evidence_limits'] as List).removeLast(),
    'injected evidence text': (d) =>
        (d['evidence_limits'] as List)[0] = 'PRIVATE_CANARY',
  };
  for (final entry in corruptions.entries) {
    test('rejects ${entry.key} without reflecting supplied data', () {
      final data = _actual();
      entry.value(data);
      Object? failure;
      try {
        AdminOperationalHealth.parse(data);
      } catch (error) {
        failure = error;
      }
      expect(failure, isA<FormatException>());
      expect(failure.toString(), isNot(contains('PRIVATE_CANARY')));
      expect(
        failure.toString(),
        contains('Health sample could not be validated'),
      );
    });
  }

  Future<void> mount(
    WidgetTester tester,
    Map<String, dynamic> data, {
    required DateTime Function() clock,
    required VoidCallback refresh,
    double scale = 1,
  }) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: CollectTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AdminOperationalHealthPanel(
              data: data,
              clock: clock,
              onRefresh: refresh,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  }

  testWidgets('invalid receipt is redacted, refreshable, and never healthy', (
    tester,
  ) async {
    final data = _actual()..['provider_error'] = 'PRIVATE_CANARY';
    var refreshes = 0;
    await mount(tester, data, clock: DateTime.now, refresh: () => refreshes++);
    expect(find.text('Health unavailable'), findsOneWidget);
    expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
    expect(find.text('Measurements'), findsNothing);
    await tester.ensureVisible(find.text('Refresh health'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refresh health').hitTestable());
    expect(refreshes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fresh missing telemetry stays unknown; no automatic fetch', (
    tester,
  ) async {
    final data = _actual();
    var now = AdminOperationalHealth.parse(data).checkedAt;
    var refreshes = 0;
    await mount(tester, data, clock: () => now, refresh: () => refreshes++);
    expect(find.text('Measurements unavailable'), findsOneWidget);
    expect(find.text('Receipt telemetry age: Not measured'), findsOneWidget);
    expect(find.text('Notifications due: 0'), findsOneWidget);
    expect(
      find.text('ACK generation does not prove device receipt.'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 20));
    expect(refreshes, 0);
    now = now.add(const Duration(seconds: 60));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Sample expired or clock unavailable'), findsOneWidget);
    expect(find.text('Measurements'), findsNothing);
    expect(find.text('Alert checks'), findsNothing);
    expect(find.text('Notifications due: 0'), findsNothing);
    expect(find.textContaining('at sample: disabled'), findsNothing);
    expect(
      find.text('Notification schedule not verified for the current time.'),
      findsOneWidget,
    );
    expect(refreshes, 0);
    await tester.ensureVisible(find.text('Refresh health'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refresh health').hitTestable());
    expect(refreshes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('future sample hides operational values and timer disposes', (
    tester,
  ) async {
    final data = _actual();
    final now = AdminOperationalHealth.parse(
      data,
    ).checkedAt.subtract(const Duration(minutes: 1));
    var refreshes = 0;
    await mount(tester, data, clock: () => now, refresh: () => refreshes++);
    expect(find.text('Sample expired or clock unavailable'), findsOneWidget);
    expect(find.text('Measurements'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 2));
    expect(refreshes, 0);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'compact ${scale}x health is scrollable, named and keyboard operable',
      (tester) async {
        final data = _actual();
        final metrics = data['metrics'] as Map;
        metrics['sms_failed_24h'] = 1;
        data['failed_sms_parse'] = 1;
        _alert(data, 'receipt_parse_failure')['state'] = 'attention';
        data['health_status'] = 'attention';
        var refreshes = 0;
        await mount(
          tester,
          data,
          clock: () => AdminOperationalHealth.parse(data).checkedAt,
          refresh: () => refreshes++,
          scale: scale,
        );
        final semantics = tester.ensureSemantics();
        addTearDown(semantics.dispose);
        expect(find.text('Attention required'), findsOneWidget);
        expect(find.byType(InfoSecurityBanner), findsOneWidget);
        await tester.ensureVisible(find.text('Refresh health'));
        await tester.pumpAndSettle();
        expect(find.text('Refresh health').hitTestable(), findsOneWidget);
        final namedButton = tester.getSemantics(find.byType(FilledButton));
        expect(namedButton.label, 'Refresh health');
        expect(
          namedButton.getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(refreshes, 1);
        await tester.ensureVisible(
          find.text('Receipt parsing failures: Attention required'),
        );
        await tester.pumpAndSettle();
        expect(
          find
              .text('Receipt parsing failures: Attention required')
              .hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
