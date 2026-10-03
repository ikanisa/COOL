import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_receipt_cancel_checkpoint.dart';
import 'package:collect_app/admin/core/admin_receipt_cancel_models.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_action_session_test.dart' as auth;
import 'admin_receipt_cancel_models_test.dart' as wire;

const _identity = AdminIdentity(
  userId: auth.actor,
  displayName: 'Synthetic SDK cancellation reviewer',
  roles: ['platform_owner'],
  permissions: [
    'payments.read',
    'notifications.read',
    'system_health.read',
    'notifications.manage',
  ],
);

class _NoScope extends AdminSessionController {
  _NoScope() : super(null);
}

class _Store implements AdminReceiptCancelCheckpointStore {
  final values = <String, String>{};
  @override
  String? read(String ownerDigest) => values[ownerDigest];
  @override
  void write(String ownerDigest, String encoded) =>
      values[ownerDigest] = encoded;
  @override
  void clear(String ownerDigest) => values.remove(ownerDigest);
}

String _stamp(DateTime value) => value
    .toUtc()
    .toIso8601String()
    .replaceFirstMapped(RegExp(r'\.(\d{3})Z$'), (match) => '.${match[1]}000Z');

class _Probe {
  _Probe({this.lookup = false, this.noScope = false});
  final bool lookup, noScope;
  late SupabaseClient client;
  late ProviderContainer container;
  final store = _Store();
  final inspection = wire.cancelFixture('preexisting-eligible-inspection');
  final lookupRaw = wire.cancelFixture('recorded-lookup');
  final requests = <http.Request>[];
  final entered = Completer<void>();
  Completer<void>? release, mutationRelease;
  Object? mutationError;
  String lookupStatus = 'recorded';
  AdminReceiptCancelIntent? submitted;
  bool cancellationRecorded = false;
  bool finished = false;
  int onRecorded = 0;
  AdminIdentity? freshIdentity = _identity;
  late final authority = StateProvider<Future<AdminIdentity?>>(
    (_) => Future.value(_identity),
  );
  String get target => lookup
      ? lookupRaw['request_id'] as String
      : inspection['outbox_id'] as String;
  String get readRpc => lookup
      ? 'admin_get_unstarted_receipt_action_v1'
      : 'admin_inspect_unstarted_receipt_v1';
  ProviderListenable<AsyncValue<Object?>> get provider => lookup
      ? adminReceiptCancelLookupProvider(target)
      : adminReceiptCancelInspectionProvider(target);
  Future<Object?> read() => lookup
      ? container.read(adminReceiptCancelLookupProvider(target).future)
      : container.read(adminReceiptCancelInspectionProvider(target).future);
  DateTime get now => DateTime.parse(
    inspection['checked_at'] as String,
  ).add(const Duration(seconds: 20));
  Map<String, dynamic> receipt(AdminReceiptCancelIntent intent) =>
      wire.cancelCopy(wire.cancelFixture('cancelled-action'))
        ..['request_id'] = intent.requestId
        ..['outbox_id'] = intent.outboxId
        ..['expected_revision'] = intent.revision
        ..['revision'] = intent.revision + 1
        ..['reason_code'] = intent.reason.wire
        ..['recorded_at'] = _stamp(now.subtract(const Duration(seconds: 1)));
  Map<String, dynamic> lookupReceipt(String requestId) =>
      wire.cancelCopy(lookupRaw)
        ..['request_id'] = requestId
        ..['status'] = lookupStatus
        ..['checked_at'] = _stamp(now)
        ..['sample_valid_until'] = _stamp(now.add(const Duration(seconds: 60)))
        ..['receipt'] = lookupStatus == 'recorded'
            ? submitted == null
                  ? wire.cancelCopy(
                      lookupRaw['receipt'] as Map<String, dynamic>,
                    )
                  : receipt(submitted!)
            : null;

  Future<void> start() async {
    client = SupabaseClient(
      'https://synthetic.invalid',
      'synthetic-public',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/verify')) {
          final values = (jsonDecode(request.body)['token'] as String).split(
            '|',
          );
          return auth.response(auth.authReceipt(values[0], values[1]));
        }
        if (request.url.path.endsWith('/logout')) {
          return auth.response({});
        }
        requests.add(request);
        final rpc = request.url.path.split('/').last;
        Object? payload;
        var status = 200;
        if (rpc == 'admin_current_user') {
          final identity = freshIdentity;
          payload = identity == null
              ? null
              : {
                  'user_id': identity.userId,
                  'display_name': identity.displayName,
                  'phone_masked': identity.phoneMasked,
                  'roles': identity.roles,
                  'permissions': identity.permissions,
                };
        } else if (rpc == 'admin_cancel_unstarted_receipt_v1') {
          submitted = AdminReceiptCancelIntent.fromParameters(
            jsonDecode(request.body),
          );
          final stored = store.read(adminReceiptCancelOwnerDigest(auth.actor));
          expect(
            stored,
            isNotNull,
            reason: 'Verified original intent precedes actual SDK mutation.',
          );
          expect(
            AdminReceiptCancelCheckpoint.parse(
              stored!,
              adminReceiptCancelOwnerDigest(auth.actor),
            ).intent.parameters,
            submitted!.parameters,
          );
          if (mutationRelease != null) {
            await mutationRelease!.future;
          }
          if (mutationError == 'transport') {
            throw http.ClientException('PRIVATE_TRANSPORT_CANARY');
          }
          if (mutationError == 'malformed') {
            payload = {'ok': true, 'PRIVATE_CANARY': true};
          } else if (mutationError == 'mismatch') {
            payload = receipt(submitted!)
              ..['reason_code'] = 'content_review_required';
          } else if (mutationError == 503) {
            status = 503;
            payload = {'code': 'unavailable', 'message': 'PRIVATE_CANARY'};
          } else {
            cancellationRecorded = true;
            payload = receipt(submitted!);
          }
        } else {
          if (!entered.isCompleted) {
            entered.complete();
          }
          if (release != null) {
            await release!.future;
          }
          if (rpc == 'admin_inspect_unstarted_receipt_v1') {
            payload = cancellationRecorded
                ? wire.cancelCopy(wire.cancelFixture('cancelled-inspection'))
                : wire.cancelCopy(inspection);
          } else if (rpc == 'admin_get_unstarted_receipt_action_v1') {
            payload = lookupReceipt(
              jsonDecode(request.body)['p_request_id'] as String,
            );
          } else {
            throw StateError('Unexpected SDK RPC $rpc');
          }
        }
        final response = auth.response(payload, status);
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }),
    );
    await auth.session(client, 'receipt-sdk-a');
    container = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(client),
        adminIdentityProvider.overrideWith((ref) => ref.watch(authority)),
        adminClockProvider.overrideWithValue(() => now),
        adminReceiptCancelCheckpointStoreProvider.overrideWithValue(store),
        if (noScope)
          adminAuthSessionScopeProvider.overrideWith((_) => _NoScope()),
      ],
    );
  }

  Future<void> finish() async {
    if (finished) {
      return;
    }
    finished = true;
    for (final gate in [release, mutationRelease]) {
      if (gate != null && !gate.isCompleted) {
        gate.complete();
      }
    }
    container.dispose();
    await client.dispose();
  }

  AdminIdentity denied(String condition) => AdminIdentity(
    userId: condition == 'unrelated identity' ? auth.target : auth.actor,
    displayName: 'Synthetic authority departure',
    roles: condition == 'role loss' ? ['admin'] : _identity.roles,
    permissions: _identity.permissions
        .where((value) => value != condition)
        .toList(),
  );
  List<http.Request> get mutations => requests
      .where((r) => r.url.path.endsWith('/admin_cancel_unstarted_receipt_v1'))
      .toList();
}

Future<void> _drain(WidgetTester tester, bool Function() ready) async {
  for (var index = 0; index < 40 && !ready(); index++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(ready(), isTrue, reason: 'Bounded actual SDK/UI completion');
}

Future<void> _mount(WidgetTester tester, _Probe probe) async {
  // Initialize actual session expiry and SDK providers in the real event loop.
  late ProviderSubscription<AsyncValue<Object?>> keep;
  await tester.runAsync(() async {
    keep = probe.container.listen(probe.provider, (_, _) {});
    await probe.read();
  });
  addTearDown(keep.close);
  tester.view.physicalSize = const Size(1440, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: probe.container,
      child: MaterialApp(
        theme: CollectTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AdminReceiptCancelCard(
              outboxId: probe.inspection['outbox_id'] as String,
              onRecorded: () => probe.onRecorded++,
            ),
          ),
        ),
      ),
    ),
  );
  await _drain(
    tester,
    () => find.text('Eligible for cancellation').evaluate().isNotEmpty,
  );
  expect(tester.takeException(), isNull);
}

Future<void> _review(WidgetTester tester) async {
  final review = find.widgetWithText(FilledButton, 'Review cancellation');
  await tester.ensureVisible(review);
  await tester.tap(review);
  await tester.pumpAndSettle();
  expect(
    tester
        .widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Confirm cancellation'),
        )
        .onPressed,
    isNull,
  );
  await tester.tap(find.byKey(const Key('receipt-cancel-reason')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Operator cancellation').last);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Confirm cancellation'));
  // Advance the dialog while the SDK response is intentionally held.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  for (final lookup in [false, true]) {
    group(lookup ? 'lookup' : 'inspection', () {
      late _Probe probe;
      setUp(() async {
        probe = _Probe(lookup: lookup);
        await probe.start();
      });
      tearDown(() => probe.finish());
      for (final condition in ['unrelated identity', 'absent scope']) {
        test(
          'receipt private providers deny unrelated identity or absent scope: $condition',
          () async {
            if (condition == 'absent scope') {
              await probe.finish();
              probe = _Probe(lookup: lookup, noScope: true);
              await probe.start();
            } else {
              probe.container.read(probe.authority.notifier).state =
                  Future.value(probe.denied(condition));
            }
            await expectLater(
              probe.read(),
              throwsA(
                condition == 'absent scope'
                    ? anyOf(
                        isA<AdminReceiptCancelDenied>(),
                        isA<AdminSessionChanged>(),
                      )
                    : isA<AdminReceiptCancelDenied>(),
              ),
            );
            expect(probe.requests, isEmpty);
          },
        );
      }
      test(
        'receipt provider binds exact target and captured SDK bearer',
        () async {
          final keep = probe.container.listen(probe.provider, (_, _) {});
          addTearDown(keep.close);
          expect(await probe.read(), isNotNull);
          final request = probe.requests.single;
          expect(request.url.path, '/rest/v1/rpc/${probe.readRpc}');
          expect(request.method, 'POST');
          expect(
            request.headers['Authorization'],
            'Bearer ${probe.client.auth.currentSession!.accessToken}',
          );
          expect(jsonDecode(request.body), {
            lookup ? 'p_request_id' : 'p_outbox_id': probe.target,
          });
        },
      );
      for (final condition in [
        'absent identity',
        'role loss',
        'payments.read',
        'notifications.read',
        'system_health.read',
      ]) {
        test(
          'receipt provider denies $condition before SDK dispatch',
          () async {
            probe.container.read(probe.authority.notifier).state = Future.value(
              condition == 'absent identity' ? null : probe.denied(condition),
            );
            await expectLater(
              probe.read(),
              throwsA(isA<AdminReceiptCancelDenied>()),
            );
            expect(probe.requests, isEmpty);
          },
        );
      }
      for (final departure in [
        'permission loss',
        'role loss',
        'identity loading',
        'identity error',
        'session replacement',
        'A-B-A',
      ]) {
        test(
          'receipt provider suppresses pending SDK response after $departure',
          () async {
            probe.release = Completer<void>();
            final waiting = Completer<AdminIdentity?>();
            addTearDown(() {
              if (!waiting.isCompleted) {
                waiting.complete(null);
              }
            });
            final emissions = <AsyncValue<Object?>>[];
            final keep = probe.container.listen(
              probe.provider,
              (_, next) => emissions.add(next),
            );
            addTearDown(keep.close);
            final outcome = probe.read().then<Object?>(
              (value) => value,
              onError: (Object error) => error,
            );
            await probe.entered.future;
            probe.container.read(probe.authority.notifier).state =
                departure == 'permission loss' || departure == 'role loss'
                ? Future.value(
                    probe.denied(
                      departure == 'permission loss'
                          ? 'notifications.read'
                          : departure,
                    ),
                  )
                : waiting.future;
            await probe.container.pump();
            if (departure == 'session replacement' || departure == 'A-B-A') {
              await auth.session(probe.client, 'receipt-sdk-b');
              if (departure == 'A-B-A') {
                await auth.session(probe.client, 'receipt-sdk-a', nonce: 2);
              }
            }
            if (departure == 'identity error') {
              waiting.completeError(StateError('PRIVATE_CANARY'));
              await probe.container.pump();
            }
            probe.release!.complete();
            if (!waiting.isCompleted) {
              waiting.complete(null);
            }
            await probe.container.pump();
            expect(await outcome, anyOf(isA<Exception>(), isA<StateError>()));
            expect(emissions.where((v) => v.asData != null), isEmpty);
            expect(probe.requests, hasLength(1));
          },
        );
      }
    });
  }
  group('production cancellation card with actual SDK', () {
    late _Probe probe;
    setUp(() async {
      probe = _Probe();
      await probe.start();
    });
    tearDown(() => probe.finish());
    testWidgets(
      'confirmed matching SDK ACK clears original checkpoint and refreshes exactly once',
      (tester) async {
        await _mount(tester, probe);
        await _review(tester);
        await _drain(tester, () => probe.onRecorded == 1);
        expect(probe.mutations, hasLength(1));
        expect(probe.store.values, isEmpty);
        expect(
          probe.requests.where(
            (r) => r.url.path.endsWith('/admin_inspect_unstarted_receipt_v1'),
          ),
          hasLength(2),
        );
        expect(
          probe.requests.where(
            (r) => r.url.path.endsWith('/admin_current_user'),
          ),
          hasLength(1),
        );
        expect(
          probe.requests.every(
            (r) =>
                r.headers['Authorization'] ==
                'Bearer ${probe.client.auth.currentSession!.accessToken}',
          ),
          isTrue,
        );
        expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(probe.finish);
        await tester.pump();
      },
    );
    for (final failure in ['transport', 'malformed', 'mismatch', 503]) {
      testWidgets(
        'uncertain SDK $failure retains original intent and forbids replacement/replay',
        (tester) async {
          probe.mutationError = failure;
          probe.lookupStatus = 'not_recorded';
          await _mount(tester, probe);
          await _review(tester);
          await _drain(
            tester,
            () => find
                .textContaining('Cancellation outcome unconfirmed')
                .evaluate()
                .isNotEmpty,
          );
          expect(probe.mutations, hasLength(1));
          expect(probe.onRecorded, 0);
          final checkpoint = probe.store.values.values.single;
          expect(
            AdminReceiptCancelCheckpoint.parse(
              checkpoint,
              adminReceiptCancelOwnerDigest(auth.actor),
            ).intent.parameters,
            probe.submitted!.parameters,
          );
          final original = find.widgetWithText(
            OutlinedButton,
            'Check original request',
          );
          await tester.ensureVisible(original);
          await tester.tap(original);
          await tester.pumpAndSettle();
          await _drain(
            tester,
            () => find
                .text('Original request not recorded at this check')
                .evaluate()
                .isNotEmpty,
          );
          expect(probe.store.values.values.single, checkpoint);
          expect(probe.mutations, hasLength(1));
          expect(
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Review cancellation'),
                )
                .onPressed,
            isNull,
          );
          expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
          expect(find.textContaining('PRIVATE_TRANSPORT_CANARY'), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(probe.finish);
          await tester.pump();
        },
      );
    }
    for (final departure in [
      'permission loss',
      'identity loading',
      'session replacement',
      'A-B-A',
    ]) {
      testWidgets(
        'departed SDK ACK after $departure preserves original without publishing confirmation',
        (tester) async {
          probe.mutationRelease = Completer<void>();
          await _mount(tester, probe);
          await _review(tester);
          await _drain(tester, () => probe.mutations.isNotEmpty);
          final checkpoint = probe.store.values.values.single;
          final waiting = Completer<AdminIdentity?>();
          addTearDown(() {
            if (!waiting.isCompleted) {
              waiting.complete(null);
            }
          });
          await tester.runAsync(() async {
            probe.container
                .read(probe.authority.notifier)
                .state = departure == 'permission loss'
                ? Future.value(probe.denied('notifications.manage'))
                : waiting.future;
            if (departure == 'session replacement' || departure == 'A-B-A') {
              await auth.session(probe.client, 'receipt-sdk-b');
              if (departure == 'A-B-A') {
                await auth.session(probe.client, 'receipt-sdk-a', nonce: 2);
              }
            }
            probe.mutationRelease!.complete();
            await Future<void>.delayed(const Duration(milliseconds: 20));
          });
          await tester.pump(const Duration(milliseconds: 100));
          expect(probe.store.values.values.single, checkpoint);
          expect(probe.onRecorded, 0);
          expect(probe.mutations, hasLength(1));
          expect(find.textContaining('Cancellation recorded.'), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(probe.finish);
          await tester.pump();
        },
      );
    }
  });
}
