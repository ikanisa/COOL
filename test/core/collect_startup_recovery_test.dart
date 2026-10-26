import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:collect_app/core/logging/app_logger.dart';
import 'package:collect_app/core/startup/collect_global_error_handlers.dart';
import 'package:collect_app/core/startup/collect_startup_controller.dart';
import 'package:collect_app/core/startup/collect_startup_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CollectDiagnostics diagnostics([List<String>? events]) => CollectDiagnostics(
  surface: CollectDiagnosticSurface.member,
  environmentName: 'local',
  sink: (event) => events?.add(event),
);

class _SensitiveFailure {
  @override
  String toString() => throw StateError('Raw sensitive content was inspected');
}

void main() {
  test('diagnostics allowlist, bounded burst and sink failure', () {
    final events = <String>[];
    var elapsed = Duration.zero;
    final log = CollectDiagnostics(
      surface: CollectDiagnosticSurface.admin,
      environmentName: 'Bearer PRIVATE-SESSION',
      buildVersion: 'PRIVATE-RECEIPT',
      sink: events.add,
      elapsed: () => elapsed,
    );
    for (var i = 0; i < 100; i++) {
      log.record(CollectDiagnosticCode.frameworkFailure, attempt: -999);
    }
    expect(events, hasLength(65));
    expect(jsonDecode(events.last)['code'], 'diagnosticsSuppressed');
    expect(events.join(), isNot(contains('PRIVATE')));
    final first = jsonDecode(events.first) as Map<String, dynamic>;
    expect(first.keys.toSet(), {
      'collect_diagnostic',
      'code',
      'severity',
      'surface',
      'environment',
      'build_version',
      'attempt',
      'elapsed_ms',
    });
    expect(first['attempt'], 1);
    expect(first['severity'], 'error');
    elapsed = const Duration(minutes: 1);
    log.record(CollectDiagnosticCode.startupReady, attempt: 10000);
    expect(events, hasLength(66));
    expect(jsonDecode(events.last)['attempt'], 1000);
    expect(
      () => CollectDiagnostics(
        surface: CollectDiagnosticSurface.member,
        environmentName: 'prod',
        sink: (_) => throw _SensitiveFailure(),
      ).record(CollectDiagnosticCode.platformFailure),
      returnsNormally,
    );
  });

  testWidgets('draws loading first; null configuration can become ready', (
    tester,
  ) async {
    var calls = 0;
    final controller = CollectStartupController<String?>(
      initialize: () async {
        calls++;
        return null;
      },
      diagnostics: diagnostics(),
    );
    await tester.pumpWidget(
      CollectStartupHost<String?>(
        controller: controller,
        application: (value) =>
            const MaterialApp(home: Text('Unconfigured application')),
      ),
    );
    expect(find.text('Starting Collect'), findsOneWidget);
    expect(calls, 1);
    await tester.pump();
    expect(controller.value, isNull);
    expect(find.text('Unconfigured application'), findsOneWidget);
    controller.start();
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('deadline and repeated retries never overlap initialization', (
    tester,
  ) async {
    final pending = Completer<int>();
    var calls = 0;
    final controller = CollectStartupController<int>(
      initialize: () {
        calls++;
        return pending.future;
      },
      diagnostics: diagnostics(),
      displayDeadline: const Duration(seconds: 1),
    );
    controller.start();
    await tester.pump(const Duration(seconds: 2));
    expect(controller.stage, CollectStartupStage.failed);
    controller.retry();
    controller.retry();
    await tester.pump(const Duration(seconds: 2));
    controller.retry();
    expect(calls, 1);
    expect(controller.initializationInFlight, isTrue);
    pending.complete(7);
    await tester.pump();
    expect(controller.stage, CollectStartupStage.ready);
    expect(controller.value, 7);
    controller.dispose();
  });

  testWidgets('real rejection retries; unsafe cleanup prevents retry', (
    tester,
  ) async {
    var calls = 0;
    final controller = CollectStartupController<int>(
      initialize: () async {
        if (++calls == 1) throw _SensitiveFailure();
        throw const CollectStartupFailure(retryAllowed: false);
      },
      diagnostics: diagnostics(),
    );
    controller.start();
    await tester.pump();
    expect(controller.canRetry, isTrue);
    controller.retry();
    await tester.pump();
    expect(controller.canRetry, isFalse);
    controller.retry();
    expect(calls, 2);
    controller.dispose();
  });

  testWidgets('fatal and disposed controllers ignore late completion', (
    tester,
  ) async {
    for (final disposed in [false, true]) {
      final pending = Completer<int>();
      var notifications = 0;
      final controller = CollectStartupController<int>(
        initialize: () => pending.future,
        diagnostics: diagnostics(),
      )..addListener(() => notifications++);
      controller.start();
      if (disposed) {
        controller.dispose();
      } else {
        controller.reportApplicationFailure();
      }
      final before = notifications;
      pending.complete(8);
      await tester.pump();
      expect(notifications, before);
      if (!disposed) {
        expect(controller.stage, CollectStartupStage.failed);
        expect(controller.canRetry, isFalse);
        controller.dispose();
      }
    }
  });

  testWidgets('global faults are redacted, deferred, coalesced and restored', (
    tester,
  ) async {
    final priorFramework = FlutterError.onError;
    final priorPlatform = PlatformDispatcher.instance.onError;
    final priorWidget = ErrorWidget.builder;
    final events = <String>[];
    var faults = 0;
    final handlers = CollectGlobalErrorHandlers(
      diagnostics: diagnostics(events),
      onApplicationFault: () => faults++,
    );
    Widget? safeError;
    try {
      handlers.install();
      handlers.install();
      FlutterError.onError!(
        FlutterErrorDetails(exception: _SensitiveFailure()),
      );
      expect(
        PlatformDispatcher.instance.onError!(
          _SensitiveFailure(),
          StackTrace.current,
        ),
        isTrue,
      );
      safeError = ErrorWidget.builder(
        FlutterErrorDetails(exception: _SensitiveFailure()),
      );
      expect(faults, 0);
      await tester.pump();
      expect(faults, 1);
      expect(events.map((e) => jsonDecode(e)['code']), [
        'frameworkFailure',
        'platformFailure',
      ]);
    } finally {
      handlers.dispose();
    }
    expect(FlutterError.onError, same(priorFramework));
    expect(PlatformDispatcher.instance.onError, same(priorPlatform));
    expect(ErrorWidget.builder, same(priorWidget));
    await tester.pumpWidget(safeError);
    expect(find.text('Collect could not continue'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('disposing old handlers preserves later owners', (tester) async {
    final original = FlutterError.onError;
    final handlers = CollectGlobalErrorHandlers(diagnostics: diagnostics())
      ..install();
    void newer(FlutterErrorDetails _) {}
    FlutterError.onError = newer;
    handlers.dispose();
    expect(FlutterError.onError, same(newer));
    FlutterError.onError = original;
  });

  for (final admin in [false, true]) {
    for (final dark in [false, true]) {
      testWidgets(
        'recovery at320px,3x text, high contrast admin=$admin dark=$dark',
        (tester) async {
          tester.view.physicalSize = const Size(320, 480);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = 3;
          tester.platformDispatcher.platformBrightnessTestValue = dark
              ? Brightness.dark
              : Brightness.light;
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              const FakeAccessibilityFeatures(highContrast: true);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearAllTestValues);
          final pending = Completer<int>();
          final controller = CollectStartupController<int>(
            initialize: () => pending.future,
            diagnostics: diagnostics(),
            displayDeadline: const Duration(seconds: 1),
          );
          await tester.pumpWidget(
            CollectStartupHost<int>(
              controller: controller,
              admin: admin,
              application: (_) => const SizedBox.shrink(),
            ),
          );
          expect(tester.takeException(), isNull);
          await tester.pump(const Duration(seconds: 2));
          expect(find.text('Try again'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text('Try again'));
          await tester.tap(find.text('Try again'));
          await tester.pump();
          expect(controller.stage, CollectStartupStage.loading);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          pending.complete(1);
          await tester.pump();
        },
      );
    }
  }
}
