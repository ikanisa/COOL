import 'dart:async';
import 'dart:convert';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_exception_workflow_models.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_action_session_test.dart' as auth;
import 'admin_exception_workflow_test.dart' as evidence;

const _recipient = AdminIdentity(
  userId: auth.actor,
  displayName: 'Synthetic escalation recipient',
  roles: ['admin'],
  permissions: ['payments.read', 'notifications.read', 'system_health.read'],
);

Future<void> _settleSdk(WidgetTester tester) async {
  // Auth and HTTP futures use the real event loop; widget animation uses the
  // test clock. Advance both without replacing the SDK with a fake gateway.
  for (var frame = 0; frame < 8; frame++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _withSdkInbox(
  WidgetTester tester,
  SupabaseClient client,
  DateTime checkedAt,
  Future<void> Function() exercise,
) async {
  final container = ProviderContainer(
    overrides: [
      supabaseClientProvider.overrideWithValue(client),
      adminIdentityProvider.overrideWith((ref) async => _recipient),
      adminClockProvider.overrideWithValue(() => checkedAt),
    ],
  );
  try {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: CollectTheme.light(),
          home: const Scaffold(
            body: SingleChildScrollView(child: AdminExceptionEscalationInbox()),
          ),
        ),
      ),
    );
    await _settleSdk(tester);
    await tester.tap(find.text('Your escalation inbox'));
    await _settleSdk(tester);
    expect(find.text('Open exception follow-up'), findsWidgets);
    await tester.ensureVisible(find.text('Open exception follow-up').first);
    await exercise();
  } finally {
    // The uncontrolled container owns the real Auth expiry timer. Dispose it
    // before Flutter verifies widget invariants, including assertion failures.
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump();
  }
}

void main() {
  late SupabaseClient client;
  late AdminRepository repository;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) respond;
  final raw = evidence.observed('workflow');
  final id = raw['exception_id'] as String;
  final now = DateTime.parse(raw['checked_at'] as String);
  final intent = AdminExceptionWorkflowIntent(
    requestId: '11111111-1111-4111-8111-111111111111',
    exceptionId: id,
    sourceRevision: raw['source_revision'] as int,
    workflowRevision: raw['workflow_revision'] as int,
    action: 'resolve',
    expiresAt: now.add(const Duration(seconds: 90)),
  );
  final receipt = {
    'contract_version': 1,
    'request_id': intent.requestId,
    'exception_id': id,
    'source_revision': intent.sourceRevision,
    'workflow_revision': intent.workflowRevision + 1,
    'action': 'resolve',
    'escalation_id': null,
    'source_resolved': true,
    'financial_action': false,
    'send_action': false,
    'recorded_at': evidence.wire(now),
  };
  setUp(() async {
    requests = [];
    respond = (_) async => auth.response(raw);
    client = SupabaseClient(
      'https://synthetic.invalid',
      'synthetic-public',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/verify')) {
          final parts = (jsonDecode(request.body)['token'] as String).split(
            '|',
          );
          return auth.response(auth.authReceipt(parts[0], parts[1]));
        }
        if (request.url.path.endsWith('/logout')) return auth.response({});
        requests.add(request);
        final response = await respond(request);
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }),
    );
    await auth.session(client, 'workflow-a');
    repository = AdminRepository(client);
  });
  tearDown(() => client.dispose());
  test(
    'actual SDK reads strict workflow with current session header',
    () async {
      await repository.exceptionWorkflow(id);
      expect(
        requests.single.url.path,
        '/rest/v1/rpc/admin_get_exception_workflow_v1',
      );
      expect(jsonDecode(requests.single.body), {'p_exception_id': id});
      expect(
        requests.single.headers['Authorization'],
        'Bearer ${client.auth.currentSession!.accessToken}',
      );
    },
  );
  test(
    'actual SDK binds expiring action to exact source and workflow revisions',
    () async {
      respond = (_) async => auth.response(receipt);
      await repository.exceptionWorkflowAction(intent);
      expect(
        requests.single.url.path,
        '/rest/v1/rpc/admin_act_exception_workflow_v1',
      );
      expect(jsonDecode(requests.single.body), intent.parameters);
    },
  );
  test(
    'denial and uncertain server response each perform one mutation attempt',
    () async {
      for (final status in [403, 503]) {
        respond = (_) async => auth.response({
          'code': status == 403 ? '42501' : 'unavailable',
          'message': 'PRIVATE_CANARY',
        }, status);
        await expectLater(
          repository.exceptionWorkflowAction(intent),
          throwsA(isA<PostgrestException>()),
        );
      }
      expect(requests.length, 2);
    },
  );
  test(
    'false send and mismatched receipt claims reject without retry',
    () async {
      for (final invalid in [
        {...receipt, 'send_action': true},
        {...receipt, 'source_revision': 1},
        {'ok': true},
      ]) {
        respond = (_) async => auth.response(invalid);
        await expectLater(
          repository.exceptionWorkflowAction(intent),
          throwsFormatException,
        );
      }
      expect(requests.length, 3);
    },
  );
  test(
    'session replacement suppresses a pending old action response',
    () async {
      final held = Completer<http.Response>();
      final started = Completer<void>();
      respond = (_) {
        started.complete();
        return held.future;
      };
      final pending = repository.exceptionWorkflowAction(intent);
      final assertion = expectLater(
        pending,
        throwsA(isA<AdminSessionChanged>()),
      );
      await started.future;
      await auth.session(client, 'workflow-b');
      held.complete(auth.response(receipt));
      await assertion;
      expect(requests.length, 1);
    },
  );
  test(
    'request lookup is a single read and never replays original action',
    () async {
      respond = (_) async => auth.response({
        'contract_version': 1,
        'request_id': intent.requestId,
        'checked_at': evidence.wire(now),
        'sample_valid_until': evidence.wire(
          now.add(const Duration(seconds: 60)),
        ),
        'status': 'recorded',
        'receipt': receipt,
      });
      final result = await repository.exceptionWorkflowRequest(
        intent.requestId,
      );
      expect(
        AdminExceptionWorkflowLookup.parse(result, intent).status,
        'recorded',
      );
      expect(
        requests.single.url.path,
        '/rest/v1/rpc/admin_get_exception_workflow_request_v1',
      );
      expect(jsonDecode(requests.single.body), {
        'p_request_id': intent.requestId,
      });
    },
  );

  group('actual SDK escalation endpoints', () {
    final inbox = evidence.observed('inbox');
    final sample = AdminExceptionEscalationSnapshot.parse(inbox);
    final delivery = sample.rows.first;
    final acknowledgement = {
      'contract_version': 1,
      'escalation_id': delivery.id,
      'read_at': evidence.wire(sample.checkedAt),
      'source_resolved': false,
    };

    Future<Map<String, dynamic>> invoke(String operation) =>
        operation == 'admin_list_exception_escalation_inbox_v1'
        ? repository.exceptionEscalationInbox()
        : repository.readExceptionEscalation(delivery.id);
    Object responseFor(String operation) =>
        operation == 'admin_list_exception_escalation_inbox_v1'
        ? inbox
        : acknowledgement;

    for (final operation in [
      'admin_list_exception_escalation_inbox_v1',
      'admin_read_exception_escalation_v1',
    ]) {
      test(
        '$operation pins exact POST body and captured recipient Bearer',
        () async {
          respond = (_) async => auth.response(responseFor(operation));
          final token = client.auth.currentSession!.accessToken;
          final result = await invoke(operation);
          final request = requests.single;
          expect(request.method, 'POST');
          expect(request.url.path, '/rest/v1/rpc/$operation');
          expect(request.headers['authorization'], 'Bearer $token');
          expect(
            jsonDecode(request.body),
            operation == 'admin_list_exception_escalation_inbox_v1'
                ? {'p_limit': 20}
                : {'p_escalation_id': delivery.id},
          );
          if (operation == 'admin_list_exception_escalation_inbox_v1') {
            expect(
              AdminExceptionEscalationSnapshot.parse(result).rows.first.id,
              delivery.id,
            );
          } else {
            expect(result, acknowledgement);
          }
        },
      );

      for (final failure in ['denied', '503', 'response-loss']) {
        test(
          '$operation $failure makes one SDK request without fallback',
          () async {
            respond = (_) async {
              if (failure == 'response-loss') {
                throw http.ClientException(
                  'SYNTHETIC_PRIVATE_TRANSPORT_DETAIL',
                );
              }
              return auth.response({
                'code': failure == 'denied' ? '42501' : '55000',
                'message': 'SYNTHETIC_PRIVATE_TRANSPORT_DETAIL',
              }, failure == 'denied' ? 403 : 503);
            };
            await expectLater(
              invoke(operation),
              throwsA(
                failure == 'response-loss'
                    ? isA<http.ClientException>()
                    : isA<PostgrestException>(),
              ),
            );
            expect(requests, hasLength(1));
            expect(requests.single.url.path, '/rest/v1/rpc/$operation');
          },
        );
      }

      for (final switchBack in [false, true]) {
        test(
          '$operation rejects late SDK response switchBack=$switchBack',
          () async {
            final held = Completer<http.Response>();
            final started = Completer<void>();
            respond = (_) {
              started.complete();
              return held.future;
            };
            final pending = invoke(operation);
            final assertion = expectLater(
              pending,
              throwsA(isA<AdminSessionChanged>()),
            );
            await started.future;
            await auth.session(client, 'workflow-b');
            if (switchBack) await auth.session(client, 'workflow-a', nonce: 2);
            held.complete(auth.response(responseFor(operation)));
            await assertion;
            expect(requests, hasLength(1));
          },
        );
      }

      test(
        '$operation same-session refresh keeps the original request Bearer',
        () async {
          final held = Completer<http.Response>();
          final started = Completer<void>();
          respond = (_) {
            started.complete();
            return held.future;
          };
          final token = client.auth.currentSession!.accessToken;
          final pending = invoke(operation);
          await started.future;
          await auth.session(client, 'workflow-a', nonce: 3);
          held.complete(auth.response(responseFor(operation)));
          expect(await pending, responseFor(operation));
          expect(requests, hasLength(1));
          expect(requests.single.headers['authorization'], 'Bearer $token');
          expect(client.auth.currentSession!.accessToken, isNot(token));
        },
      );

      test('$operation signed-out caller makes no SDK request', () async {
        await client.auth.signOut();
        await expectLater(
          invoke(operation),
          throwsA(isA<AdminSessionChanged>()),
        );
        expect(requests, isEmpty);
      });
    }

    test(
      'read acknowledgement refuses malformed delivery ID before SDK dispatch',
      () async {
        expect(
          () => repository.readExceptionEscalation('not-a-uuid'),
          throwsFormatException,
        );
        expect(requests, isEmpty);
      },
    );

    for (final absent in _recipient.permissions) {
      test(
        'escalation provider denies missing $absent before actual SDK read',
        () async {
          final container = ProviderContainer(
            overrides: [
              supabaseClientProvider.overrideWithValue(client),
              adminIdentityProvider.overrideWith(
                (ref) async => AdminIdentity(
                  userId: auth.actor,
                  displayName: _recipient.displayName,
                  roles: _recipient.roles,
                  permissions: _recipient.permissions
                      .where((value) => value != absent)
                      .toList(),
                ),
              ),
            ],
          );
          addTearDown(container.dispose);
          await expectLater(
            container.read(adminExceptionEscalationInboxProvider.future),
            throwsA(isA<AdminExceptionDenied>()),
          );
          expect(requests, isEmpty);
        },
      );
    }

    for (final departure in ['permission-loss', 'identity-loading']) {
      test(
        'escalation provider discards held actual SDK projection after $departure',
        () async {
          final held = Completer<http.Response>();
          final started = Completer<void>();
          respond = (_) {
            started.complete();
            return held.future;
          };
          final authority = StateProvider<Future<AdminIdentity?>>(
            (_) async => _recipient,
          );
          final container = ProviderContainer(
            overrides: [
              supabaseClientProvider.overrideWithValue(client),
              adminIdentityProvider.overrideWith((ref) => ref.watch(authority)),
            ],
          );
          addTearDown(container.dispose);
          final keep = container.listen(
            adminExceptionEscalationInboxProvider,
            (_, _) {},
          );
          addTearDown(keep.close);
          final assertion = expectLater(
            container.read(adminExceptionEscalationInboxProvider.future),
            throwsA(isA<AdminExceptionDenied>()),
          );
          await started.future;
          final loading = Completer<AdminIdentity?>();
          container
              .read(authority.notifier)
              .state = departure == 'identity-loading'
              ? loading.future
              : Future.value(
                  AdminIdentity(
                    userId: auth.actor,
                    displayName: _recipient.displayName,
                    roles: _recipient.roles,
                    permissions: const [],
                  ),
                );
          await Future<void>.delayed(Duration.zero);
          expect(
            container.read(adminIdentityProvider).isLoading ||
                container
                        .read(adminIdentityProvider)
                        .asData
                        ?.value
                        ?.permissions
                        .isEmpty ==
                    true,
            isTrue,
          );
          held.complete(auth.response(inbox));
          if (departure == 'identity-loading') {
            // Riverpod follows the replacement identity future. While it is
            // unresolved, the old HTTP projection must remain unpublished.
            await Future<void>.delayed(Duration.zero);
            await Future<void>.delayed(Duration.zero);
            final state = container.read(adminExceptionEscalationInboxProvider);
            expect(state.isLoading, isTrue);
            expect(state.asData, isNull);
            expect(requests, hasLength(1));
            loading.complete(null);
          }
          await assertion;
          expect(requests, hasLength(1));
        },
      );
    }

    test(
      'escalation provider rejects contradictory SDK projection and private extras',
      () async {
        final original = inbox['rows'] as List;
        final first = Map<String, dynamic>.from(original.first as Map);
        for (final invalid in [
          {...inbox, 'private_email': 'SYNTHETIC_PRIVATE_CANARY'},
          {...inbox, 'channel': 'sms'},
          {
            ...inbox,
            'rows': [first, first],
          },
          {
            ...inbox,
            'rows': [
              {...first, 'current_source_revision': 0},
            ],
          },
          {
            ...inbox,
            'rows': [
              {...first, 'source_active': 'false'},
            ],
          },
          {
            ...inbox,
            'rows': [
              {
                ...first,
                'read_at': evidence.wire(
                  delivery.deliveredAt.subtract(
                    const Duration(microseconds: 1),
                  ),
                ),
              },
            ],
          },
          {
            ...inbox,
            'rows': [
              {...first, 'raw_phone': 'SYNTHETIC_PRIVATE_CANARY'},
            ],
          },
        ]) {
          respond = (_) async => auth.response(invalid);
          final container = ProviderContainer(
            overrides: [
              supabaseClientProvider.overrideWithValue(client),
              adminIdentityProvider.overrideWith((ref) async => _recipient),
            ],
          );
          try {
            await expectLater(
              container.read(adminExceptionEscalationInboxProvider.future),
              throwsFormatException,
            );
          } finally {
            container.dispose();
          }
        }
        expect(requests, hasLength(7));
        expect(
          requests.every(
            (request) => request.url.path.endsWith(
              'admin_list_exception_escalation_inbox_v1',
            ),
          ),
          isTrue,
        );
      },
    );

    Future<http.Response> validUiResponse(http.Request request) async =>
        auth.response(
          request.url.path.endsWith('admin_list_exception_escalation_inbox_v1')
              ? inbox
              : request.url.path.endsWith('admin_read_exception_escalation_v1')
              ? acknowledgement
              : raw,
        );

    testWidgets(
      'recipient production inbox opens only after matching actual SDK read ACK',
      (tester) async {
        respond = validUiResponse;
        await _withSdkInbox(tester, client, sample.checkedAt, () async {
          await tester.tap(find.text('Open exception follow-up').first);
          await _settleSdk(tester);
          expect(find.text('Close follow-up'), findsOneWidget);
          final reads = requests
              .where(
                (request) => request.url.path.endsWith(
                  'admin_read_exception_escalation_v1',
                ),
              )
              .toList();
          expect(reads, hasLength(1));
          expect(jsonDecode(reads.single.body), {
            'p_escalation_id': delivery.id,
          });
          expect(
            requests.any(
              (request) =>
                  request.url.path.endsWith('admin_act_exception_workflow_v1'),
            ),
            isFalse,
          );
          await evidence.close(tester);
        });
      },
    );

    for (final corrupt in [
      'wrong-delivery',
      'resolved-source',
      'private-extra',
      'before-delivery',
      'wrong-version',
      'missing-ACK',
    ]) {
      testWidgets(
        'recipient production inbox rejects actual SDK $corrupt read ACK',
        (tester) async {
          final ack = switch (corrupt) {
            'wrong-delivery' => {
              ...acknowledgement,
              'escalation_id': intent.requestId,
            },
            'resolved-source' => {...acknowledgement, 'source_resolved': true},
            'private-extra' => {
              ...acknowledgement,
              'raw_phone': 'SYNTHETIC_PRIVATE_CANARY',
            },
            'before-delivery' => {
              ...acknowledgement,
              'read_at': evidence.wire(
                delivery.deliveredAt.subtract(const Duration(microseconds: 1)),
              ),
            },
            'wrong-version' => {...acknowledgement, 'contract_version': true},
            _ => {'ok': true},
          };
          respond = (request) async =>
              request.url.path.endsWith('admin_read_exception_escalation_v1')
              ? auth.response(ack)
              : validUiResponse(request);
          await _withSdkInbox(tester, client, sample.checkedAt, () async {
            await tester.tap(find.text('Open exception follow-up').first);
            await _settleSdk(tester);
            expect(find.text('Close follow-up'), findsNothing);
            expect(
              find.textContaining('Opening could not be recorded'),
              findsOneWidget,
            );
            expect(
              find.textContaining('SYNTHETIC_PRIVATE_CANARY'),
              findsNothing,
            );
            expect(
              requests.where(
                (request) => request.url.path.endsWith(
                  'admin_read_exception_escalation_v1',
                ),
              ),
              hasLength(1),
            );
            expect(
              requests.any(
                (request) =>
                    request.url.path.endsWith(
                      'admin_get_exception_workflow_v1',
                    ) ||
                    request.url.path.endsWith(
                      'admin_act_exception_workflow_v1',
                    ),
              ),
              isFalse,
            );
            await evidence.close(tester);
          });
        },
      );
    }

    testWidgets(
      'recipient production inbox loses actual SDK response without opening or automatic replay',
      (tester) async {
        respond = (request) async {
          if (request.url.path.endsWith('admin_read_exception_escalation_v1')) {
            throw http.ClientException('SYNTHETIC_PRIVATE_RESPONSE_LOSS');
          }
          return validUiResponse(request);
        };
        await _withSdkInbox(tester, client, sample.checkedAt, () async {
          await tester.tap(find.text('Open exception follow-up').first);
          await _settleSdk(tester);
          expect(find.text('Close follow-up'), findsNothing);
          expect(
            find.textContaining('Opening could not be recorded'),
            findsOneWidget,
          );
          expect(
            find.textContaining('SYNTHETIC_PRIVATE_RESPONSE_LOSS'),
            findsNothing,
          );
          expect(
            requests.where(
              (request) => request.url.path.endsWith(
                'admin_read_exception_escalation_v1',
              ),
            ),
            hasLength(1),
          );
          expect(
            requests.any(
              (request) =>
                  request.url.path.endsWith('admin_get_exception_workflow_v1'),
            ),
            isFalse,
          );
          await evidence.close(tester);
        });
      },
    );

    for (final switchBack in [false, true]) {
      testWidgets(
        'recipient production inbox suppresses departed actual SDK read ACK switchBack=$switchBack',
        (tester) async {
          final held = Completer<http.Response>();
          respond = (request) async =>
              request.url.path.endsWith('admin_read_exception_escalation_v1')
              ? held.future
              : validUiResponse(request);
          await _withSdkInbox(tester, client, sample.checkedAt, () async {
            await tester.tap(find.text('Open exception follow-up').first);
            await _settleSdk(tester);
            expect(
              requests.where(
                (request) => request.url.path.endsWith(
                  'admin_read_exception_escalation_v1',
                ),
              ),
              hasLength(1),
            );
            await tester.runAsync(() async {
              await auth.session(client, 'workflow-b');
              if (switchBack) {
                await auth.session(client, 'workflow-a', nonce: 4);
              }
            });
            await _settleSdk(tester);
            held.complete(auth.response(acknowledgement));
            await _settleSdk(tester);
            expect(find.text('Close follow-up'), findsNothing);
            expect(
              requests.any(
                (request) => request.url.path.endsWith(
                  'admin_get_exception_workflow_v1',
                ),
              ),
              isFalse,
            );
            expect(
              requests.where(
                (request) => request.url.path.endsWith(
                  'admin_read_exception_escalation_v1',
                ),
              ),
              hasLength(1),
            );
            await evidence.close(tester);
          });
        },
      );
    }
  });
}
