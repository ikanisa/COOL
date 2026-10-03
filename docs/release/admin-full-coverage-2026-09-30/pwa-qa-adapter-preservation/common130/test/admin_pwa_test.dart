import 'dart:io';

import 'package:collect_app/admin/admin_router.dart';
import 'package:collect_app/admin/admin_shell.dart';
import 'package:collect_app/admin/core/admin_display_formatters.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/collect_colors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('admin routes expose supported operations pages', () {
    expect(
      adminRoutePaths,
      containsAll(<String>[
        '/admin/groups',
        '/admin/users',
        '/admin/members',
        '/admin/payees',
        '/admin/transactions',
        '/admin/transactions/:id',
        '/admin/reconciliations',
        '/admin/ledgers',
        '/admin/sms-receipts',
        '/admin/sms-receipts/:id',
        '/admin/sms-gateway',
        '/admin/automations',
        '/admin/exceptions',
        '/admin/notifications',
        '/admin/audit-logs',
        '/admin/settings',
        '/admin/feature-flags',
        '/admin/system-health',
        '/admin/admin-users',
      ]),
    );
    for (final retired in <String>[
      '/admin/payment-intents',
      '/admin/payment-events',
      '/admin/allocations',
      '/admin/ledger',
      '/admin/receivers',
      '/admin/sms',
      '/admin/momo-intents',
      '/admin/bank-destinations',
      '/admin/bank-transactions',
      '/admin/bank-journal',
    ]) {
      expect(adminRoutePaths, isNot(contains(retired)), reason: retired);
    }
  });

  test('admin operations paths require least-privilege capabilities', () {
    expect(adminRequiredPermissionForPath('/admin/payees'), 'receivers.read');
    expect(adminRequiredPermissionForPath('/admin/users'), 'users.read');
    expect(adminRequiredPermissionForPath('/admin/members'), 'users.read');
    expect(
      adminRequiredPermissionForPath('/admin/transactions/transaction-1'),
      'payments.read',
    );
    expect(
      adminRequiredPermissionForPath('/admin/reconciliations'),
      'payment_events.read',
    );
    expect(adminRequiredPermissionForPath('/admin/ledgers'), 'ledger.read');
    expect(
      adminRequiredPermissionForPath('/admin/sms-receipts/receipt-1'),
      'notifications.read',
    );
  });

  test('admin permission guard rejects an unauthorized operations queue', () {
    const identity = AdminIdentity(
      userId: 'admin-1',
      displayName: 'Group operator',
      roles: ['group_operator'],
      permissions: ['collections.read', 'users.read'],
    );

    expect(adminCanOpenPath(identity, '/admin/groups'), isTrue);
    expect(adminCanOpenPath(identity, '/admin/payees'), isFalse);
    expect(adminCanOpenPath(identity, '/admin/reconciliations'), isFalse);
  });

  test('retired bank admin runtime is absent', () {
    expect(
      File('lib/admin/core/bank_transfer_admin_runtime.dart').existsSync(),
      isFalse,
    );
    final source = File('lib/admin/admin_router.dart').readAsStringSync();
    expect(source, isNot(contains('/admin/bank-destinations')));
  });

  test('admin shell keeps the essential operations navigation clean', () {
    final source = File('lib/admin/admin_shell.dart').readAsStringSync();

    for (final label in <String>[
      'Payees',
      'Transactions',
      'Reconciliations',
      'Ledgers',
      'SMS receipts',
    ]) {
      expect(source, contains("'$label'"), reason: label);
    }
    expect(source, isNot(contains("'/admin/payment-intents'")));
    expect(source, isNot(contains("'/admin/sms'")));
    expect(source, isNot(contains("'/admin/receivers'")));
    expect(source, isNot(contains("'/admin/bank-destinations'")));
    expect(source, isNot(contains("'/admin/momo-intents'")));
  });

  test('feature-phone SMS receipt queue stays masked in admin', () async {
    const repository = AdminEvidenceRepository();
    final queue = await repository.list('admin_list_hybrid_sms_receipts');
    final detail = await repository.detail(
      'admin_get_hybrid_sms_receipt',
      queue.rows.first.id,
    );
    final router = File('lib/admin/admin_router.dart').readAsStringSync();
    final listSpecs = File(
      'lib/admin/core/admin_list_specs.dart',
    ).readAsStringSync();
    final detailSpecs = File(
      'lib/admin/core/admin_detail_specs.dart',
    ).readAsStringSync();

    expect(queue.rows, hasLength(4));
    expect(queue.rows.first.extra['country_code'], 'RW');
    expect(queue.rows.first.subtitle, contains('•••'));
    expect(detail['destination_masked'], '+250•••200');
    expect(
      detail['message_body'],
      'Hidden until a current fenced operator claim',
    );
    expect(router, contains('admin_list_hybrid_sms_receipts'));
    expect(router, contains('admin_get_hybrid_sms_receipt'));
    expect(listSpecs, contains('Exact body claim-gated'));
    expect(detailSpecs, contains('current fenced operator claim'));
  });

  test('admin overview reads reconciliations and balanced ledgers', () {
    final source = [
      'lib/admin/core/admin_overview_runtime.dart',
      'lib/admin/core/admin_overview_components.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');

    expect(source, contains('admin_list_collect_reconciliations'));
    expect(source, contains('/admin/reconciliations'));
    expect(source, contains('admin_list_collect_ledgers'));
    expect(source, isNot(contains('/admin/payment-events')));
  });

  test('admin overview keeps queue health readable on narrow screens', () {
    final source = [
      'lib/admin/core/admin_overview_runtime.dart',
      'lib/admin/core/admin_overview_components.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');

    expect(source, contains("return 'Next business day';"));
    expect(source, contains('textAlign: TextAlign.end'));
    expect(source, contains('softWrap: true'));
    expect(source, contains('Flexible('));
  });

  test('admin access is one combined audited permission set', () {
    final detail = File(
      'lib/admin/core/admin_platform_access.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/20260901210000_admin_single_access_role.sql',
    ).readAsStringSync();

    expect(detail, contains("'admin_set_user_access'"));
    expect(detail, contains("'p_active': active"));
    expect(detail, isNot(contains('Role access')));
    expect(detail, isNot(contains('_AdminRoleActionChip')));
    expect(migration, contains('cross join public.admin_permissions'));
    expect(migration, contains("role.name <> 'platform_owner'"));
    expect(migration, contains('admin.access.activated'));
    expect(migration, contains('admin.access.deactivated'));
  });

  test('admin country scope includes Rwanda only', () async {
    expect(AdminCountryScope.values, <AdminCountryScope>[
      AdminCountryScope.rwanda,
    ]);
    final shell = File('lib/admin/admin_shell.dart').readAsStringSync();
    expect(shell, contains('Rwanda'));
    const repository = AdminEvidenceRepository();
    final members = await repository.list('admin_list_members', limit: 100);
    expect(members.rows, isNotEmpty);
    expect(
      members.rows.every((row) => row.extra['country_code'] == 'RW'),
      isTrue,
    );
  });

  test('admin hides the redundant Collect transaction prefix', () {
    expect(
      adminCompactTransactionReference('COLLECT-AB1202-6802'),
      'AB1202-6802',
    );
    expect(
      adminCompactTransactionReference('Checker B. • COLLECT-AB1202-6802'),
      'Checker B. • AB1202-6802',
    );
    expect(adminCompactTransactionReference('AB1202-6802'), 'AB1202-6802');
  });

  test('payees workspace exposes the two confirmed official routes', () async {
    const repository = AdminEvidenceRepository();
    final result = await repository.list('admin_list_collect_payees');
    final payeeRuntime = File(
      'lib/admin/core/admin_payee_runtime.dart',
    ).readAsStringSync();

    expect(result.total, 2);
    expect(result.rows.map((row) => row.title), [
      'IKANISA LTD',
      'Rayon Sports FC',
    ]);
    expect(result.rows[0].subtitle, contains('Buri Munsi'));
    expect(result.rows[0].subtitle, contains('code 41258'));
    expect(result.rows[1].subtitle, contains('Gikundiro'));
    expect(result.rows[1].subtitle, contains('code 008000'));
    expect(result.rows.every((row) => row.status == 'active'), isTrue);
    expect(payeeRuntime, contains('Create payee'));
    expect(
      payeeRuntime,
      contains('Only the official payee name can be edited'),
    );
    expect(payeeRuntime, contains('They can never be edited afterward'));
  });

  test(
    'operations workspaces expose complete permission-safe row context',
    () async {
      const repository = AdminEvidenceRepository();
      final transactions = await repository.list(
        'admin_list_collect_transactions',
      );
      final groups = await repository.list('admin_list_collections');
      final members = await repository.list('admin_list_members');
      final users = await repository.list('admin_list_non_member_users');
      final tableSource = [
        'lib/admin/core/admin_operation_tables.dart',
        'lib/admin/core/admin_operation_components.dart',
      ].map((path) => File(path).readAsStringSync()).join('\n');
      final migration = File(
        'supabase/migrations/20260901183000_admin_operations_tables.sql',
      ).readAsStringSync();

      expect(transactions.rows, hasLength(12));
      expect(transactions.rows.first.extra['reference'], isNotNull);
      expect(transactions.rows.first.extra['sender_masked'], isNotNull);
      expect(transactions.rows.first.extra['group_name'], isNotNull);
      expect(transactions.rows.first.extra['payee_label'], isNotNull);
      expect(transactions.rows.first.extra['rail'], 'rw_momo');

      expect(groups.rows.first.title, 'Buri Munsi');
      expect(groups.rows[1].title, 'Gikundiro');
      expect(
        groups.rows.take(2).every((row) => row.status == 'public_approved'),
        isTrue,
      );
      expect(groups.rows.skip(2).first.status, 'private');
      expect(groups.rows.first.extra['active_members'], isNotNull);
      expect(groups.rows.first.extra['receiver_label'], 'IKANISA LTD');

      expect(members.rows.first.title, startsWith('Collect ID '));
      expect(members.rows.first.extra['account_state'], 'feature_phone');
      expect(members.rows.first.extra['whatsapp_masked'], isNull);
      expect(members.rows.first.extra['momo_masked'], contains('•••'));
      expect(members.rows.first.extra['country_code'], 'RW');
      expect(members.rows.first.extra['active_groups'], isNotNull);
      expect(members.rows.first.extra['active_groups'], greaterThan(0));
      expect(members.rows.first.extra, isNot(contains('revolut_account')));
      expect(users.rows, hasLength(4));
      expect(
        users.rows.every((row) => row.extra['active_groups'] == 0),
        isTrue,
      );

      for (final label in <String>[
        'Reference',
        'Receipt sender',
        'Destination',
        'Verification',
        'Allocation',
        'Ledger',
        'Notification',
        'Access',
        'Owner',
        'Payment profile',
      ]) {
        expect(tableSource, contains("label: '$label'"), reason: label);
      }
      expect(tableSource, isNot(contains("label: 'Collect ID'")));
      for (final visibleLabel in <String>[
        'WhatsApp',
        'Country',
        'Payment profile',
        'Groups',
      ]) {
        expect(
          tableSource,
          contains("label: '$visibleLabel'"),
          reason: visibleLabel,
        );
      }
      final headingSource = tableSource.substring(
        tableSource.indexOf('class _AdminColumnLabel'),
        tableSource.indexOf('class _AdminPrimaryCell'),
      );
      expect(headingSource, contains('Text(label)'));
      expect(headingSource, contains('label: label'));
      expect(headingSource, isNot(contains('iconOnly')));
      expect(tableSource, contains('IconButton.filledTonal'));
      expect(tableSource, contains('FontAwesomeIcons.whatsapp'));
      expect(tableSource, contains('_transactionDisplayAmount(row)'));
      expect(tableSource, contains("'whatsapp_masked'"));
      expect(tableSource, isNot(contains('hidePrimaryText: true')));
      expect(tableSource, contains("label: '\${data.label}: \$value'"));
      expect(tableSource, contains('message: data.label'));
      expect(migration, contains('public.mask_phone(profile.whatsapp_phone)'));
      expect(migration, contains('public.mask_phone(profile.momo_number)'));
      expect(
        migration,
        isNot(contains("'revolut_account', profile.revolut_account")),
      );
    },
  );

  test('admin record surfaces show labels and preserve field semantics', () {
    final operations = [
      'lib/admin/core/admin_operation_tables.dart',
      'lib/admin/core/admin_operation_components.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');
    final genericTable = File(
      'lib/admin/shared/components/admin_data_table.dart',
    ).readAsStringSync();
    final listRuntime = File(
      'lib/admin/core/admin_list_runtime.dart',
    ).readAsStringSync();
    final detail = File(
      'lib/admin/core/admin_detail_runtime.dart',
    ).readAsStringSync();
    final overview = [
      'lib/admin/core/admin_overview_runtime.dart',
      'lib/admin/core/admin_overview_components.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');

    expect(operations, contains('subtitleIcon: _groupPurposeIcon(row)'));
    expect(operations, contains("'Open \$accountLabel account'"));
    expect(operations, contains("scopeLabel == 'Members'"));
    expect(operations, contains("row.status == 'admin'"));
    expect(operations, contains(': const SizedBox.shrink()'));
    expect(genericTable, contains('class _AdminDataColumnLabel'));
    expect(genericTable, contains("label: '\$label: \$value'"));
    expect(genericTable, contains('adminFormatRwfAmount(row.amount)'));
    expect(genericTable, isNot(contains("currency == 'EUR'")));
    expect(genericTable, contains("label == 'Debit = credit'"));
    expect(genericTable, isNot(contains("DataColumn(label: Text('Record'))")));
    expect(genericTable, isNot(contains("child: const Text('Open record')")));
    expect(detail, contains('_adminDetailFieldGlyph('));
    expect(detail, contains('label: label'));
    expect(detail, contains('value: value'));
    expect(detail, contains('Icons.schedule_send_outlined'));
    expect(detail, contains('Icons.error_outline_rounded'));
    expect(overview, contains('String _compactAge(String value)'));
    expect(listRuntime, contains('IconButton.outlined'));
    expect(listRuntime, contains('IconButton.filledTonal'));
    expect(listRuntime, isNot(contains("child: const Text('Edit')")));
    expect(listRuntime, isNot(contains("child: const Text('Reparse')")));
  });

  test('group admin supports create, detail, activate, and deactivate', () {
    final router = File('lib/admin/admin_router.dart').readAsStringSync();
    final listRuntime = File(
      'lib/admin/core/admin_list_runtime.dart',
    ).readAsStringSync();
    final groupRuntime = File(
      'lib/admin/core/admin_group_runtime.dart',
    ).readAsStringSync();
    final rosterFileParser = File(
      'lib/admin/core/roster_file_parser.dart',
    ).readAsStringSync();
    final detailRuntime = File(
      'lib/admin/core/admin_detail_runtime.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/20260901193000_admin_group_lifecycle.sql',
    ).readAsStringSync();
    final assistedMigration = File(
      'supabase/migrations/20260903085000_hybrid_roster_import_control_plane.sql',
    ).readAsStringSync();
    final rosterFunction = File(
      'supabase/functions/prepare-roster-import/handler.ts',
    ).readAsStringSync();
    final openAiRoster = File(
      'supabase/functions/_shared/openai_roster.ts',
    ).readAsStringSync();

    expect(router, contains("'/admin/groups/:id'"));
    expect(listRuntime, contains('_AdminGroupWorkspaceActions'));
    expect(groupRuntime, contains('Create public group'));
    expect(groupRuntime, contains('admin_create_platform_public_group'));
    expect(groupRuntime, contains('locked permanently after creation'));
    expect(groupRuntime, contains('Create assisted group'));
    final rosterDialog = File(
      'lib/admin/core/admin_roster_dialog.dart',
    ).readAsStringSync();
    final rosterGateway = File(
      'lib/admin/core/admin_roster_import.dart',
    ).readAsStringSync();
    expect(rosterDialog, contains('Prepare preview'));
    expect(rosterDialog, contains("'csv'"));
    expect(rosterDialog, contains("'txt'"));
    expect(rosterDialog, contains("'xlsx'"));
    expect(rosterDialog, contains("'pdf'"));
    expect(rosterDialog, contains('Use OpenAI for this file'));
    expect(rosterDialog, contains('Save reviewed rows'));
    expect(rosterDialog, contains('Next rows'));
    expect(rosterFileParser, contains('FormulaCellValue'));
    expect(rosterGateway, contains('admin_commit_roster_import'));
    expect(rosterGateway, contains('admin_review_roster_import'));
    expect(
      assistedMigration,
      contains('creates a private assisted group, its share code'),
    );
    expect(rosterFunction, contains('readRosterSource'));
    expect(rosterFunction, contains('apiKey'));
    expect(rosterFunction, contains('model'));
    expect(rosterFunction, contains('ai_consent'));
    expect(openAiRoster, contains('store: false'));
    expect(openAiRoster, isNot(contains('tools:')));
    expect(rosterFunction, contains('processing_method'));
    expect(detailRuntime, contains('admin_set_group_active'));
    expect(detailRuntime, contains("label: 'Activate'"));
    expect(detailRuntime, contains("label: 'Deactivate'"));
    expect(migration, contains('collection.platform_public.created'));
    expect(migration, contains('collection.activated'));
    expect(migration, contains('collection.deactivated'));
    expect(migration, contains('route_immutable'));
  });

  test('users and members are separate admin populations', () {
    final shell = File('lib/admin/admin_shell.dart').readAsStringSync();
    final router = File('lib/admin/admin_router.dart').readAsStringSync();
    final migration = File(
      'supabase/migrations/20260901194500_admin_users_and_members.sql',
    ).readAsStringSync();

    expect(shell, contains("'Users'"));
    expect(shell, contains("'/admin/users'"));
    expect(router, contains('admin_list_non_member_users'));
    expect(router, contains('admin_list_members'));
    expect(router, contains('admin_get_member_record'));
    expect(migration, contains('coalesce(member_count.active_groups, 0) = 0'));
    expect(migration, contains('coalesce(member_count.active_groups, 0) > 0'));
  });

  test('member directory combines app and feature-phone identities safely', () {
    final migration = File(
      'supabase/migrations/20260903091500_hybrid_member_directory_views.sql',
    ).readAsStringSync();
    final detailSpecs = File(
      'lib/admin/core/admin_detail_specs.dart',
    ).readAsStringSync();

    expect(migration, contains("'account_state'"));
    expect(migration, contains("then 'feature_phone' else 'app'"));
    expect(migration, contains('public.mask_phone(identity.momo_number)'));
    expect(migration, contains('collect_hybrid.member_account_claims'));
    expect(migration, contains("'public_id', roster.public_id"));
    expect(detailSpecs, contains('Registered MoMo name'));
    expect(detailSpecs, contains('admin_get_member_record'));
  });

  test(
    'evidence admin accepts only the dedicated local review credentials',
    () async {
      const repository = AdminEvidenceRepository();

      await repository.sendEmailOtp(email: adminEvidenceEmail);
      final identity = await repository.verifyEmailOtp(
        email: adminEvidenceEmail,
        otp: adminEvidenceOtp,
      );

      expect(identity?.displayName, 'Collect evidence admin');
      await expectLater(
        repository.sendEmailOtp(email: 'other@collect.example'),
        throwsFormatException,
      );
      await expectLater(
        repository.verifyEmailOtp(email: adminEvidenceEmail, otp: '000000'),
        throwsFormatException,
      );
    },
  );

  test('production admin OTP is enrollment-safe and supports resend', () {
    final repository = File(
      'lib/admin/core/admin_runtime.dart',
    ).readAsStringSync();
    final login = File(
      'lib/admin/core/admin_login_runtime.dart',
    ).readAsStringSync();
    final guard = File(
      'lib/admin/core/admin_auth_guard.dart',
    ).readAsStringSync();
    final shell = File('lib/admin/admin_shell.dart').readAsStringSync();

    expect(repository, contains('shouldCreateUser: false'));
    expect(login, contains('Resend email OTP'));
    expect(login, contains('_startResendCooldown'));
    expect(login, contains('await repository.signOut()'));
    expect(guard, contains('onAuthStateChange'));
    expect(shell, contains('ref.invalidate(adminAuthStateProvider)'));
    expect(shell, contains('ref.invalidate(adminAuthGuardProvider)'));
    expect(shell, contains('ref.invalidate(adminIdentityProvider)'));
  });

  test('admin login primary action keeps readable black-surface contrast', () {
    final login = File(
      'lib/admin/core/admin_login_runtime.dart',
    ).readAsStringSync();
    final foreground = CollectColors.publicWhite.computeLuminance();
    final background = CollectColors.referenceChromeBlack.computeLuminance();
    final contrastRatio = (foreground + 0.05) / (background + 0.05);

    expect(login, contains('foregroundColor: CollectColors.publicWhite'));
    expect(login, contains('color: CollectColors.publicWhite'));
    expect(contrastRatio, greaterThanOrEqualTo(4.5));
  });

  test(
    'admin PWA refreshes immutable bundles during service-worker install',
    () {
      final releaseBuild = [
        'scripts/admin_pwa_release_build.sh',
        'scripts/templates/admin_pwa_service_worker.js',
      ].map((path) => File(path).readAsStringSync()).join('\n');

      expect(
        releaseBuild,
        contains('cache_schema_version = "fresh-install-v3"'),
      );
      expect(releaseBuild, contains("cache: 'reload'"));
      expect(releaseBuild, contains('await cache.put(request, response)'));
    },
  );

  test(
    'local Supabase review auth is isolated from production provisioning',
    () {
      final config = File('supabase/config.toml').readAsStringSync();
      final seed = File('supabase/seed.sql').readAsStringSync();
      final productionBoundary = File(
        'supabase/migrations/20260612103000_disable_browser_admin_bootstrap.sql',
      ).readAsStringSync();

      expect(config, contains('[auth.sms.test_otp]'));
      expect(config, contains('250788767816 = "123456"'));
      expect(seed, contains('local_seed_review_admin_access'));
      expect(seed, contains("where name = 'platform_owner'"));
      expect(seed, contains('Local Admin PWA review account'));
      expect(
        productionBoundary,
        contains('admin_bootstrap_whatsapp_operator is disabled'),
      );
      expect(productionBoundary, contains('to service_role'));
    },
  );

  test('authenticated browser QA covers the current admin route matrix', () {
    final browserQa = File(
      'scripts/admin_pwa_browser_qa.mjs',
    ).readAsStringSync();
    final renderSmoke = File(
      'scripts/admin_pwa_authenticated_render_smoke.sh',
    ).readAsStringSync();

    expect(RegExp(r"path: '/admin").allMatches(browserQa).length, 23);
    expect(browserQa, contains("path: '/admin/sms-receipts'"));
    expect(browserQa, contains("path: '/admin/sms-receipts/sms-receipt-1'"));
    for (final route in <String>[
      '/admin/users',
      '/admin/payees',
      '/admin/transactions',
      '/admin/reconciliations',
      '/admin/ledgers',
    ]) {
      expect(browserQa, contains("path: '$route'"), reason: route);
    }
    for (final retired in <String>[
      '/admin/payment-intents',
      '/admin/payment-events',
      '/admin/sms',
      '/admin/receivers',
      '/admin/momo-intents',
      '/admin/bank-destinations',
    ]) {
      expect(browserQa, isNot(contains("path: '$retired'")), reason: retired);
    }
    expect(renderSmoke, contains('routeCount") == 23'));
    expect(renderSmoke, contains('viewportCount") == 4'));
    expect(renderSmoke, contains('screenshotCount") == 92'));
  });

  test('Admin PWA runtime probe fails closed on stalled CDP commands', () {
    final runtime = File(
      'scripts/admin_pwa_runtime_smoke.mjs',
    ).readAsStringSync();

    expect(runtime, contains(r'Timed out waiting for ${method} response'));
    expect(runtime, contains('this.pending.delete(id)'));
    expect(runtime, contains('clearTimeout(timeout)'));
  });

  test('Admin PWA cache excludes Cloudflare deployment metadata', () {
    final releaseBuild = File(
      'scripts/admin_pwa_release_build.sh',
    ).readAsStringSync();

    expect(releaseBuild, contains('"_headers"'));
    expect(releaseBuild, contains('"_redirects"'));
    expect(
      releaseBuild,
      contains('must not precache Cloudflare _headers metadata'),
    );
    expect(
      releaseBuild,
      contains('must not precache the redirected /index.html path'),
    );
  });

  test('Admin PWA self-hosts CanvasKit for reliable first load', () {
    final bootstrap = File('web/flutter_bootstrap.js').readAsStringSync();
    final releaseBuild = File(
      'scripts/admin_pwa_release_build.sh',
    ).readAsStringSync();

    expect(bootstrap, contains("canvasKitBaseUrl: 'canvaskit/'"));
    expect(releaseBuild, contains('must self-host CanvasKit'));
  });

  test(
    'Admin queue SLA compatibility fails soft for an older hosted function',
    () {
      final runtime = File(
        'lib/admin/core/admin_runtime.dart',
      ).readAsStringSync();

      expect(runtime, contains('unsupported admin queue sla key'));
    },
  );
}
