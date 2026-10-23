import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/cloudflare_admin_gateway_pages.dart';
import 'package:collect_app/admin/core/cloudflare_admin_email_pages.dart';
import 'package:collect_app/admin/core/cloudflare_admin_receipt_pages.dart';
import 'package:collect_app/admin/core/cloudflare_admin_repository.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/admin/shared/components/admin_data_table.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'cloudflare_core_fixtures.dart';
import 'cloudflare_integrations_fixtures.dart';
import 'cloudflare_operating_repository_test.dart'
    show operatingResponse, operatingReceipt, otherId;

final _semanticsDisposers = <VoidCallback>[];

Future<void> pumpIntegration(
  WidgetTester tester,
  CloudflareAdminRepository repo,
  Widget child, {
  bool page = false,
  double width = 1300,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 1300);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final semantics = tester.ensureSemantics();
  _semanticsDisposers.add(semantics.dispose);
  final container = ProviderContainer(
    overrides: [
      adminRepositoryProvider.overrideWithValue(repo),
      cloudflareAdminSessionProvider.overrideWith((ref) => repo.session),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: page ? child : SingleChildScrollView(child: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> cleanIntegration(
  WidgetTester tester,
  CloudflareAdminRepository repo,
) async {
  for (final dispose in _semanticsDisposers) {
    dispose();
  }
  _semanticsDisposers.clear();
  repo.session.clear();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('delayed source content cannot appear on a different receipt', (
    tester,
  ) async {
    final pendingContent = Completer<http.Response>();
    final selectedId = ValueNotifier(coreId);
    addTearDown(selectedId.dispose);
    final repo = await integrationRepository((request) async {
      if (request.url.path.endsWith('/content')) return pendingContent.future;
      return operatingResponse({
        ...integrationReceiptDetail(),
        'resource': {
          ...integrationReceipt(),
          'id': request.url.path.split('/').last,
        },
      });
    });
    await pumpIntegration(
      tester,
      repo,
      ValueListenableBuilder<String>(
        valueListenable: selectedId,
        builder: (_, id, _) => CloudflareMemberReceiptDetailPage(id: id),
      ),
      page: true,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Audit reason for access and review'),
      'Review original member submission',
    );
    await tester.tap(find.text('Reveal submitted content'));
    await tester.pump();
    selectedId.value = otherId;
    await tester.pumpAndSettle();
    pendingContent.complete(operatingResponse(integrationContent()));
    await tester.pumpAndSettle();
    expect(find.text(otherId), findsOneWidget);
    expect(find.bySemanticsLabel('Submission ID: $otherId'), findsOneWidget);
    expect(find.text(integrationBody), findsNothing);
    expect(find.text('Hide submitted content'), findsNothing);
    expect(find.text('Reveal submitted content'), findsOneWidget);
    await cleanIntegration(tester, repo);
  });
  testWidgets('receipt classification needs confirmation and clears source', (
    tester,
  ) async {
    var writes = 0;
    final repo = await integrationRepository((request) async {
      if (request.url.path.endsWith('/content')) {
        return operatingResponse(integrationContent());
      }
      if (request.method == 'POST') {
        writes++;
        expect(jsonDecode(request.body), {
          'expected_version': 1,
          'outcome': 'reviewed',
          'transaction_id': null,
          'reason': 'Review original member submission',
        });
        return operatingResponse(
          operatingReceipt(type: 'member_receipts', version: 2),
        );
      }
      return operatingResponse(integrationReceiptDetail());
    });
    await pumpIntegration(
      tester,
      repo,
      const CloudflareMemberReceiptDetailPage(id: coreId),
      page: true,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Audit reason for access and review'),
      'Review original member submission',
    );
    await tester.tap(find.text('Reveal submitted content'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Review classification'));
    await tester.tap(find.text('Review classification'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    final confirmation = find.byWidgetPredicate(
      (widget) =>
          widget is AdminDataTable &&
          widget.tableLabel == 'Receipt classification confirmation',
    );
    expect(confirmation, findsOneWidget);
    expect(
      find.descendant(of: confirmation, matching: find.text('Classification')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: confirmation, matching: find.text('Reason')),
      findsOneWidget,
    );
    expect(find.textContaining('transaction stays pending'), findsOneWidget);
    await tester.tap(find.text('Confirm classification'));
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(find.text('Change saved'), findsOneWidget);
    expect(find.text(integrationBody), findsNothing);
    await cleanIntegration(tester, repo);
  });
  testWidgets(
    'gateway activation requires fingerprint review and retains actual configuration failure',
    (tester) async {
      var writes = 0;
      final repo = await integrationRepository((request) async {
        writes++;
        return operatingResponse({
          'error': 'gateway_identity_policy_unavailable',
        }, status: 503);
      });
      final detail = CloudflareGatewayDetail(
        device: CloudflareGatewayDevice.parse(
          integrationDevice(detail: true),
          detail: true,
        ),
        canManage: true,
        heartbeats: [],
        enrollment: Map<String, dynamic>.from(
          integrationGatewayDetail()['enrollment'] as Map,
        ),
        truncated: false,
      );
      await pumpIntegration(
        tester,
        repo,
        CloudflareGatewayActionForm(
          action: CloudflareGatewayAction.activate,
          detail: detail,
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Reason for device change'),
        'Reviewed device fingerprints',
      );
      await tester.tap(find.text('Review device change'));
      await tester.pumpAndSettle();
      expect(writes, 0);
      expect(
        find.textContaining('Compare the key and certificate'),
        findsOneWidget,
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.tap(find.text('Review device change'));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is AdminDataTable &&
              widget.tableLabel == 'Device change confirmation',
        ),
        findsOneWidget,
      );
      expect(find.text('Expected Key Sha256'), findsOneWidget);
      await tester.tap(find.text('Confirm device change'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(
        find.textContaining('Gateway identity policy is not configured'),
        findsOneWidget,
      );
      expect(find.text('Change saved'), findsNothing);
      expect(find.text('Check request status'), findsOneWidget);
      await cleanIntegration(tester, repo);
    },
  );
  testWidgets('gateway unavailable is never a successful empty device list', (
    tester,
  ) async {
    final repo = await integrationRepository(
      (_) async => operatingResponse({}, status: 503),
    );
    await pumpIntegration(
      tester,
      repo,
      const CloudflareGatewayListPage(),
      page: true,
    );
    expect(find.text('No enrolled devices'), findsNothing);
    expect(
      find.text('The records could not be loaded. Refresh and try again.'),
      findsOneWidget,
    );
    await cleanIntegration(tester, repo);
  });
  testWidgets(
    'email dispatch shows accepted uncertain suppressed counts without claiming delivery',
    (tester) async {
      var writes = 0;
      final repo = await integrationRepository((_) async {
        writes++;
        return operatingResponse({
          ...operatingReceipt(type: 'email_dispatch', id: otherId),
          'accepted': 1,
          'uncertain': 2,
          'suppressed': 3,
        });
      });
      await pumpIntegration(tester, repo, const CloudflareEmailDispatchForm());
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Reason for manual dispatch'),
        'Process currently queued emails',
      );
      await tester.tap(find.text('Review batch'));
      await tester.pumpAndSettle();
      expect(writes, 0);
      await tester.tap(find.text('Confirm batch'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(find.text('Provider accepted'), findsOneWidget);
      expect(find.text('Uncertain'), findsOneWidget);
      expect(find.text('Suppressed'), findsOneWidget);
      expect(
        find.textContaining('does not confirm inbox delivery'),
        findsOneWidget,
      );
      await cleanIntegration(tester, repo);
    },
  );
  testWidgets('unconfirmed email batch offers receipt check but no retry', (
    tester,
  ) async {
    var writes = 0;
    final repo = await integrationRepository((request) async {
      if (request.method == 'POST') {
        writes++;
        throw http.ClientException('lost connection');
      }
      return operatingResponse({'status': 'not_found'});
    });
    await pumpIntegration(tester, repo, const CloudflareEmailDispatchForm());
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Reason for manual dispatch'),
      'Process currently queued emails',
    );
    await tester.tap(find.text('Review batch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm batch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check dispatch receipt'));
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(
      find.textContaining('Do not retry an uncertain send'),
      findsOneWidget,
    );
    expect(find.text('Retry identical request'), findsNothing);
    expect(find.text('Review batch'), findsNothing);
    await cleanIntegration(tester, repo);
  });
  testWidgets(
    'receipt content is revealed intentionally with audit reason and can be cleared',
    (tester) async {
      var contentReads = 0;
      final repo = await integrationRepository((request) async {
        if (request.url.path.endsWith('/content')) {
          contentReads++;
          expect(
            request.headers['X-Collect-Review-Reason'],
            'Review original member submission',
          );
          return operatingResponse(integrationContent());
        }
        return operatingResponse(integrationReceiptDetail());
      });
      await pumpIntegration(
        tester,
        repo,
        const CloudflareMemberReceiptDetailPage(id: coreId),
        page: true,
      );
      expect(find.text(integrationBody), findsNothing);
      expect(contentReads, 0);
      await tester.tap(find.text('Reveal submitted content'));
      await tester.pumpAndSettle();
      expect(contentReads, 0);
      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          'Audit reason for access and review',
        ),
        'Review original member submission',
      );
      await tester.tap(find.text('Reveal submitted content'));
      await tester.pumpAndSettle();
      expect(contentReads, 1);
      expect(find.text(integrationBody), findsOneWidget);
      await tester.tap(find.text('Hide submitted content'));
      await tester.pumpAndSettle();
      expect(find.text(integrationBody), findsNothing);
      await cleanIntegration(tester, repo);
    },
  );
  testWidgets(
    'gateway detail separates identity, enrollment and heartbeat facts',
    (tester) async {
      final repo = await integrationRepository(
        (_) async => operatingResponse({
          ...integrationGatewayDetail(),
          'related': {
            'heartbeats': [
              {
                'observation_id': otherId,
                'request_id': coreId,
                'issued_at': coreDate,
                'reported_at': coreDate,
                'ingested_at': coreDate,
                'sms_permission': true,
                'network': 'validated',
                'telephony': 'ready',
                'sim_selected': false,
                'sim_revision_sha256': null,
                'local_pause': true,
                'carrier_proof': false,
                'send_authority': false,
              },
            ],
          },
        }),
      );
      await pumpIntegration(
        tester,
        repo,
        const CloudflareGatewayDetailPage(id: coreId),
        page: true,
        width: 320,
        scale: 2,
      );
      expect(find.byType(AdminDataTable), findsNWidgets(3));
      expect(find.byType(ListTile), findsNothing);
      final tables = tester
          .widgetList<AdminDataTable>(find.byType(AdminDataTable))
          .toList();
      expect(tables.map((table) => table.tableLabel), [
        'Gateway identity',
        'Enrollment response',
        'Recent heartbeats',
      ]);
      expect(
        tables[0].columns!.map((column) => column.label),
        containsAll([
          'Device',
          'State',
          'Version',
          'Public key',
          'SMS sending authority',
        ]),
      );
      expect(tables[1].columns!.map((column) => column.label), [
        'Contract version',
        'Device ID',
        'Installation ID',
        'Key SHA-256',
        'Signing certificate SHA-256',
      ]);
      expect(
        tables[2].columns!.map((column) => column.label),
        containsAll([
          'Reported',
          'Issued',
          'Ingested',
          'Network',
          'Telephony',
          'SMS permission observed',
          'Locally paused',
          'Observation ID',
          'Request ID',
        ]),
      );
      expect(
        find.bySemanticsLabel('Public key: $integrationPublicKey'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Network: Validated'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Carrier delivery proven: No'),
        findsNWidgets(2),
      );
      expect(find.text('Activate device'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await cleanIntegration(tester, repo);
    },
  );
  testWidgets(
    'receipt detail and review history retain separate authoritative facts',
    (tester) async {
      final repo = await integrationRepository(
        (_) async => operatingResponse({
          ...integrationReceiptDetail(manage: false),
          'resource': {...integrationReceipt(), 'display_name': null},
          'related': {
            'reviews': [
              {
                'id': otherId,
                'outcome': 'rejected',
                'transaction_id': null,
                'evidence_id': null,
                'actor_admin_id': coreId,
                'reason':
                    'Submission did not contain a verifiable payment reference',
                'reviewed_at': coreDate,
              },
            ],
          },
        }),
        staff: true,
      );
      await pumpIntegration(
        tester,
        repo,
        const CloudflareMemberReceiptDetailPage(id: coreId),
        page: true,
        width: 320,
        scale: 2,
      );
      expect(find.byType(AdminDataTable), findsNWidgets(2));
      expect(find.byType(ListTile), findsNothing);
      expect(
        find.bySemanticsLabel('Member name: Not recorded'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Source SHA-256: $integrationBodyHash'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Classification: Rejected'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Reason: Submission did not contain a verifiable payment reference',
        ),
        findsOneWidget,
      );
      expect(find.text('Collect member'), findsNothing);
      expect(find.text('Reveal submitted content'), findsNothing);
      expect(tester.takeException(), isNull);
      await cleanIntegration(tester, repo);
    },
  );
  for (final gateway in [true, false]) {
    testWidgets(
      'staff ${gateway ? 'gateway' : 'email'} table exposes no manage controls',
      (tester) async {
        var requests = 0;
        final repo = await integrationRepository((request) async {
          requests++;
          if (gateway) {
            return operatingResponse(integrationGatewayDetail(manage: false));
          }
          return operatingResponse({
            'rows': [integrationEmail()],
            'total': 1,
            'limit': 25,
            'offset': 0,
          });
        }, staff: true);
        await pumpIntegration(
          tester,
          repo,
          gateway
              ? const CloudflareGatewayDetailPage(id: coreId)
              : const CloudflareEmailPage(),
          page: true,
        );
        expect(
          find.byType(AdminDataTable),
          gateway ? findsNWidgets(2) : findsOneWidget,
        );
        expect(find.text('Activate device'), findsNothing);
        expect(find.text('Revoke device'), findsNothing);
        expect(find.text('Run queued batch'), findsNothing);
        if (!gateway) {
          expect(find.text('Provider accepted'), findsNWidgets(2));
          expect(
            find.bySemanticsLabel('Delivery recorded: Not recorded'),
            findsOneWidget,
          );
        }
        expect(requests, 1);
        expect(tester.takeException(), isNull);
        await cleanIntegration(tester, repo);
      },
    );
  }
  testWidgets(
    'staff sees metadata and cannot reveal receipt or dispatch emails',
    (tester) async {
      final repo = await integrationRepository(
        (_) async => operatingResponse(integrationReceiptDetail(manage: false)),
        staff: true,
      );
      await pumpIntegration(
        tester,
        repo,
        const CloudflareMemberReceiptDetailPage(id: coreId),
        page: true,
      );
      expect(find.text('Reveal submitted content'), findsNothing);
      expect(
        find.textContaining(
          'Source content and classification require administrator',
        ),
        findsOneWidget,
      );
      await cleanIntegration(tester, repo);
    },
  );
}
