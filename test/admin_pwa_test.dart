import 'dart:io';

import 'package:collect_app/admin/admin_router.dart';
import 'package:collect_app/admin/admin_shell.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('admin routes cover the bank control plane exactly', () {
    expect(
      adminRoutePaths,
      containsAll(<String>[
        '/admin/groups',
        '/admin/members',
        '/admin/bank-destinations',
        '/admin/bank-destination-requests',
        '/admin/bank-intents',
        '/admin/bank-transactions',
        '/admin/bank-evidence',
        '/admin/reconciliation',
        '/admin/reconciliation-exceptions',
        '/admin/bank-allocation-requests',
        '/admin/bank-journal',
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
      '/admin/transactions',
      '/admin/payment-events',
      '/admin/allocations',
      '/admin/exceptions',
      '/admin/ledger',
      '/admin/receivers',
      '/admin/sms',
    ]) {
      expect(adminRoutePaths, isNot(contains(retired)), reason: retired);
    }
  });

  test('admin bank paths require their least-privilege capabilities', () {
    expect(
      adminRequiredPermissionForPath('/admin/bank-destinations'),
      'bank_details.read',
    );
    expect(
      adminRequiredPermissionForPath('/admin/bank-evidence/evidence-1'),
      'bank_evidence.read',
    );
    expect(
      adminRequiredPermissionForPath('/admin/reconciliation'),
      'bank_reconciliation.read',
    );
    expect(
      adminRequiredPermissionForPath('/admin/bank-journal/entry-1'),
      'bank_reconciliation.read',
    );
  });

  test('admin permission guard rejects an unauthorized bank queue', () {
    const identity = AdminIdentity(
      userId: 'admin-1',
      displayName: 'Group operator',
      roles: ['group_operator'],
      permissions: ['collections.read', 'users.read'],
    );

    expect(adminCanOpenPath(identity, '/admin/groups'), isTrue);
    expect(adminCanOpenPath(identity, '/admin/bank-evidence'), isFalse);
    expect(adminCanOpenPath(identity, '/admin/reconciliation'), isFalse);
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

  test(
    'admin shell exposes all bank operations without legacy payment queues',
    () {
      final source = File('lib/admin/admin_shell.dart').readAsStringSync();

      for (final label in <String>[
        'Bank details',
        'Bank detail approvals',
        'Transfer requests',
        'Bank transactions',
        'Bank evidence',
        'Reconciliation',
        'Reconciliation exceptions',
        'Allocation approvals',
        'Bank journal',
      ]) {
        expect(source, contains("'$label'"), reason: label);
      }
      expect(source, isNot(contains("'/admin/payment-intents'")));
      expect(source, isNot(contains("'/admin/sms'")));
      expect(source, isNot(contains("'/admin/receivers'")));
    },
  );

  test('admin overview reads bank exception and approval metrics', () {
    final source = File(
      'lib/admin/core/admin_overview_runtime.dart',
    ).readAsStringSync();

    expect(source, contains('admin_list_reconciliation_exceptions'));
    expect(source, contains('/admin/reconciliation-exceptions'));
    expect(source, contains('/admin/bank-allocation-requests'));
    expect(source, isNot(contains('/admin/payment-events')));
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

    expect(repository, contains('shouldCreateUser: false'));
    expect(login, contains('Resend WhatsApp OTP'));
    expect(login, contains('_startResendCooldown'));
    expect(login, contains('await repository.signOut()'));
    expect(guard, contains('onAuthStateChange'));
  });

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

    expect(RegExp(r"path: '/admin").allMatches(browserQa).length, 33);
    for (final route in <String>[
      '/admin/bank-destinations',
      '/admin/bank-destination-requests',
      '/admin/bank-intents',
      '/admin/bank-transactions',
      '/admin/bank-evidence',
      '/admin/reconciliation',
      '/admin/reconciliation-exceptions',
      '/admin/bank-allocation-requests',
      '/admin/bank-journal',
    ]) {
      expect(browserQa, contains("path: '$route'"), reason: route);
    }
    for (final retired in <String>[
      '/admin/payment-intents',
      '/admin/payment-events',
      '/admin/sms',
      '/admin/receivers',
    ]) {
      expect(browserQa, isNot(contains("path: '$retired'")), reason: retired);
    }
    expect(renderSmoke, contains('routeCount") == 33'));
    expect(renderSmoke, contains('screenshotCount") == 99'));
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
