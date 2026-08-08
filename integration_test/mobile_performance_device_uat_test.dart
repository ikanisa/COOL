import 'dart:convert';

import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _minimumScenarioFrames = 3;
const _minimumTotalFrames = 30;
const _frameBudget = Duration(microseconds: 16667);
const _performanceTargetId = 'mobile_performance_device_uat_v2';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'records representative Flutter frame timing across dense mobile flows',
    (tester) async {
      debugPrint('collect_perf_target:$_performanceTargetId');
      final repository = CollectRepository.fixture(
        fixtureNow: DateTime.utc(2026, 7, 25, 4),
        fixtureCollectionCount: 24,
        fixtureContributionCount: 80,
      );
      final router = createAppRouter(initialLocation: '/groups');
      final recorder = _FlutterFrameRecorder();
      addTearDown(router.dispose);
      addTearDown(recorder.dispose);

      recorder.begin('startup_first_usable_route');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appRouterProvider.overrideWithValue(router),
            collectRepositoryProvider.overrideWith((ref) => repository),
          ],
          child: const CollectApp(),
        ),
      );
      await _pumpAnimationFrames(tester, count: 30);
      await tester.pumpAndSettle();
      recorder.end();
      expect(find.text('Groups'), findsWidgets);

      await _measure(recorder, tester, 'dense_groups_scroll', () async {
        final list = find.byType(ListView).first;
        await tester.fling(list, const Offset(0, -900), 2200);
        await _pumpAnimationFrames(tester, count: 36);
        await tester.fling(list, const Offset(0, 760), 1900);
        await _pumpAnimationFrames(tester, count: 30);
      });

      await _measure(recorder, tester, 'route_transition', () async {
        router.go('/activity');
        await _pumpAnimationFrames(tester, count: 30);
      });
      expect(find.text('Activity'), findsWidgets);

      await _measure(recorder, tester, 'dense_activity_scroll', () async {
        final list = find.byType(ListView).first;
        await tester.fling(list, const Offset(0, -1100), 2400);
        await _pumpAnimationFrames(tester, count: 42);
        await tester.fling(list, const Offset(0, 920), 2100);
        await _pumpAnimationFrames(tester, count: 34);
      });

      router.go('/groups/col-church/ledger');
      await _pumpAnimationFrames(tester, count: 30);
      expect(find.byTooltip('Sort ledger'), findsOneWidget);

      await _measure(recorder, tester, 'modal_sheet_open_close', () async {
        await tester.tap(find.byTooltip('Sort ledger'));
        await _pumpAnimationFrames(tester, count: 24);
        expect(find.text('Sort ledger'), findsWidgets);
        await tester.tap(find.text('Newest').last);
        await _pumpAnimationFrames(tester, count: 24);
      });

      router.go('/groups/col-church/contribute');
      await _pumpAnimationFrames(tester, count: 30);
      expect(find.text('Review contribution'), findsOneWidget);

      await _measure(recorder, tester, 'amount_entry_rebuild', () async {
        final amountField = find.byType(TextField);
        await tester.tap(amountField);
        for (final value in ['1', '10', '100', '1,000', '10,000', '25,000']) {
          await tester.enterText(amountField, value);
          await _pumpAnimationFrames(tester, count: 5);
        }
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await _pumpAnimationFrames(tester, count: 8);
      });

      final totalFrames = recorder.summaries.fold<int>(
        0,
        (sum, summary) => sum + summary.frameCount,
      );
      final scenarioNames = recorder.summaries
          .map((summary) => summary.name)
          .toSet();
      expect(
        scenarioNames,
        containsAll(const {
          'startup_first_usable_route',
          'dense_groups_scroll',
          'route_transition',
          'dense_activity_scroll',
          'modal_sheet_open_close',
          'amount_entry_rebuild',
        }),
      );
      expect(
        totalFrames,
        greaterThanOrEqualTo(_minimumTotalFrames),
        reason: 'Flutter engine frame sample must be representative.',
      );
      debugPrint(
        'collect_perf_complete:${jsonEncode({'scenario_count': recorder.summaries.length, 'total_frames': totalFrames, 'minimum_total_frames': _minimumTotalFrames})}',
      );
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

Future<void> _measure(
  _FlutterFrameRecorder recorder,
  WidgetTester tester,
  String name,
  Future<void> Function() action,
) async {
  await tester.pumpAndSettle();
  recorder.begin(name);
  await action();
  await tester.pumpAndSettle();
  recorder.end();
}

Future<void> _pumpAnimationFrames(
  WidgetTester tester, {
  required int count,
}) async {
  for (var index = 0; index < count; index += 1) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

class _FlutterFrameRecorder {
  _FlutterFrameRecorder() {
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  final List<FrameTiming> _activeFrames = [];
  final List<_FrameSummary> summaries = [];
  String? _activeScenario;

  void _onTimings(List<FrameTiming> timings) {
    if (_activeScenario != null) {
      _activeFrames.addAll(timings);
    }
  }

  void begin(String name) {
    if (_activeScenario != null) {
      throw StateError('Performance scenario already active.');
    }
    _activeFrames.clear();
    _activeScenario = name;
  }

  void end() {
    final name = _activeScenario;
    if (name == null) {
      throw StateError('No performance scenario is active.');
    }
    final summary = _FrameSummary.fromTimings(name, _activeFrames);
    summaries.add(summary);
    debugPrint('collect_perf_metric:${jsonEncode(summary.toJson())}');
    expect(
      summary.frameCount,
      greaterThanOrEqualTo(_minimumScenarioFrames),
      reason: '$name must emit a measurable Flutter engine frame sample.',
    );
    _activeScenario = null;
    _activeFrames.clear();
  }

  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
  }
}

class _FrameSummary {
  const _FrameSummary({
    required this.name,
    required this.frameCount,
    required this.buildP50Ms,
    required this.buildP90Ms,
    required this.rasterP50Ms,
    required this.rasterP90Ms,
    required this.totalP90Ms,
    required this.totalP99Ms,
    required this.framesOverBudget,
    required this.uiFramesOverBudget,
    required this.rasterFramesOverBudget,
    required this.totalSpanFramesOverBudget,
  });

  factory _FrameSummary.fromTimings(String name, List<FrameTiming> timings) {
    final build = timings
        .map((timing) => timing.buildDuration.inMicroseconds / 1000)
        .toList(growable: false);
    final raster = timings
        .map((timing) => timing.rasterDuration.inMicroseconds / 1000)
        .toList(growable: false);
    final total = timings
        .map((timing) => timing.totalSpan.inMicroseconds / 1000)
        .toList(growable: false);
    return _FrameSummary(
      name: name,
      frameCount: timings.length,
      buildP50Ms: _percentile(build, 0.50),
      buildP90Ms: _percentile(build, 0.90),
      rasterP50Ms: _percentile(raster, 0.50),
      rasterP90Ms: _percentile(raster, 0.90),
      totalP90Ms: _percentile(total, 0.90),
      totalP99Ms: _percentile(total, 0.99),
      framesOverBudget: timings
          .where(
            (timing) =>
                timing.buildDuration > _frameBudget ||
                timing.rasterDuration > _frameBudget,
          )
          .length,
      uiFramesOverBudget: timings
          .where((timing) => timing.buildDuration > _frameBudget)
          .length,
      rasterFramesOverBudget: timings
          .where((timing) => timing.rasterDuration > _frameBudget)
          .length,
      totalSpanFramesOverBudget: timings
          .where((timing) => timing.totalSpan > _frameBudget)
          .length,
    );
  }

  final String name;
  final int frameCount;
  final double buildP50Ms;
  final double buildP90Ms;
  final double rasterP50Ms;
  final double rasterP90Ms;
  final double totalP90Ms;
  final double totalP99Ms;
  final int framesOverBudget;
  final int uiFramesOverBudget;
  final int rasterFramesOverBudget;
  final int totalSpanFramesOverBudget;

  Map<String, Object> toJson() {
    return {
      'scenario': name,
      'frames': frameCount,
      'build_p50_ms': buildP50Ms,
      'build_p90_ms': buildP90Ms,
      'raster_p50_ms': rasterP50Ms,
      'raster_p90_ms': rasterP90Ms,
      'total_p90_ms': totalP90Ms,
      'total_p99_ms': totalP99Ms,
      'frame_budget_ms': _frameBudget.inMicroseconds / 1000,
      'frames_over_budget': framesOverBudget,
      'ui_frames_over_budget': uiFramesOverBudget,
      'raster_frames_over_budget': rasterFramesOverBudget,
      'total_span_frames_over_budget': totalSpanFramesOverBudget,
    };
  }
}

double _percentile(List<double> values, double percentile) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final index = ((sorted.length - 1) * percentile).round();
  return double.parse(sorted[index].toStringAsFixed(3));
}
