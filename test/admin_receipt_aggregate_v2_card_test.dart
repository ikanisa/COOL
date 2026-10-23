// Retained v2 component proof over actual providers/repository/Auth/HTTP.
// The production deadline/Overview consumer now uses v3; its separate cases
// require unavailable v3 evidence to remain unavailable and never revive v2.
// This test host is not a production routing adapter.
// Auth and transport are synthetic. The retained deadline list is explicitly
// adapted at the caller to that worker's ID/bindings and a fresh list clock;
// this does not establish a new SQL lifecycle or hosted authorization.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:collect_app/admin/core/admin_receipt_aggregate_v2_card.dart';
import 'package:collect_app/admin/core/admin_receipt_callback_deadline_models.dart';
import 'package:collect_app/admin/core/admin_receipt_callback_deadline_view.dart';
import 'package:collect_app/admin/core/admin_receipt_callback_deadline_runtime.dart';
import 'package:collect_app/admin/core/admin_runtime.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'callback_deadline_mount_support.dart';

const aggregateRpc = 'admin_get_receipt_aggregate_sample_v2';
Map<String, dynamic> aggregateFixture(String name) =>
    jsonDecode(
          File(
            'test/fixtures/receipt_aggregate_v2_ui/$name.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;
Map<String, dynamic> duplicate(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

Future<DeadlineMountedHarness> begin(WidgetTester tester) async {
  final h = DeadlineMountedHarness();
  await tester.runAsync(h.start);
  addTearDown(h.close);
  h.aggregateSample = aggregateFixture('sample');
  final measurement =
      (h.aggregateSample!['result'] as Map)['measurement'] as Map;
  h.execution.now = DateTime.parse(
    measurement['checked_at'] as String,
  ).add(const Duration(seconds: 1));
  final page = sqlFixture('fresh-primary-list');
  page['last_worker'] = aggregateFixture('side');
  page['checked_at'] = h.execution.now.toIso8601String();
  page['sample_valid_until'] = h.execution.now
      .add(const Duration(seconds: 60))
      .toIso8601String();
  h.primaryDeadlinePage = page;
  return h;
}

final _legacyDeadlineSource = FutureProvider.autoDispose<CallbackDeadlinePage?>(
  (ref) {
    final api = ref.watch(adminCallbackDeadlineApiProvider);
    return api?.list(CallbackDeadlineQuery());
  },
);

class _RetainedV2ComponentHost extends ConsumerStatefulWidget {
  const _RetainedV2ComponentHost();
  @override
  ConsumerState<_RetainedV2ComponentHost> createState() =>
      _RetainedV2ComponentHostState();
}

class _RetainedV2ComponentHostState
    extends ConsumerState<_RetainedV2ComponentHost> {
  Timer? _clock;
  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ref
      .watch(_legacyDeadlineSource)
      .when(
        skipLoadingOnReload: false,
        skipLoadingOnRefresh: false,
        data: (page) => AdminReceiptAggregateV2Card(source: page),
        loading: () => const Text('Loading retained v2 source'),
        error: (_, _) =>
            const Text('Retained v2 source could not be verified.'),
      );
}

Widget app(DeadlineMountedHarness h, {bool full = false, double scale = 1}) =>
    UncontrolledProviderScope(
      container: h.container,
      child: RepaintBoundary(
        key: const ValueKey('aggregate-capture'),
        child: MaterialApp(
          theme: CollectTheme.light(),
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: SingleChildScrollView(
                child: full
                    ? const AdminReceiptCallbackDeadlineCard()
                    : const _RetainedV2ComponentHost(),
              ),
            ),
          ),
        ),
      ),
    );

Future<void> capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['COLLECT_AGGREGATE_CAPTURE_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('aggregate-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(directory).createSync(recursive: true);
    await File(
      '$directory/$name.png',
    ).writeAsBytes(data!.buffer.asUint8List(), flush: true);
    image.dispose();
  });
}

void main() {
  testWidgets(
    'retained v2 component reads only the original authenticated request',
    (tester) async {
      final h = await begin(tester);
      expect(
        await tester.runAsync(
          () async => h.container.read(adminReceiptAggregateV2ApiProvider),
        ),
        isNotNull,
      );
      await tester.pumpWidget(app(h));
      await settle(tester);
      expect(find.text('Latest recorded receipt measurement'), findsOneWidget);
      expect(find.text('Unhandled business events'), findsOneWidget);
      final requests = h.calls(aggregateRpc);
      expect(requests, hasLength(1));
      expect(jsonDecode(requests.single.body), {
        'p_request_id': h.aggregateSample!['request_id'],
      });
      expect(
        requests.single.headers['authorization'],
        'Bearer ${h.client.auth.currentSession!.accessToken}',
      );
      expect(h.calls('admin_list_receipt_callback_deadlines_v1'), hasLength(1));
      expect(
        h.requests.every(
          (r) => {
            'admin_current_user',
            'admin_list_receipt_callback_deadlines_v1',
            aggregateRpc,
          }.contains(r.url.path.split('/').last),
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final width in [1440.0, 390.0]) {
    testWidgets(
      'current three-protocol screen keeps missing measurements unavailable at $width',
      (tester) async {
        final h = await begin(tester);
        tester.view.physicalSize = Size(width, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.runAsync(() async {
          await (FontLoader('Inter')..addFont(
                rootBundle.load('assets/typefaces/Inter-Variable.ttf'),
              ))
              .load();
        });
        await tester.runAsync(() async {
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        });
        await tester.pumpWidget(
          app(h, full: true, scale: width == 390 ? 1.6 : 1),
        );
        await settle(tester);
        expect(
          find.textContaining('retained legacy aggregate was not admitted'),
          findsOneWidget,
        );
        expect(
          find.text(
            'Latest recorded receipt measurement for all three send protocols',
          ),
          findsOneWidget,
        );
        expect(find.text('Authenticated callback observations'), findsNothing);
        expect(find.text('Unknown outcomes and callback gaps'), findsNothing);
        expect(find.textContaining('could not be verified'), findsOneWidget);
        expect(
          find.textContaining('does not prove carrier delivery'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await capture(tester, 'aggregate-${width.toInt()}');
        if (width == 390) {
          await tester.scrollUntilVisible(
            find.text(
              'Latest recorded receipt measurement for all three send protocols',
            ),
            650,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          await capture(tester, 'aggregate-390-callbacks');
          await tester.scrollUntilVisible(
            find.text('Refresh recorded measurement'),
            650,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          await capture(tester, 'aggregate-390-recovery');
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('actual Overview compact consumer uses v3 and never revives v2', (
    tester,
  ) async {
    final h = await begin(tester);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: h.container,
        child: MaterialApp(
          theme: CollectTheme.light(),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: AdminReceiptTelemetryCard(compact: true),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    expect(h.calls(aggregateRpc), isEmpty);
    expect(h.calls('admin_get_receipt_aggregate_sample_v3'), hasLength(1));
    expect(
      find.text(
        'Latest recorded receipt measurement for all three send protocols',
      ),
      findsOneWidget,
    );
    expect(find.text('Unhandled business events'), findsNothing);
    expect(
      find.text(
        'The recorded measurement could not be verified. Refresh and check current access.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Legacy receipt measurements could not be verified. Refresh and check current access.',
      ),
      findsOneWidget,
    );
    expect(find.text('Callback deadlines'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'expiry clears displayed metrics without advancing the retained clock',
    (tester) async {
      final h = await begin(tester);
      await tester.pumpWidget(app(h));
      await settle(tester);
      expect(find.text('Unhandled business events'), findsOneWidget);
      h.execution.now = h.execution.now.add(const Duration(seconds: 59));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Unhandled business events'), findsNothing);
      expect(find.textContaining('measurement has expired'), findsOneWidget);
      final refresh = find.widgetWithText(
        OutlinedButton,
        'Refresh recorded measurement',
      );
      await tester.ensureVisible(refresh);
      await tester.tap(refresh);
      await settle(tester);
      expect(h.calls(aggregateRpc), hasLength(2));
      expect(
        h.calls(aggregateRpc).map((r) => jsonDecode(r.body)),
        everyElement({'p_request_id': h.aggregateSample!['request_id']}),
      );
      expect(find.text('Unhandled business events'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a different worker binding cannot display an admitted sample', (
    tester,
  ) async {
    final h = await begin(tester);
    (h.aggregateSample!['result'] as Map)['configuration_revision'] = 3;
    await tester.pumpWidget(app(h));
    await settle(tester);
    expect(find.textContaining('could not be verified'), findsOneWidget);
    expect(find.text('Unhandled business events'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('missing lookup stays unavailable and never becomes zero', (
    tester,
  ) async {
    final h = await begin(tester);
    h.aggregateSample = null;
    await tester.pumpWidget(app(h));
    await settle(tester);
    expect(
      find.textContaining('no recorded measurement for both send protocols'),
      findsOneWidget,
    );
    expect(find.text('Unhandled business events'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  for (final denied in [true, false]) {
    testWidgets(
      '${denied ? 'denial' : 'timeout'} produces one read and no apparent health',
      (tester) async {
        final h = await begin(tester);
        h.aggregateDenied = denied;
        h.aggregateTimeout = !denied;
        await tester.pumpWidget(app(h));
        await settle(tester);
        expect(find.textContaining('could not be verified'), findsOneWidget);
        expect(find.text('Unhandled business events'), findsNothing);
        expect(h.calls(aggregateRpc), hasLength(1));
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('late response after role loss cannot restore measurements', (
    tester,
  ) async {
    final h = await begin(tester);
    h.aggregateEntered = Completer<void>();
    h.aggregateRelease = Completer<void>();
    await tester.pumpWidget(app(h));
    await settle(tester);
    expect(h.aggregateEntered!.isCompleted, isTrue);
    h.owner = false;
    h.container.invalidate(adminIdentityProvider);
    await tester.runAsync(() => h.container.read(adminIdentityProvider.future));
    h.aggregateRelease!.complete();
    await settle(tester);
    expect(find.text('Unhandled business events'), findsNothing);
    expect(
      find.textContaining('receipt measurement access is required'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a worker with no retained side causes no aggregate RPC', (
    tester,
  ) async {
    final h = await begin(tester);
    h.primaryDeadlinePage!['last_worker'] = null;
    await tester.pumpWidget(app(h));
    await settle(tester);
    expect(h.calls(aggregateRpc), isEmpty);
    expect(
      find.text('No worker receipt is available for this measurement.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  test('the supplied list parser retains the exact legacy side unchanged', () {
    final list = duplicate(sqlFixture('fresh-primary-list'));
    final side = aggregateFixture('side');
    list['last_worker'] = side;
    final parsed = CallbackDeadlinePage.parse(list, CallbackDeadlineQuery());
    expect(parsed.row['last_worker'], side);
    expect(
      (parsed.row['last_worker'] as Map)['aggregate_status'],
      'not_admitted',
    );
  });
}
