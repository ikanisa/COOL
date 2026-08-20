import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String readAll(List<String> paths) =>
    paths.map((path) => File(path).readAsStringSync()).join('\n');

void main() {
  const migrationPath =
      'supabase/migrations/20260820162240_bank_transfer_only_financial_control_plane.sql';
  final cutover = File(migrationPath).readAsStringSync();
  final config = File('supabase/config.toml').readAsStringSync();
  final repository = readAll([
    'lib/shared/repositories/collect_repository.dart',
    'lib/shared/repositories/collect_repository_live_reader.dart',
    'lib/shared/repositories/collect_repository_providers.dart',
  ]);
  final memberJourney = readAll([
    'lib/features/payments/contribution_flow_screen.dart',
    'lib/features/settings/bank_transfer_settings_screen.dart',
    'lib/core/payments/revolut_launcher.dart',
  ]);
  final adminSurface = readAll([
    'lib/admin/admin_router.dart',
    'lib/admin/admin_shell.dart',
    'lib/admin/core/admin_runtime.dart',
    'lib/admin/core/bank_transfer_admin_runtime.dart',
    'lib/admin/core/admin_detail_specs.dart',
  ]);

  test('only the reviewed bank and notification Edge Functions remain', () {
    final functions =
        Directory('supabase/functions')
            .listSync()
            .whereType<Directory>()
            .where(
              (directory) => File('${directory.path}/index.ts').existsSync(),
            )
            .map((directory) => directory.path.split('/').last)
            .toList()
          ..sort();

    expect(functions, [
      'auth-send-whatsapp-otp',
      'dispatch-notifications',
      'ingest-bank-email',
      'ingest-bank-sms',
      'ingest-bank-statement',
      'send-notification',
    ]);
    for (final retired in [
      'stripe-create-customer',
      'stripe-create-diaspora-contribution',
      'stripe-create-setup-intent',
      'stripe-webhook',
      'ingest-payment-sms',
      'parse-payment-sms',
      'verify-play-integrity',
    ]) {
      expect(
        File('supabase/functions/$retired/index.ts').existsSync(),
        isFalse,
      );
    }
  });

  test('Stripe persistence is retired with a fail-closed data guard', () {
    expect(cutover, contains('Stripe retirement requires a reviewed export'));
    for (final table in [
      'stripe_customers',
      'stripe_payment_methods',
      'diaspora_contribution_intents',
      'stripe_webhook_events',
    ]) {
      expect(cutover, contains('drop table if exists public.$table'));
    }
    expect(File('supabase/functions/_shared/stripe.ts').existsSync(), isFalse);
  });

  test('bank-transfer control plane owns all financial evidence and state', () {
    for (final table in [
      'bank_transfer_destinations',
      'bank_destination_change_requests',
      'bank_transfer_intents',
      'raw_payment_evidence',
      'bank_evidence_events',
      'bank_transactions',
      'payment_evidence_links',
      'bank_transaction_allocations',
      'bank_statement_imports',
      'bank_statement_lines',
      'reconciliation_runs',
      'reconciliation_matches',
      'reconciliation_exceptions',
      'daily_bank_closes',
      'journal_entries',
      'journal_lines',
      'bank_allocation_change_requests',
    ]) {
      expect(cutover, contains('create table public.$table'));
      expect(
        cutover,
        contains('alter table public.$table enable row level security'),
      );
    }
    expect(cutover, contains("'bank_transfer_v1'"));
    expect(cutover, contains("'EUR'"));
    expect(cutover, contains("'sepa_credit_transfer'"));
  });

  test(
    'placeholder bank details stay disabled until maker-checker approval',
    () {
      expect(cutover, contains("'PLACEHOLDER — DO NOT TRANSFER'"));
      expect(cutover, contains("'PLACEHOLDER BANK'"));
      expect(cutover, contains("'bank_transfer_v1',"));
      expect(cutover, contains('admin_propose_bank_destination'));
      expect(cutover, contains('admin_review_bank_destination_change'));
      expect(cutover, contains('proposed_by'));
      expect(cutover, contains('reviewed_by <> proposed_by'));
      expect(cutover, contains('request.proposed_by = auth.uid()'));
      expect(
        cutover,
        contains('prohibits approving your own bank destination'),
      );
    },
  );

  test(
    'member journey creates unique EUR references and exposes masked IBAN',
    () {
      for (final rpc in [
        'get_bank_transfer_destination',
        'create_bank_transfer_intent',
        'list_current_user_bank_transfer_intents',
        'get_bank_transfer_intent',
        'mark_bank_transfer_handoff_opened',
        'cancel_bank_transfer_intent',
        'list_current_user_bank_contributions',
        'list_current_user_bank_collection_summaries',
      ]) {
        expect(cutover, contains('function public.$rpc'));
      }
      expect(cutover, contains('normalize_iban'));
      expect(cutover, contains('mask_iban'));
      expect(cutover, contains('transfer_reference text unique not null'));
      expect(cutover, contains("and status = 'active'"));
      expect(cutover, contains('and not is_placeholder'));
      expect(repository, contains("'create_bank_transfer_intent'"));
      expect(repository, contains("'get_bank_transfer_destination'"));
      expect(repository, contains("'mark_bank_transfer_handoff_opened'"));
      expect(repository, contains("'list_current_user_bank_contributions'"));
    },
  );

  test(
    'Revolut handoff opens the app without fabricating a payment result',
    () {
      expect(memberJourney, contains("Uri.parse('revolut://')"));
      expect(memberJourney, contains('LaunchMode.externalApplication'));
      expect(memberJourney, contains('https://www.revolut.com/app/'));
      expect(memberJourney, contains('markBankTransferHandoffOpened'));
      expect(memberJourney, contains("label: 'IBAN'"));
      expect(memberJourney, contains("label: 'Exact reference'"));
      expect(memberJourney, isNot(contains('sepa_debit')));
      expect(memberJourney, isNot(contains('Payment successful')));
    },
  );

  test(
    'production Android app has no financial SMS or phone-call permission',
    () {
      final manifest = File(
        'android/app/src/production/AndroidManifest.xml',
      ).readAsStringSync();
      final activity = File(
        'android/app/src/main/kotlin/app/cool/mobile/MainActivity.kt',
      ).readAsStringSync();
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();

      expect(manifest, isNot(contains('android.permission.RECEIVE_SMS')));
      expect(manifest, isNot(contains('android.permission.READ_SMS')));
      expect(manifest, isNot(contains('android.permission.CALL_PHONE')));
      expect(activity, isNot(contains('collect/ussd')));
      expect(activity, isNot(contains('collect/play_integrity')));
      expect(gradle, isNot(contains('com.google.android.play:integrity')));
      expect(
        File('lib/core/payments/momo_ussd_launcher.dart').existsSync(),
        isFalse,
      );
      expect(
        File('lib/core/security/play_integrity_service.dart').existsSync(),
        isFalse,
      );
    },
  );

  test('bank SMS is admin-authenticated and bank email requires HMAC', () {
    final sharedHmac = File(
      'supabase/functions/_shared/hmac.ts',
    ).readAsStringSync();
    final email = File(
      'supabase/functions/ingest-bank-email/index.ts',
    ).readAsStringSync();
    final sms = File(
      'supabase/functions/ingest-bank-sms/index.ts',
    ).readAsStringSync();

    expect(sharedHmac, contains('verifyTimestampedHmac'));
    expect(sharedHmac, contains('constantTimeEqual'));
    expect(sharedHmac, contains('5 * 60 * 1000'));
    expect(email, contains('BANK_EMAIL_INGEST_HMAC_SECRET'));
    expect(sms, contains('requireUser'));
    expect(email, contains('ingest_bank_evidence'));
    expect(sms, contains('ingest_bank_evidence'));
    expect(email, isNot(contains('OPENAI_API_KEY')));
    expect(sms, isNot(contains('OPENAI_API_KEY')));
  });

  test('evidence parsing is deterministic and data-minimising', () {
    final parser = File(
      'supabase/functions/_shared/bank_evidence.ts',
    ).readAsStringSync();
    expect(parser, contains('parseBankEvidence'));
    expect(parser, contains('amount_minor'));
    expect(parser, contains('currency'));
    expect(parser, contains('transfer_reference'));
    expect(parser, contains('bank_transaction_id'));
    expect(parser, isNot(contains('api.openai.com')));
    expect(parser, isNot(contains('sender_name')));
  });

  test(
    'raw evidence ingestion is idempotent and links independent sources',
    () {
      expect(cutover, contains('body_hash'));
      expect(cutover, contains('unique (channel, body_hash)'));
      expect(cutover, contains('bank_transaction_id'));
      expect(cutover, contains('payment_evidence_links'));
      expect(cutover, contains('on conflict'));
      expect(cutover, contains('ingest_bank_evidence'));
      expect(cutover, contains('raw_body'));
      expect(cutover, contains('revoke all on public.raw_payment_evidence'));
    },
  );

  test('daily reconciliation controls confirmation and balanced posting', () {
    expect(cutover, contains('run_daily_bank_reconciliation'));
    expect(cutover, contains("set status = 'reconciled'"));
    expect(cutover, contains("'bank_receipt'"));
    expect(cutover, contains("'debit'"));
    expect(cutover, contains("'credit'"));
    expect(cutover, contains('journal_entries_immutable'));
    expect(cutover, contains('journal_lines_immutable'));
    expect(cutover, contains('Posted financial journals are immutable'));
    expect(cutover, contains('reconciliation_exceptions'));
    expect(cutover, contains('daily_bank_closes'));
    expect(cutover, contains('admin_reopen_daily_bank_close'));
    expect(cutover, contains('cron.schedule'));
  });

  test('manual allocations require separate proposer and approver', () {
    expect(cutover, contains('admin_propose_bank_allocation'));
    expect(cutover, contains('admin_review_bank_allocation'));
    expect(cutover, contains('bank_allocation_change_requests'));
    expect(cutover, contains('bank_allocations.propose'));
    expect(cutover, contains('bank_allocations.approve'));
    expect(cutover, contains('prohibits approving your own allocation'));
  });

  test(
    'raw evidence reveal and exception handling are permissioned and audited',
    () {
      expect(cutover, contains('admin_reveal_raw_bank_evidence'));
      expect(cutover, contains('bank_evidence.raw.reveal'));
      expect(cutover, contains('admin_resolve_reconciliation_exception'));
      expect(cutover, contains('bank_reconciliation.manage'));
      expect(cutover, contains('create_audit_log'));
      expect(cutover, contains('p_reason'));
    },
  );

  test('admin routes cover destinations through immutable journals', () {
    for (final route in [
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
      expect(adminSurface, contains(route));
      expect(cutover, contains(route));
    }
    for (final action in [
      'admin_propose_bank_destination',
      'admin_review_bank_destination_change',
      'ingest-bank-statement',
      'admin_run_bank_reconciliation',
      'admin_propose_bank_allocation',
      'admin_review_bank_allocation',
      'admin_resolve_reconciliation_exception',
      'admin_reveal_raw_bank_evidence',
      'admin_reopen_daily_bank_close',
    ]) {
      expect(adminSurface, contains(action));
    }
  });

  test('bank statement import supports reviewed machine-readable formats', () {
    final parser = File(
      'supabase/functions/_shared/bank_statement.ts',
    ).readAsStringSync();
    final ingest = File(
      'supabase/functions/ingest-bank-statement/index.ts',
    ).readAsStringSync();
    expect(parser, contains('parseBankStatement'));
    expect(parser, contains('CSV'));
    expect(parser, contains('MT940'));
    expect(parser, contains('CAMT'));
    expect(ingest, contains('admin_import_bank_statement'));
    expect(ingest, contains('requireUser'));
  });

  test('member and admin bank records are realtime invalidation areas', () {
    final realtime = File(
      'lib/core/supabase/realtime_invalidation.dart',
    ).readAsStringSync();
    expect(realtime, contains('bank_intents'));
    expect(realtime, contains('bank_transactions'));
    expect(realtime, contains('bank_reconciliation'));
    expect(realtime, contains('bank_evidence'));
    expect(repository, contains('RealtimeInvalidationSubscription'));
  });

  test(
    'notification dispatch supports FCM and APNs without logging credentials',
    () {
      final dispatch = File(
        'supabase/functions/dispatch-notifications/index.ts',
      ).readAsStringSync();
      final fcm = File('supabase/functions/_shared/fcm.ts').readAsStringSync();
      final apns = File(
        'supabase/functions/_shared/apns.ts',
      ).readAsStringSync();
      expect(dispatch, contains('createFcmAccessToken'));
      expect(dispatch, contains('sendFcmMessage'));
      expect(dispatch, contains('sendApnsMessage'));
      expect(dispatch, contains('FCM_SERVICE_ACCOUNT_JSON'));
      expect(fcm, contains('fcm.googleapis.com/v1/projects'));
      expect(apns, contains('privateKeyBase64'));
      expect(dispatch, contains('APNS_PRIVATE_KEY_BASE64'));
      expect(dispatch, isNot(contains('console.log(secret')));
    },
  );

  test('Edge auth configuration matches each ingestion boundary', () {
    expect(config, contains('[functions.ingest-bank-sms]'));
    expect(config, contains('[functions.ingest-bank-email]'));
    expect(config, contains('[functions.ingest-bank-statement]'));
    expect(config, isNot(contains('[functions.stripe-webhook]')));
    expect(config, isNot(contains('[functions.ingest-payment-sms]')));
  });

  test('production scripts require bank and notification secrets only', () {
    final readiness = File(
      'scripts/supabase_production_readiness.sh',
    ).readAsStringSync();
    final deploy = File('scripts/supabase_deploy.sh').readAsStringSync();
    final authContract = File(
      'scripts/collect_edge_auth_contract_uat.sh',
    ).readAsStringSync();
    final scripts = '$readiness\n$deploy\n$authContract';

    expect(scripts, contains('BANK_EMAIL_INGEST_HMAC_SECRET'));
    expect(scripts, contains('ingest-bank-sms'));
    expect(scripts, contains('ingest-bank-statement'));
    expect(scripts, contains('FCM_SERVICE_ACCOUNT_JSON'));
    expect(scripts, isNot(contains('STRIPE_SECRET_KEY')));
    expect(scripts, isNot(contains('STRIPE_WEBHOOK_SECRET')));
    expect(scripts, isNot(contains('PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON')));
    expect(deploy, contains('ingest-bank-email'));
    expect(deploy, contains('ingest-bank-sms'));
    expect(deploy, contains('ingest-bank-statement'));
  });
}
