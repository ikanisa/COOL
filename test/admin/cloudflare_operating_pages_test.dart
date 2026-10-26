import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/admin/core/admin_pending_attempt_store.dart';
import 'package:collect_app/admin/core/cloudflare_admin_operating_pages.dart';
import 'package:collect_app/admin/core/cloudflare_admin_repository.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/admin/shared/components/admin_data_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'cloudflare_core_fixtures.dart';
import 'cloudflare_operating_repository_test.dart'
    show
        operatingRepository,
        operatingResponse,
        operatingReceipt,
        operatorOnlyDetail,
        otherId;
import '../support/legacy_backend_fixture.dart';

part 'cloudflare_operating_pages_cases/detail.dart';
part 'cloudflare_operating_pages_cases/mutations.dart';

Future<ProviderContainer> pumpOperating(
  WidgetTester tester,
  CloudflareAdminRepository repo,
  Widget child, {
  MemoryAdminPendingAttemptStorage? storage,
}) async {
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      adminRepositoryProvider.overrideWithValue(repo),
      cloudflareAdminSessionProvider.overrideWith((ref) => repo.session),
      if (storage != null)
        adminPendingAttemptStorageProvider.overrideWithValue(storage),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: child is CloudflareOperatingDetailPage
              ? child
              : SingleChildScrollView(child: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> reasonAndReview(WidgetTester tester) async {
  final reason = find.widgetWithText(TextFormField, 'Reason for this change');
  await tester.ensureVisible(reason);
  await tester.enterText(reason, 'Checked against the supporting evidence');
  final review = find.text('Review change');
  await tester.ensureVisible(review);
  await tester.tap(review);
  await tester.pumpAndSettle();
}

Future<void> clean(WidgetTester tester, CloudflareAdminRepository repo) async {
  repo.session.clear();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

const draftJournalForPosting = CloudflareOperatingDetail(
  type: 'journals',
  resource: {
    'id': coreId,
    'group_id': otherId,
    'version': 1,
    'description': 'Contribution journal',
    'status': 'draft',
    'created_by_admin_id': otherId,
    'edited_by_admin_id': otherId,
    'transaction_id': null,
    'allocation_id': null,
  },
  actorId: coreId,
  canManage: true,
  related: {},
  truncated: false,
);

Map<String, dynamic> journalPostingResponse({int count = 2}) => {
  'resource_type': 'journals',
  'resource': {...draftJournalForPosting.resource},
  'current_actor_id': coreId,
  'can_manage': true,
  'related': {
    'entries': [
      for (var i = 0; i < count; i++)
        <String, dynamic>{
          'id':
              '66666666-6666-4666-8666-${(i + 1).toString().padLeft(12, '0')}',
          'journal_id': coreId,
          'group_id': otherId,
          'account_id': i.isEven ? coreId : otherId,
          'line_number': i + 1,
          'account_code': i.isEven ? '1000' : '4000',
          'account_name': i.isEven
              ? 'Recorded receiver funds'
              : 'Contributions',
          'debit_rwf': i.isEven ? 1 : 0,
          'credit_rwf': i.isEven ? 0 : 1,
          'description': 'Reviewed line ${i + 1}',
        },
    ],
  },
  'related_pages': {
    'entries': <String, dynamic>{
      'total': count,
      'limit': 100,
      'offset': 0,
      'next_offset': null,
    },
  },
  'related_truncated': false,
};

Map<String, dynamic> postedJournalDetail() => {
  'resource_type': 'journals',
  'resource': {
    'id': coreId,
    'group_id': otherId,
    'version': 2,
    'description': 'Contribution journal',
    'status': 'posted',
    'created_by_admin_id': otherId,
    'edited_by_admin_id': otherId,
  },
  'current_actor_id': coreId,
  'can_manage': false,
  'related': {'entries': <Object>[]},
  'related_truncated': false,
};

const journalRecoveryPage = CloudflareOperatingDetailPage(
  type: 'journals',
  id: coreId,
  backPath: '/admin/ledgers',
);
const journalRecoveryKey = '44444444-4444-4444-8444-444444444444';

void retainJournalPost(ProviderContainer container) => container
    .read(adminPendingAttemptStoreProvider)
    .retain(
      family: 'operating-postjournal',
      resourceId: coreId,
      requestKey: journalRecoveryKey,
      permission: 'ledger.manage',
      intent: {
        'expected_version': 1,
        'reason': 'Independently reviewed supporting evidence',
      },
      schema: const AdminPendingAttemptSchema(
        fields: {'reason', 'expected_version'},
      ),
    );

void main() {
  _registerOperatingDetailPageCases();
  _registerOperatingMutationPageCases();
}
