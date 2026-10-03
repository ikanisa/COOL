import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_action_session_test.dart' as sdk;
import 'support/admin_read_fixture.dart';

const _id = sdk.target;
const _name = 'Synthetic official payee';
const _reason = 'Synthetic independently reviewed evidence';
const _identity = AdminIdentity(
  userId: sdk.actor,
  displayName: 'Synthetic operator',
  roles: ['admin'],
  permissions: [
    'collections.read',
    'collections.moderate',
    'payees.read',
    'payees.manage',
  ],
);
const _payee = AdminTableRowData(
  id: 'momo:$_id',
  title: _name,
  subtitle: 'Locked synthetic route',
  status: 'active',
  amount: '',
);

// The production widgets and production repository execute against the locked
// SDK HTTP client. Synthetic JSON is contract evidence, not a server acceptance.
enum _Action {
  createGroup,
  createPayee,
  editPayee,
  deactivatePayee,
  activatePayee,
  deactivateGroup,
  activateGroup,
  approveGroup,
  rejectGroup,
  metadata,
  note,
}

String _rpc(_Action action) => switch (action) {
  _Action.createGroup => 'admin_create_platform_public_group',
  _Action.createPayee => 'admin_create_collect_payee',
  _Action.editPayee => 'admin_update_collect_payee',
  _Action.deactivatePayee ||
  _Action.activatePayee => 'admin_set_collect_payee_status',
  _Action.deactivateGroup || _Action.activateGroup => 'admin_set_group_active',
  _Action.approveGroup ||
  _Action.rejectGroup => 'admin_update_collection_support_status',
  _Action.metadata => 'admin_update_platform_public_group_metadata',
  _Action.note => 'admin_record_operator_note',
};

String _success(_Action action) => switch (action) {
  _Action.createGroup => 'Public group created and activated',
  _Action.createPayee => 'Official payee created and activated',
  _Action.editPayee => 'Official payee name updated',
  _Action.deactivatePayee => 'Official payee deactivated',
  _Action.activatePayee => 'Official payee activated',
  _Action.deactivateGroup => 'Group updated: Deactivate',
  _Action.activateGroup => 'Group updated: Activate',
  _Action.approveGroup => 'Group updated: Approve public',
  _Action.rejectGroup => 'Group updated: Reject public',
  _Action.metadata => 'Public group updated in Supabase',
  _Action.note => 'Operator note recorded',
};

Map<String, dynamic> _parameters(_Action action) => switch (action) {
  _Action.createGroup => {
    'p_title': 'Synthetic reviewed group',
    'p_description': 'Synthetic description',
    'p_collection_type': 'ikimina',
    'p_category_subtype': 'community',
    'p_purpose_label': 'Synthetic savings',
    'p_receiver_label': _name,
    'p_momo_code': '123456',
    'p_network': 'mtn_momo',
    'p_reason': _reason,
  },
  _Action.createPayee => {
    'p_collection_id': _id,
    'p_label': _name,
    'p_momo_code': '123456',
    'p_network': 'mtn_momo',
    'p_reason': _reason,
  },
  _Action.editPayee => {
    'p_payee_id': _id,
    'p_label': 'Synthetic updated name',
    'p_reason': _reason,
  },
  _Action.deactivatePayee || _Action.activatePayee => {
    'p_payee_id': _id,
    'p_active': action == _Action.activatePayee,
    'p_reason': _reason,
  },
  _Action.deactivateGroup || _Action.activateGroup => {
    'p_collection_id': _id,
    'p_active': action == _Action.activateGroup,
    'p_reason': _reason,
  },
  _Action.approveGroup || _Action.rejectGroup => {
    'p_collection_id': _id,
    'p_status': action == _Action.approveGroup
        ? 'public_approved'
        : 'public_rejected',
    'p_reason': _reason,
  },
  _Action.metadata => {
    'p_collection_id': _id,
    'p_title': 'Synthetic updated group',
    'p_description': 'Synthetic description',
    'p_collection_type': 'ikimina',
    'p_category_subtype': 'community',
    'p_purpose_label': 'Synthetic savings',
    'p_receiver_label': _name,
    'p_reason': _reason,
  },
  _Action.note => {
    'p_entity_type': 'collection',
    'p_entity_id': _id,
    'p_body': _reason,
  },
};

Map<String, dynamic> _receipt(_Action action) => switch (action) {
  _Action.createGroup => {
    'ok': true,
    'collection_id': _id,
    'payee_id': sdk.actor,
    'status': 'active',
    'visibility': 'public_approved',
    'route_immutable': true,
  },
  _Action.createPayee => {
    'ok': true,
    'payee_id': _id,
    'status': 'active',
    'route_immutable': true,
  },
  _Action.editPayee => {
    'ok': true,
    'payee_id': _id,
    'label': 'Synthetic updated name',
    'route_immutable': true,
  },
  _Action.deactivatePayee || _Action.activatePayee => {
    'ok': true,
    'payee_id': _id,
    'status': action == _Action.activatePayee ? 'active' : 'inactive',
    'route_immutable': true,
  },
  _Action.deactivateGroup || _Action.activateGroup => {
    'ok': true,
    'collection_id': _id,
    'active': action == _Action.activateGroup,
    'status': action == _Action.activateGroup ? 'active' : 'inactive',
    'visibility': action == _Action.activateGroup ? 'private' : 'archived',
  },
  _Action.approveGroup || _Action.rejectGroup => {
    'ok': true,
    'status': action == _Action.approveGroup
        ? 'public_approved'
        : 'public_rejected',
  },
  _Action.metadata => {
    'ok': true,
    'collection_id': _id,
    'receiver_id': sdk.actor,
    'public_status': 'public_approved',
    'visibility': 'public_approved',
    'status': 'active',
  },
  _Action.note => {'ok': true, 'note_id': sdk.actor},
};

void main() {
  for (final action in _Action.values) {
    for (final state in [
      'success',
      'cancel',
      'invalid',
      'revoked-draft',
      'late-ack',
      'unknown-ack',
      'denied',
    ]) {
      testWidgets('${action.name} production UI $state', (tester) async {
        debugPrint('custom matrix: setup starts');
        final identity = StateProvider<AdminIdentity?>((_) => _identity);
        final writes = <http.Request>[];
        final release = Completer<http.Response>();
        final began = Completer<void>();
        var done = 0;
        final client = SupabaseClient(
          'https://synthetic.invalid',
          'synthetic-publishable',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient((request) async {
            http.Response response;
            final endpoint = request.url.path.split('/').last;
            if (endpoint == 'verify') {
              final values = (jsonDecode(request.body)['token'] as String)
                  .split('|');
              response = sdk.response(sdk.authReceipt(values[0], values[1]));
            } else if (endpoint == _rpc(action)) {
              writes.add(request);
              if (!began.isCompleted) began.complete();
              response = state == 'late-ack'
                  ? await release.future
                  : state == 'unknown-ack'
                  ? sdk.response({'ok': true})
                  : state == 'denied'
                  ? sdk.response({
                      'code': '42501',
                      'message': 'SYNTHETIC_PRIVATE_DENIAL_CANARY',
                    }, 403)
                  : sdk.response(_receipt(action));
            } else if (endpoint == 'admin_list_platform_payee_candidates') {
              response = sdk.response({
                'rows': [
                  {
                    'id': _id,
                    'title': 'Synthetic eligible group',
                    'subtitle': 'Synthetic candidate',
                    'status': 'eligible',
                    'amount': '',
                    'created_at': adminReadDate,
                  },
                ],
                'total': 1,
              });
            } else if (endpoint == 'admin_get_collection') {
              response = sdk.response({
                ...adminDetailFixture('admin_get_collection', _id),
                'title': 'Synthetic reviewed group',
                'description': 'Synthetic description',
                'category_subtype': 'community',
                'purpose_label': 'Synthetic savings',
                'receiver_display_label': _name,
                'is_platform_sponsored': action == _Action.metadata,
                'public_status': action == _Action.activateGroup
                    ? 'inactive'
                    : action == _Action.approveGroup ||
                          action == _Action.rejectGroup
                    ? 'public_requested'
                    : 'active',
              });
            } else {
              throw StateError('Unexpected synthetic request $endpoint');
            }
            return http.Response.bytes(
              response.bodyBytes,
              response.statusCode,
              headers: response.headers,
              request: request,
            );
          }),
        );
        await sdk.session(client, 'custom-ui-session');
        debugPrint('custom matrix: session ready');
        final container = ProviderContainer(
          overrides: [
            supabaseClientProvider.overrideWithValue(client),
            adminIdentityProvider.overrideWith(
              (ref) async => ref.watch(identity),
            ),
          ],
        );
        var disposed = false;
        addTearDown(() async {
          if (!disposed) container.dispose();
          await tester.runAsync(client.dispose);
        });
        await container.read(adminIdentityProvider.future);
        debugPrint('custom matrix: identity ready');
        tester.view.physicalSize = const Size(1440, 2200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Future<void> network() async {
          debugPrint('custom matrix: network starts');
          for (var i = 0; i < 40; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump();
            if (find.byType(LinearProgressIndicator).evaluate().isEmpty &&
                find.byType(CircularProgressIndicator).evaluate().isEmpty) {
              break;
            }
          }
          await tester.pumpAndSettle();
          debugPrint('custom matrix: animation settled');
          // A form dispatch starts only after its route's closing transition.
          // Allow the real SDK decoder to finish after that fake-clock step.
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 40)),
          );
          await tester.pumpAndSettle();
          debugPrint('custom matrix: network ends');
        }

        Finder field(String label) => find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == label,
        );
        Future<void> fill(String label, String text) async {
          await tester.ensureVisible(field(label));
          await tester.enterText(field(label), text);
          await tester.pump();
        }

        Future<void> tap(Finder finder) async {
          await tester.ensureVisible(finder);
          await tester.tap(finder);
          await network();
        }

        final helper = action.index <= _Action.activatePayee.index;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: Scaffold(
                body: helper
                    ? Consumer(
                        builder: (context, ref, _) => FilledButton(
                          onPressed: () => switch (action) {
                            _Action.createGroup => createAdminPublicGroup(
                              context,
                              ref,
                              onDone: () => done++,
                            ),
                            _Action.createPayee => createAdminPayee(
                              context,
                              ref,
                              onDone: () => done++,
                            ),
                            _Action.editPayee => editAdminPayee(
                              context,
                              ref,
                              row: _payee,
                              onDone: () => done++,
                            ),
                            _ => setAdminPayeeActive(
                              context,
                              ref,
                              row: _payee,
                              active: action == _Action.activatePayee,
                              onDone: () => done++,
                            ),
                          },
                          child: const Text('Open production action'),
                        ),
                      )
                    : const AdminDetailPage(
                        title: 'Group',
                        rpcName: 'admin_get_collection',
                        id: _id,
                      ),
              ),
            ),
          ),
        );
        await network();
        if (helper) {
          await tap(find.text('Open production action'));
        } else if (action == _Action.metadata) {
          await fill(
            'Group name',
            state == 'invalid' ? '' : ' Synthetic updated group ',
          );
          await tap(find.byTooltip('Save group changes'));
        } else {
          await tap(
            find.byTooltip(switch (action) {
              _Action.deactivateGroup => 'Deactivate',
              _Action.activateGroup => 'Activate',
              _Action.approveGroup => 'Approve public',
              _Action.rejectGroup => 'Reject public',
              _ => 'Record note',
            }),
          );
        }
        if (action == _Action.metadata && state == 'invalid') {
          expect(find.text('Enter at least 3 characters'), findsOneWidget);
          expect(find.byType(AlertDialog), findsNothing);
        } else {
          expect(find.byType(AlertDialog), findsOneWidget);
          if (state == 'cancel') {
            await tap(find.text('Cancel'));
          } else if (state == 'revoked-draft') {
            // The mounted StatefulWidget must be removed, not merely have its
            // launch button disabled while its existing sensitive draft lives.
            container.read(identity.notifier).state = const AdminIdentity(
              userId: sdk.actor,
              displayName: 'Synthetic operator',
              roles: ['admin'],
              permissions: [],
            );
            await network();
            expect(find.byType(AlertDialog), findsNothing);
          } else {
            if (action == _Action.createGroup) {
              await fill(
                'Group name',
                state == 'invalid' ? 'x' : ' Synthetic reviewed group ',
              );
              await fill('Description', ' Synthetic description ');
              await fill('Category key', ' community ');
              await fill('Purpose label', ' Synthetic savings ');
              await fill('Official payee name', ' $_name ');
              await fill('MoMo number or code', ' 123456 ');
              await fill('Creation reason', ' $_reason ');
            } else if (action == _Action.createPayee) {
              await fill('Official payee name', ' $_name ');
              await fill(
                'MoMo number or code',
                state == 'invalid' ? 'abc' : ' 123456 ',
              );
              await fill('Creation reason', ' $_reason ');
            } else if (action == _Action.editPayee) {
              await fill(
                'Official payee name',
                state == 'invalid' ? 'x' : ' Synthetic updated name ',
              );
              await fill('Change reason', ' $_reason ');
              expect(field('MoMo number or code'), findsNothing);
              expect(field('Provider'), findsNothing);
            } else {
              final reasonField = find.descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(TextField),
              );
              await tester.enterText(
                reasonField,
                state == 'invalid' ? ' ' : ' $_reason ',
              );
              await tester.pump();
            }
            final submit = find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(FilledButton),
            );
            await tester.ensureVisible(submit);
            await tester.tap(submit);
            if (state == 'late-ack') {
              if (helper) {
                await tester.pumpAndSettle();
              }
              await tester.runAsync(() => began.future);
              container.read(identity.notifier).state = const AdminIdentity(
                userId: sdk.actor,
                displayName: 'Synthetic operator',
                roles: ['admin'],
                permissions: [],
              );
              await container.read(adminIdentityProvider.future);
              container.read(identity.notifier).state = _identity;
              await container.read(adminIdentityProvider.future);
              release.complete(sdk.response(_receipt(action)));
            }
            await network();
          }
        }
        if (['cancel', 'invalid', 'revoked-draft'].contains(state)) {
          expect(writes, isEmpty);
          expect(done, 0);
        } else {
          expect(writes, hasLength(1));
          expect(writes.single.method, 'POST');
          expect(
            writes.single.headers['Authorization'],
            'Bearer ${client.auth.currentSession!.accessToken}',
          );
          expect(jsonDecode(writes.single.body), _parameters(action));
          expect(done, helper && state == 'success' ? 1 : 0);
        }
        expect(
          find.text(_success(action)),
          state == 'success' ? findsOneWidget : findsNothing,
        );
        expect(find.text('SYNTHETIC_PRIVATE_DENIAL_CANARY'), findsNothing);
        if (state == 'unknown-ack') {
          expect(
            find.text(
              'The action was not acknowledged. Refresh the record before trying again.',
            ),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
        debugPrint('custom matrix: assertions complete');
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        disposed = true;
      });
    }
  }
}
