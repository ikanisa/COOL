import 'support/recorded_auth_fixture.dart';
// Newly composed actual Settings and receipt detail consumers. Auth/HTTP and
// joined/detail renderer envelopes are explicitly synthetic. Notice RPC bytes
// come from actual canonical1600 fixtures, except the declared caller-generated
// original request UUID in mutation/lookup replies. No unrelated captured IDs are
// rewritten: every joined source ID/amount is taken from its own source_facts.
import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_investigation.dart';
import 'package:collect_app/admin/core/admin_receipt_notice_content_host.dart';
import 'package:collect_app/admin/core/admin_receipt_notice_dispatch_host.dart';
import 'support/receipt_notice_dispatch_journal_fixture.dart';
import 'package:collect_app/admin/core/admin_receipt_notice_content_models.dart';
import 'package:collect_app/admin/core/admin_receipt_notice_content_view.dart';
import 'package:collect_app/admin/core/admin_runtime.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'admin_receipt_notice_content_test.dart'
    show Store, actor, session, fixture;

Map<String, dynamic> _facts(Map<String, dynamic> sample) =>
    ((sample['candidate'] as Map)['source_evidence'] as Map)['source_facts']
        as Map<String, dynamic>;

Map<String, dynamic> _joined(Map<String, dynamic> sample) {
  final f = _facts(sample), reversal = f.containsKey('source_snapshot_id');
  // These values are absent from1600. Group balance0 is a declared renderer-only
  // synthetic value; current balances/times remain unavailable. Neither is used
  // as financial evidence or to derive the notice. The real notice DTO/body and
  // every actual source identifier/amount remain unchanged.
  const group = '0';
  final at = f['original_recorded_at'] as String;
  Map<String, dynamic> journal({required bool compensation}) => {
    'id':
        f[compensation
            ? 'source_journal_entry_id'
            : 'original_journal_entry_id'],
    'entry_type': compensation ? 'reversal' : 'receipt',
    'amount_rwf': '${f['original_amount_rwf']}',
    'posted_at':
        f[compensation ? 'source_recorded_at' : 'original_recorded_at'],
    'snapshot': {
      'id': f[compensation ? 'source_snapshot_id' : 'original_snapshot_id'],
      'captured_at':
          f[compensation ? 'source_recorded_at' : 'original_recorded_at'],
      'delta_rwf': '${compensation ? '-' : ''}${f['original_amount_rwf']}',
      'member_balance_rwf':
          '${f[compensation ? 'source_member_balance_recorded_rwf' : 'original_member_balance_recorded_rwf']}',
      'group_balance_rwf': group,
    },
  };
  final checked = DateTime.parse(sample['checked_at'] as String);
  return {
    'contract_version': 1,
    'scope': 'rwanda_momo',
    'kind': 'receipt',
    'target_id': f['root_outbox_id'],
    'history_limit': 50,
    'checked_at': checked.toIso8601String(),
    'sample_valid_until': checked
        .add(const Duration(seconds: 60))
        .toIso8601String(),
    'payment_state': 'available',
    'receipt_state': 'available',
    'payment': {
      'payment_id': f['payment_id'],
      'raw_sms_id': null,
      'event_id': null,
      'collection_id': f['collection_id'],
      'member_record_id': f['member_record_id'],
      'lifecycle': null,
      'times': {
        'received_at_device': null,
        'ingested_at': null,
        'parsed_recorded_at': null,
        'allocation_recorded_at': null,
        'provider_confirmed_at': null,
        'confirmation_recorded_at': null,
        'rejection_occurred_at': null,
        'rejection_recorded_at': null,
        'payment_posted_at': null,
      },
      'journals': [
        journal(compensation: false),
        if (reversal) journal(compensation: true),
      ],
      'current_balances': {
        'member_rwf': null,
        'member_updated_at': null,
        'group_rwf': null,
        'group_updated_at': null,
      },
    },
    'receipt': {
      'id': f['root_outbox_id'],
      'payment_id': f['payment_id'],
      'snapshot_id': f['original_snapshot_id'],
      'collection_id': f['collection_id'],
      'member_record_id': f['member_record_id'],
      'state': 'observed_sent',
      'template_key': 'buri_munsi.payment_received',
      'template_version': 1,
      'created_at': at,
      'updated_at': at,
      'observed_sent_at': at,
      'masked_destination': '+250•••234',
      'amount_rwf': '${f['original_amount_rwf']}',
      'member_balance_rwf': '${f['original_member_balance_recorded_rwf']}',
      'group_balance_rwf': group,
      'snapshot_captured_at': at,
      'preview_source': 'immutable_posting_snapshot',
      'masked_snapshot_preview':
          'Synthetic redacted source rendering; notice wording comes from1600.',
      'approvals': <Object>[],
      'approval_total': 0,
      'attempts': <Object>[],
      'attempt_total': 0,
    },
  };
}

class _Harness {
  _Harness({this.reversal = false}) {
    sample = fixture(
      'content-preview-${reversal ? 'reversal_notice' : 'duplicate_copy'}-rw',
    );
    joined = _joined(sample);
    // Parse the declared wrapper before any mount; no relaxed fixture decoder.
    AdminInvestigationSnapshot.parse(joined);
    now = DateTime.parse(
      sample['checked_at'] as String,
    ).add(const Duration(seconds: 1));
  }
  final bool reversal;
  final store = Store(), requests = <http.Request>[];
  final permissions = <String>{
    'settings.read',
    'groups.read',
    'payments.read',
    'notifications.read',
    'system_health.read',
    'notifications.manage',
  };
  late Map<String, dynamic> sample, joined;
  late DateTime now;
  late CollectCloudflareClient client;
  late ProviderContainer container;
  bool owner = true,
      denyNoticeAfterRecord = false,
      holdAfterRecord = false,
      loseReply = false;
  Completer<void>? noticeRelease, nextInvestigationRelease;
  String get root => _facts(sample)['root_outbox_id'] as String;
  List<http.Request> calls(String name) =>
      requests.where((r) => r.url.path.endsWith('/$name')).toList();
  Future<void> start() async {
    client = recordedFixtureClient(
      'https://synthetic.invalid',
      httpClient: MockClient((r) async {
        http.Response reply(Object? row, [int status = 200]) => http.Response(
          jsonEncode(row),
          status,
          headers: {'content-type': 'application/json'},
          request: r,
        );
        http.Response denied() =>
            reply({'code': '42501', 'message': 'PRIVATE_SEAM_CANARY'}, 403);
        if (r.url.path == '/v1/auth/verify') {
          return reply({
            'access_token':
                'e30.${base64Url.encode(utf8.encode(jsonEncode({'role': 'authenticated', 'sub': actor, 'session_id': session, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}))).replaceAll('=', '')}.synthetic',
            'refresh_token': 'synthetic-refresh',
            'token_type': 'bearer',
            'user': {
              'id': actor,
              'aud': 'authenticated',
              'email': 'operator@example.invalid',
              'app_metadata': <String, dynamic>{},
              'user_metadata': <String, dynamic>{},
              'created_at': '2026-10-03T00:00:00Z',
            },
          });
        }
        if (r.url.path == '/v1/auth/logout') return reply({});
        requests.add(r);
        final name = r.url.path.split('/').last,
            args = (jsonDecode(r.body) ?? <String, dynamic>{}) as Map;
        if (name == 'admin_current_user') {
          return reply({
            'user_id': actor,
            'display_name': 'Synthetic owner',
            'phone_masked': null,
            'roles': owner ? ['platform_owner'] : ['operator'],
            'permissions': permissions.toList(),
          });
        }
        if (name == 'admin_list_country_scoped') {
          expect(args['p_rpc_name'], 'admin_list_collections');
          expect(args['p_limit'], 25);
          expect(args['p_offset'], 0);
          expect(args['p_country'], 'RW');
          return reply({
            'rows': [
              {
                'id': _facts(sample)['collection_id'],
                'title': 'Synthetic Rwanda group',
                'subtitle': '',
                'status': 'active',
                'amount': '',
                'country_code': 'RW',
              },
            ],
            'total': 1,
          });
        }
        if (name == 'admin_get_hybrid_sms_receipt') {
          expect(args['p_id'], root);
          final f = _facts(sample);
          return reply({
            'id': root,
            'state': 'observed_sent',
            'channel': 'Assisted SMS operator',
            'member_collect_id': f['member_record_id'],
            'collection_id': f['collection_id'],
            'collection_title': 'Synthetic Rwanda group',
            'destination_masked': '+250•••234',
            'amount_rwf': f['original_amount_rwf'],
            'member_balance_rwf': f['original_member_balance_recorded_rwf'],
            'group_balance_rwf': 0,
            'reference': f['original_reference'],
            'template_key': 'buri_munsi.payment_received',
            'template_version': 1,
            'consent_revision': 1,
            'authorization_current': false,
            'body_sha256': f['original_content_sha256'],
            'message_body': 'Hidden until a current fenced operator claim',
            'attempt_count': 0,
            'claim_expires_at': null,
            'suppression_reason': null,
            'created_at': f['original_recorded_at'],
            'observed_sent_at': f['original_recorded_at'],
            'latest_attempt_state': null,
            'delivery_claim':
                'Observed sent is operator-recorded UI evidence, not handset delivery',
          });
        }
        if (name == 'admin_get_collect_investigation_v1') {
          expect(args, {'p_kind': 'receipt', 'p_id': root});
          if (!owner) return denied();
          if (holdAfterRecord && calls(name).length > 1) {
            await nextInvestigationRelease!.future;
          }
          return reply(joined);
        }
        if (name == 'admin_inspect_receipt_notice_policy_v1') {
          await noticeRelease?.future;
          return reply(
            fixture(
              'policy-preview-${args['p_notice_family']}-${args['p_language']}',
            ),
          );
        }
        if (name == 'admin_inspect_receipt_notice_content_v1') {
          await noticeRelease?.future;
          if (denyNoticeAfterRecord) return denied();
          final family = args['p_notice_family'];
          if (family == 'duplicate_copy' && reversal) return denied();
          return reply(
            fixture(
              family == 'correction' || family == 'approved_resend'
                  ? 'explicit-$family-refusal'
                  : 'content-preview-$family-rw',
            ),
          );
        }
        if (name == 'admin_approve_receipt_notice_policy_v1' ||
            name == 'admin_prepare_receipt_notice_content_v1') {
          final intent = store.value!;
          expect(args, intent.parameters);
          expect(intent.actorId, actor);
          expect(intent.sessionId, session);
          expect(
            args.keys.any(
              (k) =>
                  k.toString().contains('body') ||
                  k.toString().contains('destination'),
            ),
            isFalse,
          );
          if (loseReply) {
            throw TimeoutException('Synthetic lost original reply');
          }
          final result = fixture(
            intent.policy
                ? 'actual-approved-policy-duplicate_copy-rw'
                : 'actual-prepared-duplicate_copy-rw',
          )..['request_id'] = intent.requestId;
          expect(result['send_authority'], isFalse);
          expect(result['financial_action'], isFalse);
          expect(result['notice_transport_available'], isFalse);
          if (holdAfterRecord) denyNoticeAfterRecord = true;
          return reply(result);
        }
        if (name == 'admin_get_receipt_notice_content_request_v1') {
          expect(args, {'p_request_id': store.value!.requestId});
          return reply(
            fixture('actual-lookup-not_recorded-12')
              ..['request_id'] = store.value!.requestId,
          );
        }
        // Other existing Settings/receipt safety cards are independently denied;
        // their denial cannot enable a notice/send or replace this route's read.
        return denied();
      }),
    );
    await installRecordedAuthFixture(
      client,
      type: CollectOtpType.email,
      token: 'synthetic',
      email: 'operator@example.invalid',
    );
    container = ProviderContainer(
      overrides: [
        collectBackendClientProvider.overrideWithValue(client),
        adminRealtimeSubscriptionProvider.overrideWith((ref) {}),
        adminClockProvider.overrideWithValue(() => now),
        adminReceiptNoticeContentStoreProvider.overrideWithValue(store),
        adminReceiptNoticeDispatchStoreProvider.overrideWithValue(
          NoticeDispatchJournalFixture().store,
        ),
      ],
    );
    await container.read(adminIdentityProvider.future);
  }

  Widget app({required bool settings}) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: CollectTheme.light(),
      home: Scaffold(
        body: settings
            ? const AdminGovernedSettingsPage()
            : AdminDetailPage(
                title: 'SMS receipt detail',
                rpcName: 'admin_get_hybrid_sms_receipt',
                id: root,
              ),
      ),
    ),
  );
  Future<void> close() async {
    if (noticeRelease?.isCompleted == false) {
      noticeRelease!.complete();
    }
    if (nextInvestigationRelease?.isCompleted == false) {
      nextInvestigationRelease!.complete();
    }
    container.dispose();
    await client.dispose();
  }
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 24; i++) {
    await t.pump(const Duration(milliseconds: 16));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
  }
}

Finder get _view => find.byType(AdminReceiptNoticeContentView);
Finder _within(String text) =>
    find.descendant(of: _view, matching: find.text(text));
Future<void> _expose(WidgetTester t, Finder target) async {
  await t.pump(const Duration(milliseconds: 200));
  await Scrollable.ensureVisible(t.element(target), alignment: 0.5);
  await t.pump();
}

Future<void> _chooseGroup(WidgetTester t) async {
  final choice = find
      .ancestor(
        of: find.text('Rwanda group'),
        matching: find.byType(DropdownButtonFormField<String>),
      )
      .first;
  await _expose(t, choice);
  await t.tap(choice);
  await t.pump(const Duration(milliseconds: 350));
  await t.tap(find.text('Synthetic Rwanda group').last);
  await _settle(t);
}

Future<void> _choosePurpose(WidgetTester t, String text) async {
  final choice = find.descendant(
    of: _view,
    matching: find.byType(DropdownButtonFormField<AdminReceiptNoticeFamily>),
  );
  await _expose(t, choice);
  await t.tap(choice);
  await t.pump(const Duration(milliseconds: 350));
  await t.tap(find.text(text).last);
  await _settle(t);
}

void _noSend(_Harness h) {
  expect(
    h.requests.where(
      (r) => RegExp(
        r'/admin_(?:enqueue|ensure|reserve|dispatch|send|cancel|approve_receipt_successor|approve_receipt_notice_transport)',
      ).hasMatch(r.url.path),
    ),
    isEmpty,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets(
    'actual Settings composes its owner-only paged notice policy alongside denied independent controls',
    (t) async {
      final h = _Harness();
      await t.runAsync(h.start);
      addTearDown(() => t.runAsync(h.close));
      await t.pumpWidget(h.app(settings: true));
      await _settle(t);
      expect(find.text('Settings'), findsWidgets);
      expect(find.byType(AdminReceiptNoticePolicyHost), findsOneWidget);
      await _chooseGroup(t);
      expect(_within('Original recorded receipt facts only'), findsOneWidget);
      expect(h.calls('admin_inspect_receipt_notice_policy_v1'), hasLength(1));
      final reason = find.descendant(
        of: _view,
        matching: find.byType(TextField),
      );
      await _expose(t, reason);
      await t.enterText(reason, 'Reviewed immutable notice evidence');
      await _expose(t, _within('Record notice policy'));
      await t.tap(_within('Record notice policy'));
      await _settle(t);
      expect(h.calls('admin_approve_receipt_notice_policy_v1'), hasLength(1));
      expect(h.store.value, isNull);
      _noSend(h);
      expect(find.textContaining('PRIVATE_SEAM_CANARY'), findsNothing);
    },
  );
  testWidgets('composed Settings removes notice authority after owner loss', (
    t,
  ) async {
    final h = _Harness();
    await t.runAsync(h.start);
    addTearDown(() => t.runAsync(h.close));
    await t.pumpWidget(h.app(settings: true));
    await _settle(t);
    await _chooseGroup(t);
    expect(_view, findsOneWidget);
    h.owner = false;
    h.container.invalidate(adminIdentityProvider);
    await t.runAsync(() => h.container.read(adminIdentityProvider.future));
    await _settle(t);
    expect(_view, findsNothing);
    expect(find.byType(AdminReceiptNoticePolicyHost), findsNothing);
    expect(h.calls('admin_approve_receipt_notice_policy_v1'), isEmpty);
    _noSend(h);
  });
  testWidgets(
    'actual receipt detail forwards its fresh exact joined root and original snapshot',
    (t) async {
      final h = _Harness();
      await t.runAsync(h.start);
      addTearDown(() => t.runAsync(h.close));
      await t.pumpWidget(h.app(settings: false));
      await _settle(t);
      expect(find.text('SMS receipt detail'), findsWidgets);
      expect(h.calls('admin_get_hybrid_sms_receipt'), hasLength(1));
      expect(h.calls('admin_get_collect_investigation_v1'), hasLength(1));
      final host = t.widget<AdminReceiptNoticeContentHost>(
        find.byType(AdminReceiptNoticeContentHost),
      );
      expect(host.outboxId, h.root);
      expect(host.collectionId, _facts(h.sample)['collection_id']);
      expect(host.sourceSnapshotId, _facts(h.sample)['original_snapshot_id']);
      expect(host.reversalSnapshotId, isNull);
      final args =
          jsonDecode(
                h.calls('admin_inspect_receipt_notice_content_v1').single.body,
              )
              as Map;
      expect(args, {
        'p_outbox_id': h.root,
        'p_notice_family': 'duplicate_copy',
        'p_source_snapshot_id': _facts(h.sample)['original_snapshot_id'],
      });
      expect(
        _within((h.sample['candidate'] as Map)['body'] as String),
        findsOneWidget,
      );
      _noSend(h);
    },
  );
  testWidgets(
    'confirmed original content record invalidates joined investigation and hides the prior review while rereading',
    (t) async {
      final h = _Harness()
        ..holdAfterRecord = true
        ..nextInvestigationRelease = Completer<void>();
      await t.runAsync(h.start);
      addTearDown(() => t.runAsync(h.close));
      await t.pumpWidget(h.app(settings: false));
      await _settle(t);
      final body = (h.sample['candidate'] as Map)['body'] as String;
      expect(_within(body), findsOneWidget);
      final reason = find.descendant(
        of: _view,
        matching: find.byType(TextField),
      );
      await _expose(t, reason);
      await t.enterText(reason, 'Reviewed immutable notice evidence');
      await _expose(t, _within('Save immutable notice content'));
      await t.tap(_within('Save immutable notice content'));
      await _settle(t);
      expect(h.calls('admin_prepare_receipt_notice_content_v1'), hasLength(1));
      expect(h.store.value, isNull);
      expect(h.calls('admin_get_collect_investigation_v1'), hasLength(2));
      expect(find.byType(AdminReceiptNoticeContentHost), findsNothing);
      expect(find.text(body), findsNothing);
      h.nextInvestigationRelease!.complete();
      h.nextInvestigationRelease = null;
      await _settle(t);
      expect(h.calls('admin_inspect_receipt_notice_content_v1'), hasLength(2));
      expect(find.text(body), findsNothing);
      expect(h.calls('admin_prepare_receipt_notice_content_v1'), hasLength(1));
      _noSend(h);
    },
  );
  testWidgets(
    'compensation detail selects only its own actual reversal journal and never substitutes a foreign copy root',
    (t) async {
      final h = _Harness(reversal: true);
      await t.runAsync(h.start);
      addTearDown(() => t.runAsync(h.close));
      await t.pumpWidget(h.app(settings: false));
      await _settle(t);
      final host = t.widget<AdminReceiptNoticeContentHost>(
            find.byType(AdminReceiptNoticeContentHost),
          ),
          f = _facts(h.sample);
      expect(host.outboxId, f['root_outbox_id']);
      expect(host.sourceSnapshotId, f['original_snapshot_id']);
      expect(host.reversalSnapshotId, f['source_snapshot_id']);
      expect(
        find.text(
          (fixture('content-preview-duplicate_copy-rw')['candidate']
                  as Map)['body']
              as String,
        ),
        findsNothing,
      );
      await _choosePurpose(t, 'Collect ledger compensation');
      await _expose(t, _within('Refresh preview'));
      await t.tap(_within('Refresh preview'));
      await _settle(t);
      expect(
        jsonDecode(
          h.calls('admin_inspect_receipt_notice_content_v1').last.body,
        ),
        {
          'p_outbox_id': f['root_outbox_id'],
          'p_notice_family': 'reversal_notice',
          'p_source_snapshot_id': f['source_snapshot_id'],
        },
      );
      expect(
        _within((h.sample['candidate'] as Map)['body'] as String),
        findsOneWidget,
      );
      expect(h.calls('admin_prepare_receipt_notice_content_v1'), isEmpty);
      _noSend(h);
    },
  );
  testWidgets(
    'malformed financial join cannot compose a notice review or infer compensation',
    (t) async {
      final h = _Harness(reversal: true);
      h.joined['payment']['payment_id'] = _facts(
        fixture('content-preview-duplicate_copy-rw'),
      )['payment_id'];
      await t.runAsync(h.start);
      addTearDown(() => t.runAsync(h.close));
      await t.pumpWidget(h.app(settings: false));
      await _settle(t);
      expect(find.byType(AdminReceiptNoticeContentHost), findsNothing);
      expect(h.calls('admin_inspect_receipt_notice_content_v1'), isEmpty);
      expect(find.text('Investigation read failed'), findsOneWidget);
      _noSend(h);
    },
  );
  for (final settings in [true, false]) {
    testWidgets(
      'late notice response cannot reappear after current session loss on ${settings ? 'Settings' : 'receipt detail'}',
      (t) async {
        final h = _Harness()..noticeRelease = Completer<void>();
        await t.runAsync(h.start);
        addTearDown(() => t.runAsync(h.close));
        await t.pumpWidget(h.app(settings: settings));
        await _settle(t);
        if (settings) {
          await _chooseGroup(t);
        }
        expect(
          h.calls(
            settings
                ? 'admin_inspect_receipt_notice_policy_v1'
                : 'admin_inspect_receipt_notice_content_v1',
          ),
          hasLength(1),
        );
        await t.runAsync(
          () => h.client.auth.signOut(scope: CollectSignOutScope.local),
        );
        await _settle(t);
        h.noticeRelease!.complete();
        h.noticeRelease = null;
        await _settle(t);
        expect(_view, findsNothing);
        expect(
          find.text((h.sample['candidate'] as Map)['body'] as String),
          findsNothing,
        );
        expect(h.calls('admin_approve_receipt_notice_policy_v1'), isEmpty);
        expect(h.calls('admin_prepare_receipt_notice_content_v1'), isEmpty);
        _noSend(h);
      },
    );
  }
  testWidgets(
    'composed correction and resend display prerequisite denial without recording or transport authority',
    (t) async {
      final h = _Harness();
      await t.runAsync(h.start);
      addTearDown(() => t.runAsync(h.close));
      await t.pumpWidget(h.app(settings: false));
      await _settle(t);
      for (final p in [
        (
          'Correction',
          'Correction requires verified source evidence before content can be prepared.',
        ),
        (
          'Approved resend',
          'Resolve the original send outcome before an approved resend can be considered.',
        ),
      ]) {
        await _choosePurpose(t, p.$1);
        await _expose(t, _within('Refresh preview'));
        await t.tap(_within('Refresh preview'));
        await _settle(t);
        expect(_within(p.$2), findsOneWidget);
        expect(
          t
              .widget<FilledButton>(
                find.descendant(
                  of: _view,
                  matching: find.widgetWithText(
                    FilledButton,
                    'Save immutable notice content',
                  ),
                ),
              )
              .onPressed,
          isNull,
        );
      }
      expect(h.calls('admin_prepare_receipt_notice_content_v1'), isEmpty);
      _noSend(h);
    },
  );
}
