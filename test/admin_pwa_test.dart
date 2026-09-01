import 'dart:io';

import 'package:collect_app/admin/admin_router.dart';
import 'package:collect_app/admin/admin_shell.dart';
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

    expect(RegExp(r"path: '/admin").allMatches(browserQa).length, 20);
    for (final route in <String>[
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
    expect(renderSmoke, contains('routeCount") == 20'));
    expect(renderSmoke, contains('screenshotCount") == 60'));
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
