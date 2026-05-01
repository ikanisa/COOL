import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const authPath = 'supabase/functions/_shared/auth.ts';
  const fcmPath = 'supabase/functions/_shared/fcm.ts';
  const parseMemberListPath = 'supabase/functions/parse-member-list/index.ts';
  const sendNotificationPath = 'supabase/functions/send-notification/index.ts';
  const campaignMigrationPath =
      'supabase/migrations/20260501133000_notification_campaign_approval_hardening.sql';
  const securityContractPath = 'supabase/tests/security_privacy_contract.sql';

  late String authTs;
  late String fcmTs;
  late String parseMemberListTs;
  late String sendNotificationTs;
  late String campaignMigrationSql;
  late String securityContractSql;

  setUpAll(() {
    authTs = File(authPath).readAsStringSync();
    fcmTs = File(fcmPath).readAsStringSync();
    parseMemberListTs = File(parseMemberListPath).readAsStringSync();
    sendNotificationTs = File(sendNotificationPath).readAsStringSync();
    campaignMigrationSql = File(campaignMigrationPath).readAsStringSync();
    securityContractSql = File(securityContractPath).readAsStringSync();
  });

  test('cron secrets use constant-time comparison', () {
    expect(
      authTs,
      contains('constantTimeEquals(configuredSecret, providedSecret)'),
    );
    expect(authTs, isNot(contains('providedSecret !== configuredSecret')));
  });

  test(
    'member-list OCR validates upload type and size before external AI calls',
    () {
      expect(parseMemberListTs, contains('MAX_MEMBER_LIST_BYTES'));
      expect(parseMemberListTs, contains('ALLOWED_MEMBER_LIST_MIME_TYPES'));
      expect(parseMemberListTs, contains('Unsupported member-list file type'));
      expect(parseMemberListTs, contains('Invalid base64 upload payload'));
      expect(
        parseMemberListTs,
        contains('Member-list upload exceeds the 5 MiB limit'),
      );
      expect(parseMemberListTs, isNot(contains('errorText')));
    },
  );

  test(
    'topic notifications require campaign approval and avoid raw internal errors',
    () {
      expect(sendNotificationTs, contains('campaign_approval_id'));
      expect(sendNotificationTs, contains('notification_campaign_approvals'));
      expect(
        sendNotificationTs,
        contains('Approved campaign record is required'),
      );
      expect(
        sendNotificationTs,
        contains('Campaign approval does not match notification copy'),
      );
      expect(sendNotificationTs, contains('readFcmData'));
      expect(sendNotificationTs, contains('Notification send failed.'));
    },
  );

  test('FCM provider errors are sanitized before durable logging', () {
    expect(fcmTs, contains(r'error: `${response.status}: ${errorCode}`'));
    expect(fcmTs, isNot(contains('errorBody}`')));
  });

  test('campaign approval migration enforces RLS and auditability', () {
    expect(campaignMigrationSql, contains('notification_campaign_approvals'));
    expect(campaignMigrationSql, contains('enable row level security'));
    expect(
      campaignMigrationSql,
      contains('notification_campaign_approvals_admin_all'),
    );
    expect(
      campaignMigrationSql,
      contains('audit_notification_campaign_approval_change'),
    );
    expect(campaignMigrationSql, contains('public.admin_audit_log'));
    expect(campaignMigrationSql, contains('campaign_approval_id'));
    expect(
      campaignMigrationSql,
      contains('notification_campaign_approval_expiry_check'),
    );
    expect(
      campaignMigrationSql,
      contains('notification_events_topic_approval_check'),
    );
  });

  test(
    'security pgTAP contract covers campaign and notification boundaries',
    () {
      expect(
        securityContractSql,
        contains('notification campaign approvals have RLS enabled'),
      );
      expect(
        securityContractSql,
        contains('campaign approvals are admin-managed'),
      );
      expect(
        securityContractSql,
        contains('campaign approval changes are audit logged'),
      );
      expect(
        securityContractSql,
        contains('users only read their own notification events'),
      );
      expect(
        securityContractSql,
        contains('topic notification events require campaign approval linkage'),
      );
    },
  );
}
