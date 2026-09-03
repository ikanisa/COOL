import 'dart:io';

import 'package:collect_app/admin/admin_router.dart';
import 'package:collect_app/admin/admin_shell.dart';
import 'package:collect_app/admin/core/admin_display_formatters.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/collect_colors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('admin routes expose only four essential operations pages', () {
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
      '/admin/exceptions',
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

  test(
    'bank admin runtime includes maker-checker and reconciliation actions',
    () {
      final source = File(
        'lib/admin/core/bank_transfer_admin_runtime.dart',
      ).readAsStringSync();

      for (final action in <String>[
        'admin_propose_bank_destination',
        'admin_review_bank_destination_change',
        'admin_propose_bank_allocation',
        'admin_review_bank_allocation',
        "'ingest-bank-statement'",
        'admin_run_bank_reconciliation',
        'admin_resolve_reconciliation_exception',
        'admin_reveal_raw_bank_evidence',
        'admin_reopen_daily_bank_close',
      ]) {
        expect(source, contains(action), reason: action);
      }
      expect(source, contains('A checker must approve.'));
      expect(source, contains("'p_reason'"));
    },
  );

  test('admin shell keeps the essential operations navigation clean', () {
    final source = File('lib/admin/admin_shell.dart').readAsStringSync();

    for (final label in <String>[
      'Payees',
      'Transactions',
      'Reconciliations',
      'Ledgers',
    ]) {
      expect(source, contains("'$label'"), reason: label);
    }
    expect(source, isNot(contains("'/admin/payment-intents'")));
    expect(source, isNot(contains("'/admin/sms'")));
    expect(source, isNot(contains("'/admin/receivers'")));
    expect(source, isNot(contains("'/admin/bank-destinations'")));
    expect(source, isNot(contains("'/admin/momo-intents'")));
  });

  test('admin overview reads reconciliations and balanced ledgers', () {
    final source = File(
      'lib/admin/core/admin_overview_runtime.dart',
    ).readAsStringSync();

    expect(source, contains('admin_list_collect_reconciliations'));
    expect(source, contains('/admin/reconciliations'));
    expect(source, contains('admin_list_collect_ledgers'));
    expect(source, isNot(contains('/admin/payment-events')));
  });

  test('admin overview keeps queue health readable on narrow screens', () {
    final source = File(
      'lib/admin/core/admin_overview_runtime.dart',
    ).readAsStringSync();

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

  test('admin country scope covers Rwanda Malta and other countries', () async {
    expect(AdminCountryScope.values, <AdminCountryScope>[
      AdminCountryScope.all,
      AdminCountryScope.rwanda,
      AdminCountryScope.malta,
      AdminCountryScope.other,
    ]);

    final shell = File('lib/admin/admin_shell.dart').readAsStringSync();
    final listRuntime = File(
      'lib/admin/core/admin_list_runtime.dart',
    ).readAsStringSync();
    expect(shell, contains('_AdminCountrySwitcher'));
    expect(shell, contains('PopupMenuButton<AdminCountryScope>'));
    expect(listRuntime, contains('adminRowMatchesCountryScope'));
    expect(listRuntime, contains('countryCode: countryScope.rpcCode'));

    const repository = AdminEvidenceRepository();
    final members = await repository.list('admin_list_members', limit: 100);
    final countries = members.rows
        .map((row) => row.extra['country_code'])
        .toSet();
    expect(countries, containsAll(<String>{'RW', 'MT', 'GB'}));
    final maltaMembers = await repository.list(
      'admin_list_members',
      limit: 100,
      countryCode: 'MT',
    );
    expect(maltaMembers.rows, isNotEmpty);
    expect(
      maltaMembers.rows.every((row) => row.extra['country_code'] == 'MT'),
      isTrue,
    );
    expect(
      members.rows
          .where(
            (row) => adminRowMatchesCountryScope(row, AdminCountryScope.rwanda),
          )
          .every((row) => row.extra['country_code'] == 'RW'),
      isTrue,
    );
    expect(
      members.rows
          .where(
            (row) => adminRowMatchesCountryScope(row, AdminCountryScope.malta),
          )
          .every((row) => row.extra['country_code'] == 'MT'),
      isTrue,
    );
    expect(
      members.rows
          .where(
            (row) => adminRowMatchesCountryScope(row, AdminCountryScope.other),
          )
          .every((row) => row.extra['country_code'] == 'GB'),
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
      final tableSource = File(
        'lib/admin/core/admin_operation_tables.dart',
      ).readAsStringSync();
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
      expect(members.rows.first.extra['whatsapp_masked'], contains('•••'));
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
        'MoMo number',
        'Destination',
        'Access',
        'Owner',
        'Payment profile',
      ]) {
        expect(tableSource, contains("label: '$label'"), reason: label);
      }
      expect(tableSource, isNot(contains("label: 'Collect ID'")));
      for (final iconOnlyLabel in <String>[
        'WhatsApp',
        'Country',
        'Payment profile',
        'Groups',
      ]) {
        expect(
          RegExp(
            "label: '$iconOnlyLabel',\\s+iconOnly: true",
          ).hasMatch(tableSource),
          isTrue,
          reason: iconOnlyLabel,
        );
      }
      expect(tableSource, contains('IconButton.filledTonal'));
      expect(tableSource, contains('FontAwesomeIcons.whatsapp'));
      expect(tableSource, contains('_transactionDisplayAmount(row)'));
      expect(tableSource, contains("'whatsapp_masked'"));
      expect(tableSource, isNot(contains('hidePrimaryText: true')));
      expect(tableSource, contains('iconOnlyFields: true'));
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

  test(
    'admin record surfaces use icon-led labels without losing semantics',
    () {
      final operations = File(
        'lib/admin/core/admin_operation_tables.dart',
      ).readAsStringSync();
      final genericTable = File(
        'lib/admin/shared/components/admin_data_table.dart',
      ).readAsStringSync();
      final listRuntime = File(
        'lib/admin/core/admin_list_runtime.dart',
      ).readAsStringSync();
      final detail = File(
        'lib/admin/core/admin_detail_runtime.dart',
      ).readAsStringSync();
      final overview = File(
        'lib/admin/core/admin_overview_runtime.dart',
      ).readAsStringSync();

      expect(operations, contains('this.iconOnly = true'));
      expect(operations, contains('subtitleIcon: _groupPurposeIcon(row)'));
      expect(operations, contains('iconOnlyFields: true'));
      expect(operations, contains("'Open \$accountLabel account'"));
      expect(operations, contains("scopeLabel == 'Members'"));
      expect(operations, contains("row.status == 'admin'"));
      expect(operations, contains(': const SizedBox.shrink()'));
      expect(genericTable, contains('class _AdminDataColumnLabel'));
      expect(genericTable, contains("label: '\$label: \$value'"));
      expect(genericTable, contains('_adminFormatCurrency(row.amount)'));
      expect(genericTable, contains("currency == 'EUR'"));
      expect(genericTable, contains("label == 'Debit = credit'"));
      expect(
        genericTable,
        isNot(contains("DataColumn(label: Text('Record'))")),
      );
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
    },
  );

  test('group admin supports create, detail, activate, and deactivate', () {
    final router = File('lib/admin/admin_router.dart').readAsStringSync();
    final listRuntime = File(
      'lib/admin/core/admin_list_runtime.dart',
    ).readAsStringSync();
    final groupRuntime = File(
      'lib/admin/core/admin_group_runtime.dart',
    ).readAsStringSync();
    final detailRuntime = File(
      'lib/admin/core/admin_detail_runtime.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/20260901193000_admin_group_lifecycle.sql',
    ).readAsStringSync();

    expect(router, contains("'/admin/groups/:id'"));
    expect(listRuntime, contains('_AdminGroupWorkspaceActions'));
    expect(groupRuntime, contains('Create public group'));
    expect(groupRuntime, contains('admin_create_platform_public_group'));
    expect(groupRuntime, contains('locked permanently after creation'));
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
    expect(migration, contains('coalesce(member_count.active_groups, 0) = 0'));
    expect(migration, contains('coalesce(member_count.active_groups, 0) > 0'));
  });

  test(
    'evidence admin accepts only the dedicated local review credentials',
    () async {
      const repository = AdminEvidenceRepository();

      await repository.sendOtp(phone: adminEvidenceWhatsAppPhone);
      final identity = await repository.verifyOtp(
        phone: adminEvidenceWhatsAppPhone,
        otp: adminEvidenceOtp,
      );

      expect(identity?.phoneMasked, '+250***6816');
      expect(
        await repository.action('admin_reveal_raw_bank_evidence', const {}),
        {
          'sender': 'Bank evidence',
          'body': 'Raw bank evidence hidden in route evidence.',
        },
      );
      await expectLater(
        repository.sendOtp(phone: '+250788000000'),
        throwsFormatException,
      );
      await expectLater(
        repository.verifyOtp(phone: adminEvidenceWhatsAppPhone, otp: '000000'),
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
    expect(login, contains('Resend WhatsApp OTP'));
    expect(login, contains('_startResendCooldown'));
    expect(login, contains('await repository.signOut()'));
    expect(guard, contains('onAuthStateChange'));
    expect(shell, contains('ref.invalidate(adminAuthStateProvider)'));
    expect(shell, contains('ref.invalidate(adminAuthGuardProvider)'));
    expect(shell, contains('ref.invalidate(adminIdentityProvider)'));
  });

  test('admin login primary action keeps readable dark-surface contrast', () {
    final login = File(
      'lib/admin/core/admin_login_runtime.dart',
    ).readAsStringSync();
    final foreground = CollectColors.brandPaper.computeLuminance();
    final background = CollectColors.referenceChromeBlack.computeLuminance();
    final contrastRatio = (foreground + 0.05) / (background + 0.05);

    expect(login, contains('foregroundColor: colors.onImagePrimary'));
    expect(login, contains('color: colors.onImagePrimary'));
    expect(contrastRatio, greaterThanOrEqualTo(4.5));
  });

  test(
    'admin PWA refreshes immutable bundles during service-worker install',
    () {
      final releaseBuild = File(
        'scripts/admin_pwa_release_build.sh',
      ).readAsStringSync();

      expect(
        releaseBuild,
        contains('cache_schema_version = "fresh-install-v2"'),
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

    expect(RegExp(r"path: '/admin").allMatches(browserQa).length, 21);
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
    expect(renderSmoke, contains('routeCount") == 21'));
    expect(renderSmoke, contains('screenshotCount") == 63'));
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
